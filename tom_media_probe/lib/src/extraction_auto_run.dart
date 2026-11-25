import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tom_media_extract_probe/tom_media_extract_probe.dart';

import 'extraction.dart';
import 'probe_out.dart';
import 'report.dart';

/// A long video to measure besides the fixtures: a path on this machine
/// (`tool/make_fixtures.sh long <out>` writes one of an hour).
const String _longFile = String.fromEnvironment('PROBE_LONG_FILE');

/// Parts to leave out, comma separated: `recorded`, or a fixture's name.
const String _skip = String.fromEnvironment('PROBE_SKIP');

/// Whether every frame got back is kept as a JPEG in the probe's folder
/// (`frame_<video>_<exact|key>_<ms>.jpg`), for `tool/frame_numbers.py`.
const bool _keepFrames = bool.fromEnvironment('PROBE_KEEP');

/// Whether the application ends when the run is over.
const bool _exitWhenDone = bool.fromEnvironment('PROBE_EXIT');

bool _skipped(String part) => _skip.split(',').contains(part);

/// The automated extraction run: every fixture, a video recorded just now,
/// and a long video if one is named, measured.
class ExtractionAutoRun extends StatefulWidget {
  const ExtractionAutoRun({super.key});

  @override
  State<ExtractionAutoRun> createState() => _ExtractionAutoRunState();
}

class _ExtractionAutoRunState extends State<ExtractionAutoRun> {
  final List<String> _log = <String>[];
  final List<Uint8List> _strip = <Uint8List>[];
  CameraController? _camera;
  final MediaExtract _extract = MediaExtract.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _say(String line) {
    debugPrint('PROBE_LOG $line');
    if (mounted) {
      setState(() => _log.add(line));
    }
  }

  Future<void> _run() async {
    final Map<String, Object?> report = <String, Object?>{
      'platform': platformName,
      'platformVersion': platformVersion,
      'web': kIsWeb,
      'started': DateTime.now().toIso8601String(),
    };
    final List<Map<String, Object?>> videos = <Map<String, Object?>>[];
    for (final String name in fixtures) {
      if (_skipped(name)) {
        continue;
      }
      try {
        final String source = await assetSource('assets/fixtures/$name');
        videos.add(await _measure(name, source, numbered: true));
      } on Object catch (error) {
        videos.add(<String, Object?>{'name': name, 'error': '$error'});
        _say('$name failed: $error');
      }
    }
    if (!_skipped('recorded')) {
      videos.add(await _recorded());
    }
    if (_longFile.isNotEmpty) {
      videos.add(await _measure('long', _longFile, numbered: true, long: true));
    }
    report['videos'] = videos;
    report['finished'] = DateTime.now().toIso8601String();
    final String? path = await emitReport('extraction_report.json', report);
    _say('Done. ${path ?? ''}');
    if (_exitWhenDone) {
      quit(0);
    }
  }

  /// Records four seconds with the first camera and measures the result.
  Future<Map<String, Object?>> _recorded() async {
    final Map<String, Object?> out = <String, Object?>{'name': 'recorded'};
    CameraController? controller;
    try {
      final List<CameraDescription> cameras = await availableCameras().timeout(
        const Duration(seconds: 45),
      );
      if (cameras.isEmpty) {
        out['error'] = 'no camera to record with';
        _say('recorded: no camera');
        return out;
      }
      controller = CameraController(cameras.first, ResolutionPreset.medium);
      await controller.initialize().timeout(const Duration(seconds: 45));
      if (mounted) {
        setState(() => _camera = controller);
      }
      await controller.startVideoRecording();
      await Future<void>.delayed(const Duration(seconds: 4));
      final XFile file = await controller.stopVideoRecording();
      out['file'] = file.name;
      out['mimeType'] = file.mimeType;
      out['bytes'] = await file.length();
      if (mounted) {
        setState(() => _camera = null);
      }
      await controller.dispose();
      controller = null;
      out.addAll(await _measure('recorded', file.path, numbered: false));
    } on Object catch (error) {
      out['error'] = '$error';
      _say('recorded failed: $error');
    } finally {
      if (mounted) {
        setState(() => _camera = null);
      }
      try {
        await controller?.dispose();
      } on Object catch (_) {}
    }
    return out;
  }

  Future<T> _timed<T>(
    Map<String, Object?> into,
    String key,
    Future<T> Function() work,
  ) async {
    final Stopwatch clock = Stopwatch()..start();
    try {
      return await work();
    } finally {
      into['${key}Ms'] = clock.elapsedMilliseconds;
    }
  }

  Future<Map<String, Object?>> _measure(
    String name,
    String source, {
    required bool numbered,
    bool long = false,
  }) async {
    final Map<String, Object?> out = <String, Object?>{'name': name};
    final Map<String, Object?> info;
    try {
      info = await _timed(out, 'info', () => _extract.info(source));
    } on Object catch (error) {
      out['error'] = 'info: $error';
      _say('$name: cannot be opened: $error');
      return out;
    }
    out['info'] = info;
    final int? durationMs = (info['durationMs'] as num?)?.toInt();
    _say('$name: $info');

    out['audio'] = await _audio(name, source, durationMs, long: long);
    if (info['hasVideo'] != false) {
      out['frames'] = await _frames(
        name,
        source,
        durationMs ?? 4000,
        numbered: numbered,
        long: long,
      );
    }
    return out;
  }

  Future<Map<String, Object?>> _audio(
    String name,
    String source,
    int? durationMs, {
    required bool long,
  }) async {
    final Map<String, Object?> out = <String, Object?>{};
    final String folder = await probeFolder();
    final String wav = folder.isEmpty ? '' : '$folder/extract_$name.wav';
    try {
      final Map<String, Object?> written = await _timed(
        out,
        'wav16kMono',
        () => _extract.audioToWav(source, wav, sampleRate: 16000, channels: 1),
      );
      final int frames = (written['frames']! as num).toInt();
      out['wav16kMonoFrames'] = frames;
      out['wav16kMonoSeconds'] = frames / 16000;
      out['wav16kMonoBytes'] =
          (written['bytes'] as Uint8List?)?.length ?? await fileLength(wav);
      if (durationMs != null && durationMs > 0) {
        out['wav16kMonoMsPerMinute'] =
            ((out['wav16kMonoMs']! as int) * 60000 / durationMs).round();
      }
      _say(
        '$name audio: 16 kHz mono WAV in ${out['wav16kMonoMs']} ms, '
        '${(frames / 16000).toStringAsFixed(2)} s of sound',
      );
    } on Object catch (error) {
      out['wav16kMonoError'] = '$error';
      _say('$name audio failed: $error');
      return out;
    }
    if (!long) {
      try {
        final Map<String, Object?> written = await _timed(
          out,
          'wav44kStereo',
          () =>
              _extract.audioToWav(source, wav, sampleRate: 44100, channels: 2),
        );
        out['wav44kStereoFrames'] = (written['frames']! as num).toInt();
      } on Object catch (error) {
        out['wav44kStereoError'] = '$error';
      }
    }
    if (wav.isNotEmpty) {
      await deleteFile(wav);
    }
    try {
      final int start = long ? 1800000 : 2000;
      final Uint8List pcm = await _timed(
        out,
        'pcmRange',
        () => _extract.audioPcm(
          source,
          sampleRate: 16000,
          channels: 1,
          startMs: start,
          durationMs: 3000,
        ),
      );
      final ({double rmsDbfs, double frequency}) tone = describeTone(
        pcm,
        16000,
      );
      out['pcmRangeBytes'] = pcm.length;
      out['pcmRangeExpectedBytes'] = 96000;
      out['pcmRangeRmsDbfs'] = double.parse(tone.rmsDbfs.toStringAsFixed(1));
      out['pcmRangeFrequency'] = tone.frequency.round();
      _say(
        '$name audio: 3 s from $start ms in memory, ${pcm.length} bytes, '
        '${tone.frequency.round()} Hz at ${tone.rmsDbfs.toStringAsFixed(1)} dBFS '
        '(${out['pcmRangeMs']} ms)',
      );
    } on Object catch (error) {
      out['pcmRangeError'] = '$error';
      _say('$name audio in memory failed: $error');
    }
    return out;
  }

  Future<Map<String, Object?>> _frames(
    String name,
    String source,
    int durationMs, {
    required bool numbered,
    required bool long,
  }) async {
    final Map<String, Object?> out = <String, Object?>{};
    // Times between key frames, at a key frame and near the end.
    final List<int> times = long
        ? <int>[0, 1234567, 1800000, 3599000]
        : <int>[
            0,
            1000,
            3367,
            4000,
            7500,
            durationMs - 100,
          ].where((int t) => t >= 0 && t < durationMs).toList();
    for (final bool exact in <bool>[true, false]) {
      final List<Map<String, Object?>> shots = <Map<String, Object?>>[];
      for (final int time in times) {
        final Map<String, Object?> shot = <String, Object?>{'askedMs': time};
        try {
          final Map<String, Object?> frame = await _timed(
            shot,
            'frame',
            () => _extract.frame(source, timeMs: time, exact: exact),
          );
          final Uint8List jpeg = frame['jpeg']! as Uint8List;
          shot['bytes'] = jpeg.length;
          if (_keepFrames) {
            await keepBytes(
              'frame_${name}_${exact ? 'exact' : 'key'}_$time.jpg',
              jpeg,
            );
          }
          shot['width'] = frame['width'];
          shot['height'] = frame['height'];
          shot['reportedMs'] = frame['timeMs'];
          if (numbered) {
            final int? number = await frameNumber(jpeg);
            shot['frame'] = number;
            shot['expectedFrame'] = time * fixtureFps ~/ 1000;
          }
        } on Object catch (error) {
          shot['error'] = '$error';
        }
        shots.add(shot);
      }
      out[exact ? 'exact' : 'keyFrame'] = shots;
      _say(
        '$name frames (${exact ? 'exact' : 'key frame allowed'}): '
        '${shots.map((Map<String, Object?> s) => s['error'] != null ? 'error' : '${s['askedMs']}ms→#${s['frame'] ?? '?'} in ${s['frameMs']}ms').join(', ')}',
      );
      if (shots.every((Map<String, Object?> s) => s['error'] != null)) {
        out['error'] = shots.first['error'];
        return out;
      }
    }

    // Frames at an interval, full size, exact.
    final Stopwatch clock = Stopwatch()..start();
    final int step = long ? 360000 : 1000;
    int count = 0;
    int wrong = 0;
    for (int time = 0; time < durationMs && count < 10; time += step) {
      try {
        final Map<String, Object?> frame = await _extract.frame(
          source,
          timeMs: time,
        );
        count++;
        if (numbered) {
          final int? number = await frameNumber(frame['jpeg']! as Uint8List);
          if (number != time * fixtureFps ~/ 1000) {
            wrong++;
          }
        }
      } on Object catch (error) {
        out['intervalError'] = '$error';
        break;
      }
    }
    out['intervalFrames'] = count;
    out['intervalMs'] = clock.elapsedMilliseconds;
    if (numbered) {
      out['intervalWrongFrames'] = wrong;
    }

    // Thumbnails for a strip: small, the nearest key frame is enough.
    clock
      ..reset()
      ..start();
    final List<Uint8List> strip = <Uint8List>[];
    int stripBytes = 0;
    for (int i = 0; i < 10; i++) {
      try {
        final Map<String, Object?> frame = await _extract.frame(
          source,
          timeMs: durationMs * i ~/ 10,
          maxWidth: 160,
          exact: false,
        );
        final Uint8List jpeg = frame['jpeg']! as Uint8List;
        strip.add(jpeg);
        stripBytes += jpeg.length;
        out['stripSize'] = '${frame['width']}x${frame['height']}';
      } on Object catch (error) {
        out['stripError'] = '$error';
        break;
      }
    }
    out['stripFrames'] = strip.length;
    out['stripMs'] = clock.elapsedMilliseconds;
    out['stripBytes'] = stripBytes;
    if (mounted) {
      setState(() {
        _strip
          ..clear()
          ..addAll(strip);
      });
    }
    _say(
      '$name: $count frames at an interval in ${out['intervalMs']} ms'
      '${numbered ? ' ($wrong wrong)' : ''}, a strip of ${strip.length} '
      'thumbnails (${out['stripSize']}) in ${out['stripMs']} ms',
    );
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Extraction: automated run')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 100,
            child: camera != null
                ? Center(child: CameraPreview(camera))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final Uint8List jpeg in _strip)
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: Image.memory(jpeg, gaplessPlayback: true),
                        ),
                    ],
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[for (final String line in _log) Text(line)],
            ),
          ),
        ],
      ),
    );
  }
}
