# tom_media_extract_probe

The extraction half of [tom_media_probe](../README.md): audio and still
frames out of a video file, over what each platform brings.

| Platform | Demuxing and decoding | Image |
| --- | --- | --- |
| macOS, iOS | `AVAssetReader`, `AVAssetImageGenerator` (`darwin/`, one Swift file for both) | ImageIO JPEG |
| Android | `MediaExtractor` with `MediaCodec`, `MediaMetadataRetriever` | `Bitmap.compress` JPEG |
| Windows | Media Foundation Source Reader | Windows Imaging Component JPEG |
| Linux | the system's GStreamer (`uridecodebin`, `appsink`) | `jpegenc` |
| Web | Web Audio `decodeAudioData`, a `<video>` element drawn to a canvas | `canvas.toBlob` JPEG |

One method channel, `tom_media_probe/extract`, with four calls
(`lib/tom_media_extract_probe.dart`): `info`, `audioToWav`, `audioPcm`,
`frame`. A probe, not a product: `publish_to: none`, BSD-3, skipped by
buildkit.
