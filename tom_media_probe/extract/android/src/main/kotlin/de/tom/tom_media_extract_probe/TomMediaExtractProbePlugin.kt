package de.tom.tom_media_extract_probe

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Audio and still frames out of a video with the platform's own classes:
 * [MediaExtractor] and [MediaCodec] decode the sound, [MediaMetadataRetriever]
 * returns a frame at a time. The decoder gives the track's own sample rate and
 * channel count, so the conversion to the ones asked for is done here.
 */
class TomMediaExtractProbePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "tom_media_probe/extract")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("arguments", "path is missing", null)
            return
        }
        val rate = call.argument<Int>("sampleRate") ?: 16000
        val channels = call.argument<Int>("channels") ?: 1
        executor.execute {
            try {
                val value: Any = when (call.method) {
                    "info" -> info(path)
                    "audioToWav" -> audioToWav(path, call.argument<String>("out")!!, rate, channels)
                    "audioPcm" -> {
                        val out = ByteArrayOutputStream()
                        decodeAudio(
                            path, rate, channels,
                            (call.argument<Number>("startMs") ?: 0).toLong(),
                            call.argument<Number>("durationMs")?.toLong(),
                        ) { out.write(it) }
                        out.toByteArray()
                    }
                    "frame" -> frame(
                        path,
                        (call.argument<Number>("timeMs") ?: 0).toLong(),
                        call.argument<Int>("maxWidth") ?: 0,
                        call.argument<Boolean>("exact") ?: true,
                    )
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (error: Throwable) {
                main.post { result.error("extract", error.toString(), null) }
            }
        }
    }

    private fun info(path: String): Map<String, Any> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            val out = HashMap<String, Any>()
            out["hasVideo"] = false
            out["hasAudio"] = false
            var durationUs = 0L
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationUs = maxOf(durationUs, format.getLong(MediaFormat.KEY_DURATION))
                }
                if (mime.startsWith("video/") && out["hasVideo"] == false) {
                    out["hasVideo"] = true
                    out["videoCodec"] = mime
                    out["width"] = format.getInteger(MediaFormat.KEY_WIDTH)
                    out["height"] = format.getInteger(MediaFormat.KEY_HEIGHT)
                } else if (mime.startsWith("audio/") && out["hasAudio"] == false) {
                    out["hasAudio"] = true
                    out["audioCodec"] = mime
                    out["sampleRate"] = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    out["channels"] = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
            }
            if (out["hasVideo"] == false && out["hasAudio"] == false) {
                throw IllegalStateException("MediaExtractor finds no audio or video track")
            }
            out["durationMs"] = durationUs / 1000
            return out
        } finally {
            extractor.release()
        }
    }

    /** Decodes the sound and hands every converted block to [sink]; answers the bytes. */
    private fun decodeAudio(
        path: String,
        rate: Int,
        channels: Int,
        startMs: Long,
        durationMs: Long?,
        sink: (ByteArray) -> Unit,
    ): Long {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val index = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalStateException("the file has no audio track MediaExtractor can read")
            val format = extractor.getTrackFormat(index)
            extractor.selectTrack(index)
            val startUs = startMs * 1000
            val endUs = if (durationMs != null) (startMs + durationMs) * 1000 else Long.MAX_VALUE
            if (startUs > 0) {
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            }
            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0)
            codec.start()
            var sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var sourceChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val converter = Converter(rate, channels)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var bytes = 0L
            while (!outputDone) {
                if (!inputDone) {
                    val input = codec.dequeueInputBuffer(10_000)
                    if (input >= 0) {
                        val buffer = codec.getInputBuffer(input)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0 || extractor.sampleTime > endUs) {
                            codec.queueInputBuffer(
                                input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(input, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val output = codec.dequeueOutputBuffer(info, 10_000)
                if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val changed = codec.outputFormat
                    sourceRate = changed.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    sourceChannels = changed.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else if (output >= 0) {
                    if (info.size > 0 && info.presentationTimeUs >= startUs &&
                        info.presentationTimeUs < endUs
                    ) {
                        val buffer = codec.getOutputBuffer(output)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val samples = ShortArray(info.size / 2)
                        buffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples)
                        val converted = converter.convert(samples, sourceRate, sourceChannels)
                        sink(converted)
                        bytes += converted.size
                    }
                    codec.releaseOutputBuffer(output, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }
            return bytes
        } finally {
            try {
                codec?.stop()
            } catch (_: Throwable) {
            }
            codec?.release()
            extractor.release()
        }
    }

    private fun wavHeader(dataBytes: Long, rate: Int, channels: Int): ByteArray {
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt((36 + dataBytes).toInt())
        header.put("WAVEfmt ".toByteArray())
        header.putInt(16)
        header.putShort(1)
        header.putShort(channels.toShort())
        header.putInt(rate)
        header.putInt(rate * channels * 2)
        header.putShort((channels * 2).toShort())
        header.putShort(16)
        header.put("data".toByteArray())
        header.putInt(dataBytes.toInt())
        return header.array()
    }

    private fun audioToWav(path: String, out: String, rate: Int, channels: Int): Map<String, Any> {
        RandomAccessFile(out, "rw").use { file ->
            file.setLength(0)
            file.write(wavHeader(0, rate, channels))
            val bytes = decodeAudio(path, rate, channels, 0, null) { file.write(it) }
            file.seek(0)
            file.write(wavHeader(bytes, rate, channels))
            return mapOf(
                "frames" to bytes / (2 * channels),
                "sampleRate" to rate,
                "channels" to channels,
            )
        }
    }

    private fun frame(path: String, timeMs: Long, maxWidth: Int, exact: Boolean): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            var width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: 0
            var height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
            if (rotation == 90 || rotation == 270) {
                val swap = width
                width = height
                height = swap
            }
            val option = if (exact) {
                MediaMetadataRetriever.OPTION_CLOSEST
            } else {
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            }
            val scaled = maxWidth in 1 until width && Build.VERSION.SDK_INT >= 27
            val bitmap = (
                if (scaled) {
                    retriever.getScaledFrameAtTime(
                        timeMs * 1000, option, maxWidth, height * maxWidth / width,
                    )
                } else {
                    retriever.getFrameAtTime(timeMs * 1000, option)
                }
                ) ?: throw IllegalStateException("MediaMetadataRetriever returned no frame")
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            val answer = mapOf(
                "jpeg" to out.toByteArray(),
                "width" to bitmap.width,
                "height" to bitmap.height,
            )
            bitmap.recycle()
            return answer
        } finally {
            retriever.release()
        }
    }
}

/**
 * Mixes 16-bit interleaved samples to [targetChannels] and resamples them to
 * [targetRate] by linear interpolation, keeping its place between blocks.
 */
private class Converter(private val targetRate: Int, private val targetChannels: Int) {
    /** Position of the next output frame, in frames of the current block. */
    private var position = 0.0
    private var last: FloatArray? = null

    fun convert(source: ShortArray, sourceRate: Int, sourceChannels: Int): ByteArray {
        val frames = source.size / sourceChannels
        if (frames == 0) {
            return ByteArray(0)
        }
        val mixed = FloatArray(frames * targetChannels)
        for (f in 0 until frames) {
            if (targetChannels == 1) {
                var sum = 0f
                for (c in 0 until sourceChannels) {
                    sum += source[f * sourceChannels + c]
                }
                mixed[f] = sum / sourceChannels
            } else {
                for (c in 0 until targetChannels) {
                    mixed[f * targetChannels + c] =
                        source[f * sourceChannels + (c % sourceChannels)].toFloat()
                }
            }
        }
        val out = ByteArrayOutputStream()
        fun put(value: Float) {
            val sample = value.toInt().coerceIn(-32768, 32767)
            out.write(sample and 0xff)
            out.write((sample shr 8) and 0xff)
        }
        if (sourceRate == targetRate) {
            for (value in mixed) {
                put(value)
            }
            return out.toByteArray()
        }
        val step = sourceRate.toDouble() / targetRate
        val previous = last
        if (previous == null) {
            position = 0.0
        }
        // Frame -1 is the last frame of the block before.
        while (position < frames - 1) {
            val index = Math.floor(position).toInt()
            val fraction = (position - index).toFloat()
            for (c in 0 until targetChannels) {
                val a = if (index < 0) previous!![c] else mixed[index * targetChannels + c]
                val b = mixed[(index + 1) * targetChannels + c]
                put(a + (b - a) * fraction)
            }
            position += step
        }
        last = FloatArray(targetChannels) { mixed[(frames - 1) * targetChannels + it] }
        position -= frames
        return out.toByteArray()
    }
}
