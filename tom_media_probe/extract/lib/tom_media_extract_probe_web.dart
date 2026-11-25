import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'tom_media_extract_probe.dart';

/// The browser's extraction: Web Audio decodes the sound (the whole track,
/// in memory), a `<video>` element seeks and is drawn to a canvas.
class TomMediaExtractProbeWeb extends MediaExtract {
  static void registerWith(Registrar registrar) {
    MediaExtract.instance = TomMediaExtractProbeWeb();
  }

  /// One element per source, so a strip of frames opens the video once.
  final Map<String, web.HTMLVideoElement> _videos =
      <String, web.HTMLVideoElement>{};

  Future<web.HTMLVideoElement> _video(String source) async {
    final web.HTMLVideoElement? known = _videos[source];
    if (known != null) {
      return known;
    }
    final web.HTMLVideoElement video = web.HTMLVideoElement()
      ..crossOrigin = 'anonymous'
      ..muted = true
      ..preload = 'auto';
    final Completer<void> ready = Completer<void>();
    void done(web.Event _) {
      if (!ready.isCompleted) {
        ready.complete();
      }
    }

    void failed(web.Event _) {
      if (!ready.isCompleted) {
        final web.MediaError? error = video.error;
        ready.completeError(
          StateError(
            'the browser cannot play this video '
            '(${error?.code}: ${error?.message})',
          ),
        );
      }
    }

    video.addEventListener('loadeddata', done.toJS);
    video.addEventListener('error', failed.toJS);
    video.src = source;
    video.load();
    await ready.future.timeout(const Duration(seconds: 30));
    _videos[source] = video;
    return video;
  }

  @override
  Future<Map<String, Object?>> info(String source) async {
    final web.HTMLVideoElement video = await _video(source);
    final double seconds = video.duration.toDouble();
    return <String, Object?>{
      'durationMs': seconds.isFinite ? (seconds * 1000).round() : null,
      'hasVideo': video.videoWidth > 0,
      'width': video.videoWidth,
      'height': video.videoHeight,
    };
  }

  /// Decodes the whole sound track at [sampleRate] and mixes it to
  /// [channels], as interleaved 16-bit samples.
  Future<Int16List> _decode(String source, int sampleRate, int channels) async {
    final web.Response response = await web.window.fetch(source.toJS).toDart;
    final JSArrayBuffer encoded = await response.arrayBuffer().toDart;
    final web.AudioContext context = web.AudioContext(
      web.AudioContextOptions(sampleRate: sampleRate.toDouble()),
    );
    try {
      final web.AudioBuffer buffer = await context
          .decodeAudioData(encoded)
          .toDart;
      final int frames = buffer.length;
      final List<Float32List> source = <Float32List>[
        for (int c = 0; c < buffer.numberOfChannels; c++)
          buffer.getChannelData(c).toDart,
      ];
      final Int16List out = Int16List(frames * channels);
      for (int f = 0; f < frames; f++) {
        for (int c = 0; c < channels; c++) {
          double value;
          if (channels == 1) {
            value = 0;
            for (final Float32List channel in source) {
              value += channel[f];
            }
            value /= source.length;
          } else {
            value = source[c % source.length][f];
          }
          out[f * channels + c] = (value * 32767).round().clamp(-32768, 32767);
        }
      }
      return out;
    } finally {
      await context.close().toDart;
    }
  }

  @override
  Future<Map<String, Object?>> audioToWav(
    String source,
    String out, {
    required int sampleRate,
    required int channels,
  }) async {
    final Int16List samples = await _decode(source, sampleRate, channels);
    final int dataBytes = samples.lengthInBytes;
    final ByteData header = ByteData(44);
    void text(int at, String value) {
      for (int i = 0; i < value.length; i++) {
        header.setUint8(at + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    header.setUint32(4, 36 + dataBytes, Endian.little);
    text(8, 'WAVEfmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    text(36, 'data');
    header.setUint32(40, dataBytes, Endian.little);
    final BytesBuilder file = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(samples.buffer.asUint8List());
    return <String, Object?>{
      'frames': samples.length ~/ channels,
      'sampleRate': sampleRate,
      'channels': channels,
      'bytes': file.takeBytes(),
    };
  }

  @override
  Future<Uint8List> audioPcm(
    String source, {
    required int sampleRate,
    required int channels,
    int startMs = 0,
    int? durationMs,
  }) async {
    final Int16List samples = await _decode(source, sampleRate, channels);
    final int total = samples.length ~/ channels;
    final int first = (startMs * sampleRate ~/ 1000).clamp(0, total);
    final int last = durationMs == null
        ? total
        : ((startMs + durationMs) * sampleRate ~/ 1000).clamp(first, total);
    return Uint8List.fromList(
      samples.buffer.asUint8List(
        first * channels * 2,
        (last - first) * channels * 2,
      ),
    );
  }

  @override
  Future<Map<String, Object?>> frame(
    String source, {
    required int timeMs,
    int maxWidth = 0,
    bool exact = true,
  }) async {
    final web.HTMLVideoElement video = await _video(source);
    final Completer<void> sought = Completer<void>();
    void done(web.Event _) {
      if (!sought.isCompleted) {
        sought.complete();
      }
    }

    // A browser seeks to the frame shown at the time; it offers no
    // key-frame seek that every engine has, so [exact] changes nothing.
    double? presentedSeconds;
    if ((video.currentTime - timeMs / 1000).abs() > 0.0005) {
      // `seeked` says the position is reached, not that its frame is on the
      // element: drawn right then, the canvas gets the frame before. The
      // frame callback fires once the new frame is presented.
      final Completer<void> presented = Completer<void>();
      void shown(JSNumber now, JSObject metadata) {
        presentedSeconds = metadata
            .getProperty<JSNumber>('mediaTime'.toJS)
            .toDartDouble;
        if (!presented.isCompleted) {
          presented.complete();
        }
      }

      video.requestVideoFrameCallback(shown.toJS);
      final JSFunction listener = done.toJS;
      video.addEventListener('seeked', listener);
      video.currentTime = timeMs / 1000;
      try {
        await sought.future.timeout(const Duration(seconds: 30));
        // No callback comes when the frame is the one already shown.
        await presented.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      } finally {
        video.removeEventListener('seeked', listener);
      }
    }
    int width = video.videoWidth;
    int height = video.videoHeight;
    if (maxWidth > 0 && maxWidth < width) {
      height = (height * maxWidth / width).round();
      width = maxWidth;
    }
    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final web.CanvasRenderingContext2D context =
        canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.drawImage(video, 0, 0, width, height);
    final Completer<web.Blob?> encoded = Completer<web.Blob?>();
    void taken(web.Blob? blob) => encoded.complete(blob);
    canvas.toBlob(taken.toJS, 'image/jpeg', 0.8.toJS);
    final web.Blob? blob = await encoded.future;
    if (blob == null) {
      throw StateError('the browser returned no JPEG');
    }
    final JSArrayBuffer bytes = await blob.arrayBuffer().toDart;
    return <String, Object?>{
      'jpeg': bytes.toDart.asUint8List(),
      'timeMs': ((presentedSeconds ?? video.currentTime) * 1000).round(),
      'width': width,
      'height': height,
    };
  }
}
