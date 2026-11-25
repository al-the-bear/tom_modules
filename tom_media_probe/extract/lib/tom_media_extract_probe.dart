import 'package:flutter/services.dart';

/// Audio and still frames out of a video, over the platform's own demuxers
/// and decoders.
///
/// A source is a file path; on the web a URL (an asset's or a blob's).
abstract class MediaExtract {
  /// The implementation of this platform; the web sets its own.
  static MediaExtract instance = _ChannelMediaExtract();

  /// What the platform says about the source: `durationMs`, `hasVideo`,
  /// `hasAudio`, `width`, `height`, `videoCodec`, `audioCodec`,
  /// `sampleRate`, `channels`, as far as it knows them.
  Future<Map<String, Object?>> info(String source);

  /// Decodes the sound and writes it as a 16-bit PCM WAV file at
  /// [sampleRate] and [channels]. Answers `frames` (sample frames written)
  /// and, on the web, `bytes` (the file's content: the web has no path).
  Future<Map<String, Object?>> audioToWav(
    String source,
    String out, {
    required int sampleRate,
    required int channels,
  });

  /// Decodes a part of the sound into memory: signed 16-bit little-endian
  /// interleaved samples at [sampleRate] and [channels].
  Future<Uint8List> audioPcm(
    String source, {
    required int sampleRate,
    required int channels,
    int startMs = 0,
    int? durationMs,
  });

  /// One frame as a JPEG: `jpeg`, `width`, `height`, and `timeMs` where the
  /// platform reports the time of the frame it returned.
  ///
  /// [exact] asks for the frame shown at [timeMs]; otherwise the platform
  /// may answer the nearest key frame, which is faster. [maxWidth] 0 keeps
  /// the video's size.
  Future<Map<String, Object?>> frame(
    String source, {
    required int timeMs,
    int maxWidth = 0,
    bool exact = true,
  });
}

class _ChannelMediaExtract extends MediaExtract {
  static const MethodChannel _channel = MethodChannel(
    'tom_media_probe/extract',
  );

  Map<String, Object?> _map(Object? value) =>
      (value as Map<Object?, Object?>).cast<String, Object?>();

  @override
  Future<Map<String, Object?>> info(String source) async => _map(
    await _channel.invokeMethod<Object?>('info', <String, Object?>{
      'path': source,
    }),
  );

  @override
  Future<Map<String, Object?>> audioToWav(
    String source,
    String out, {
    required int sampleRate,
    required int channels,
  }) async => _map(
    await _channel.invokeMethod<Object?>('audioToWav', <String, Object?>{
      'path': source,
      'out': out,
      'sampleRate': sampleRate,
      'channels': channels,
    }),
  );

  @override
  Future<Uint8List> audioPcm(
    String source, {
    required int sampleRate,
    required int channels,
    int startMs = 0,
    int? durationMs,
  }) async =>
      (await _channel.invokeMethod<Uint8List>('audioPcm', <String, Object?>{
        'path': source,
        'sampleRate': sampleRate,
        'channels': channels,
        'startMs': startMs,
        'durationMs': durationMs,
      }))!;

  @override
  Future<Map<String, Object?>> frame(
    String source, {
    required int timeMs,
    int maxWidth = 0,
    bool exact = true,
  }) async => _map(
    await _channel.invokeMethod<Object?>('frame', <String, Object?>{
      'path': source,
      'timeMs': timeMs,
      'maxWidth': maxWidth,
      'exact': exact,
    }),
  );
}
