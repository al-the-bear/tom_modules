import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'level_meter.dart';
import 'probe_out.dart';
import 'recording_screen.dart' show encoderExtensions;

/// Seconds each format is recorded for.
const int _seconds = int.fromEnvironment('PROBE_SECONDS', defaultValue: 10);

/// Seconds of the long recording; 0 leaves it out.
const int _longSeconds = int.fromEnvironment('PROBE_LONG_SECONDS');

/// What the long recording records: `audio` or `video`.
const String _longKind = String.fromEnvironment(
  'PROBE_LONG_KIND',
  defaultValue: 'audio',
);

/// Parts to leave out, comma separated: `audio`, `video`, `camera_macos`.
const String _skip = String.fromEnvironment('PROBE_SKIP');

/// Whether the recorded files stay (to look at their codecs).
const bool _keepFiles = bool.fromEnvironment('PROBE_KEEP');

/// Whether the application ends when the run is over.
const bool _exitWhenDone = bool.fromEnvironment('PROBE_EXIT');

/// How long a step may wait for a permission dialog nobody answers.
const Duration _promptWait = Duration(seconds: 45);

bool _skipped(String part) => _skip.split(',').contains(part);

/// The automated recording run: every format the platform offers, measured.
class RecordingAutoRun extends StatefulWidget {
  const RecordingAutoRun({super.key});

  @override
  State<RecordingAutoRun> createState() => _RecordingAutoRunState();
}

class _RecordingAutoRunState extends State<RecordingAutoRun> {
  final List<String> _log = <String>[];
  final Map<String, Object?> _report = <String, Object?>{};
  CameraController? _camera;
  double? _level;
  bool _showMacCamera = false;
  String? _macCameraId;
  Completer<CameraMacOSController>? _macController;

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
    _report['platform'] = platformName;
    _report['platformVersion'] = platformVersion;
    _report['web'] = kIsWeb;
    _report['secondsPerFormat'] = _seconds;
    _report['started'] = DateTime.now().toIso8601String();
    if (!_skipped('audio')) {
      _report['audio'] = await _guard('audio', _audio);
    }
    if (!_skipped('video')) {
      _report['video'] = await _guard('video', _video);
    }
    if (!kIsWeb && platformName == 'macos' && !_skipped('camera_macos')) {
      _report['cameraMacos'] = await _guard('camera_macos', _cameraMacos);
    }
    if (_longSeconds > 0) {
      _report['long'] = await _guard(
        'long',
        _longKind == 'video' ? _longVideo : _longAudio,
      );
    }
    _report['finished'] = DateTime.now().toIso8601String();
    final String json = jsonEncode(_report);
    final String? path = await writeReport(
      'recording_report${_longSeconds > 0 ? '_long' : ''}.json',
      json,
    );
    // In parts: Android's log cuts a line near 1,000 characters.
    const int part = 700;
    for (int at = 0, n = 0; at < json.length; at += part, n++) {
      final int end = at + part < json.length ? at + part : json.length;
      // ignore: avoid_print
      print('PROBE_PART $n ${json.substring(at, end)}');
    }
    // ignore: avoid_print
    print('PROBE_DONE ${path ?? ''}');
    _say('Done. ${path ?? ''}');
    if (_exitWhenDone) {
      quit(0);
    }
  }

  Future<Object?> _guard(
    String name,
    Future<Map<String, Object?>> Function() step,
  ) async {
    try {
      return await step();
    } on Object catch (error) {
      _say('$name failed: $error');
      return <String, Object?>{'error': '$error'};
    }
  }

  // ---------------------------------------------------------------- audio

  Future<Map<String, Object?>> _audio() async {
    final Map<String, Object?> out = <String, Object?>{};
    final AudioRecorder recorder = AudioRecorder();
    try {
      final Stopwatch clock = Stopwatch()..start();
      bool? before;
      try {
        before = await recorder.hasPermission(request: false);
      } on Object catch (error) {
        out['permissionCheckError'] = '$error';
      }
      out['permissionBeforeAsking'] = before;
      clock.reset();
      bool granted;
      try {
        granted = await recorder.hasPermission().timeout(_promptWait);
      } on TimeoutException {
        out['permission'] = 'the dialog was not answered';
        _say('audio: the permission dialog was not answered');
        return out;
      }
      out['permission'] = granted;
      out['permissionMs'] = clock.elapsedMilliseconds;
      _say('audio: permission $granted (${clock.elapsedMilliseconds} ms)');
      if (!granted) {
        return out;
      }

      List<InputDevice> devices = <InputDevice>[];
      try {
        devices = await recorder.listInputDevices();
      } on Object catch (error) {
        out['devicesError'] = '$error';
      }
      out['devices'] = <String>[
        for (final InputDevice device in devices) device.label,
      ];
      _say('audio: ${devices.length} input device(s)');

      final List<AudioEncoder> encoders = <AudioEncoder>[];
      for (final AudioEncoder encoder in AudioEncoder.values) {
        try {
          if (await recorder.isEncoderSupported(encoder)) {
            encoders.add(encoder);
          }
        } on Object catch (error) {
          out['encoderCheckError_${encoder.name}'] = '$error';
        }
      }
      out['encoders'] = <String>[
        for (final AudioEncoder encoder in encoders) encoder.name,
      ];
      _say('audio: formats ${out['encoders']}');

      final List<Map<String, Object?>> runs = <Map<String, Object?>>[];
      for (final AudioEncoder encoder in encoders) {
        if (encoder == AudioEncoder.pcm16bits) {
          continue;
        }
        runs.add(await _recordAudio(recorder, encoder, _seconds, null));
      }
      out['runs'] = runs;

      out['pcmStream'] = await _pcmStream(recorder);

      if (devices.length > 1) {
        final AudioEncoder encoder = encoders.contains(AudioEncoder.wav)
            ? AudioEncoder.wav
            : encoders.first;
        out['secondDevice'] = await _recordAudio(
          recorder,
          encoder,
          3,
          devices[1],
        );
      }
    } finally {
      await recorder.dispose();
    }
    return out;
  }

  Future<Map<String, Object?>> _recordAudio(
    AudioRecorder recorder,
    AudioEncoder encoder,
    int seconds,
    InputDevice? device, {
    bool keep = false,
  }) async {
    final Map<String, Object?> run = <String, Object?>{
      'encoder': encoder.name,
      'seconds': seconds,
      if (device != null) 'device': device.label,
    };
    StreamSubscription<Amplitude>? levels;
    try {
      final String folder = await probeFolder();
      final String name = 'auto_${encoder.name}.${encoderExtensions[encoder]}';
      final Stopwatch clock = Stopwatch()..start();
      await recorder.start(
        RecordConfig(encoder: encoder, device: device),
        path: folder.isEmpty ? name : '$folder/$name',
      );
      run['startMs'] = clock.elapsedMilliseconds;
      int events = 0;
      double loudest = -160;
      levels = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((Amplitude amplitude) {
            events++;
            if (amplitude.current > loudest) {
              loudest = amplitude.current;
            }
            if (mounted) {
              setState(() => _level = amplitude.current);
            }
          });
      final int rssBefore = residentBytes ?? 0;
      await Future<void>.delayed(Duration(seconds: seconds));
      run['rssGrowthBytes'] = (residentBytes ?? 0) - rssBefore;
      await levels.cancel();
      levels = null;
      clock.reset();
      final String? path = await recorder.stop();
      run['stopMs'] = clock.elapsedMilliseconds;
      run['levelEvents'] = events;
      run['loudestDbfs'] = loudest.isFinite ? loudest : null;
      if (path != null) {
        final int bytes = await XFile(path).length();
        run['bytes'] = bytes;
        run['bytesPerMinute'] = (bytes * 60 / seconds).round();
        run['file'] = path.split(RegExp(r'[/\\]')).last;
        if (!keep && !_keepFiles) {
          await deleteFile(path);
        }
      } else {
        run['error'] = 'stop returned no file';
      }
      _say(
        'audio ${encoder.name}: start ${run['startMs']} ms, '
        'stop ${run['stopMs']} ms, ${run['bytes']} bytes',
      );
    } on Object catch (error) {
      await levels?.cancel();
      run['error'] = '$error';
      _say('audio ${encoder.name} failed: $error');
      try {
        await recorder.cancel();
      } on Object catch (_) {}
    }
    if (mounted) {
      setState(() => _level = null);
    }
    return run;
  }

  Future<Map<String, Object?>> _pcmStream(AudioRecorder recorder) async {
    final Map<String, Object?> run = <String, Object?>{};
    try {
      final Stopwatch clock = Stopwatch()..start();
      final Stream<Uint8List> stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      int bytes = 0;
      int chunks = 0;
      int? firstMs;
      final StreamSubscription<Uint8List> sub = stream.listen((
        Uint8List chunk,
      ) {
        firstMs ??= clock.elapsedMilliseconds;
        bytes += chunk.length;
        chunks++;
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      await recorder.stop();
      await sub.cancel();
      run['firstChunkMs'] = firstMs;
      run['chunks'] = chunks;
      run['bytes'] = bytes;
      run['expectedBytes'] = 16000 * 2 * 3;
      _say(
        'audio stream: $chunks chunks, $bytes bytes, first after $firstMs ms',
      );
    } on Object catch (error) {
      run['error'] = '$error';
      _say('audio stream failed: $error');
    }
    return run;
  }

  Future<Map<String, Object?>> _longAudio() async {
    final AudioRecorder recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission().timeout(_promptWait)) {
        return <String, Object?>{'error': 'no permission'};
      }
      _say('long audio: $_longSeconds s');
      return await _recordAudio(
        recorder,
        AudioEncoder.aacLc,
        _longSeconds,
        null,
        keep: true,
      );
    } finally {
      await recorder.dispose();
    }
  }

  // ---------------------------------------------------------------- video

  Future<Map<String, Object?>> _video() async {
    final Map<String, Object?> out = <String, Object?>{};
    final Stopwatch clock = Stopwatch()..start();
    final List<CameraDescription> cameras = await availableCameras().timeout(
      _promptWait,
    );
    out['listMs'] = clock.elapsedMilliseconds;
    out['cameras'] = <String>[
      for (final CameraDescription camera in cameras)
        '${camera.name} (${camera.lensDirection.name})',
    ];
    _say('video: ${cameras.length} camera(s)');
    final List<Map<String, Object?>> runs = <Map<String, Object?>>[];
    for (final CameraDescription camera in cameras.take(2)) {
      runs.add(await _recordVideo(camera, _seconds));
    }
    out['runs'] = runs;
    return out;
  }

  Future<Map<String, Object?>> _recordVideo(
    CameraDescription camera,
    int seconds, {
    bool keep = false,
  }) async {
    final Map<String, Object?> run = <String, Object?>{
      'camera': camera.name,
      'seconds': seconds,
    };
    final CameraController controller = CameraController(
      camera,
      ResolutionPreset.high,
    );
    try {
      final Stopwatch clock = Stopwatch()..start();
      await controller.initialize().timeout(_promptWait);
      run['initMs'] = clock.elapsedMilliseconds;
      final Size? preview = controller.value.previewSize;
      run['previewSize'] = preview == null
          ? null
          : '${preview.width.round()}x${preview.height.round()}';
      if (mounted) {
        setState(() => _camera = controller);
      }
      // The preview is on screen for a moment before the recording starts.
      await Future<void>.delayed(const Duration(seconds: 1));
      clock.reset();
      await controller.startVideoRecording();
      run['startMs'] = clock.elapsedMilliseconds;
      final int rssBefore = residentBytes ?? 0;
      await Future<void>.delayed(Duration(seconds: seconds));
      run['rssGrowthBytes'] = (residentBytes ?? 0) - rssBefore;
      clock.reset();
      final XFile file = await controller.stopVideoRecording();
      run['stopMs'] = clock.elapsedMilliseconds;
      final int bytes = await file.length();
      run['bytes'] = bytes;
      run['bytesPerMinute'] = (bytes * 60 / seconds).round();
      run['file'] = file.name;
      run['path'] = _keepFiles ? file.path : null;
      run['mimeType'] = file.mimeType;
      if (!keep && !_keepFiles && !kIsWeb) {
        await deleteFile(file.path);
      }
      _say(
        'video ${camera.name}: init ${run['initMs']} ms, start '
        '${run['startMs']} ms, stop ${run['stopMs']} ms, $bytes bytes '
        '(${file.name})',
      );
    } on TimeoutException {
      run['error'] = 'the permission dialog was not answered';
      _say('video ${camera.name}: the permission dialog was not answered');
    } on CameraException catch (error) {
      run['error'] = '${error.code}: ${error.description}';
      _say('video ${camera.name} failed: ${error.code} ${error.description}');
    } on Object catch (error) {
      run['error'] = '$error';
      _say('video ${camera.name} failed: $error');
    } finally {
      if (mounted) {
        setState(() => _camera = null);
      }
      try {
        await controller.dispose();
      } on Object catch (_) {}
    }
    return run;
  }

  Future<Map<String, Object?>> _longVideo() async {
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      return <String, Object?>{'error': 'no camera'};
    }
    _say('long video: $_longSeconds s');
    return _recordVideo(cameras.first, _longSeconds, keep: true);
  }

  // --------------------------------------------------------- camera_macos

  Future<Map<String, Object?>> _cameraMacos() async {
    final Map<String, Object?> out = <String, Object?>{};
    final Stopwatch clock = Stopwatch()..start();
    final List<CameraMacOSDevice> devices = await CameraMacOS.instance
        .listDevices(deviceType: CameraMacOSDeviceType.video)
        .timeout(_promptWait);
    out['listMs'] = clock.elapsedMilliseconds;
    out['cameras'] = <String>[
      for (final CameraMacOSDevice device in devices)
        device.localizedName ?? device.deviceId,
    ];
    if (devices.isEmpty) {
      return out;
    }
    final Completer<CameraMacOSController> ready =
        Completer<CameraMacOSController>();
    clock.reset();
    setState(() {
      _macController = ready;
      _macCameraId = devices.first.deviceId;
      _showMacCamera = true;
    });
    try {
      final CameraMacOSController controller = await ready.future.timeout(
        _promptWait,
      );
      out['initMs'] = clock.elapsedMilliseconds;
      await Future<void>.delayed(const Duration(seconds: 1));
      final String folder = await probeFolder();
      clock.reset();
      await controller.recordVideo(url: '$folder/auto_camera_macos.mp4');
      out['startMs'] = clock.elapsedMilliseconds;
      await Future<void>.delayed(const Duration(seconds: _seconds));
      clock.reset();
      final CameraMacOSFile? file = await controller.stopRecording();
      out['stopMs'] = clock.elapsedMilliseconds;
      final String? url = file?.url;
      out['file'] = url?.split('/').last;
      if (url != null) {
        final int bytes = await XFile(url).length();
        out['bytes'] = bytes;
        out['bytesPerMinute'] = (bytes * 60 / _seconds).round();
        if (!_keepFiles) {
          await deleteFile(url);
        }
      }
      await controller.destroy();
      _say(
        'camera_macos: init ${out['initMs']} ms, start ${out['startMs']} ms, '
        'stop ${out['stopMs']} ms, ${out['bytes']} bytes',
      );
    } on TimeoutException {
      out['error'] = 'the camera did not come up (permission dialog?)';
    } finally {
      if (mounted) {
        setState(() => _showMacCamera = false);
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ ui

  @override
  Widget build(BuildContext context) {
    final CameraController? camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Recording: automated run')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: LevelMeter(dbfs: _level),
          ),
          SizedBox(
            height: 200,
            child: camera != null
                ? Center(child: CameraPreview(camera))
                : _showMacCamera
                ? CameraMacOSView(
                    deviceId: _macCameraId,
                    cameraMode: CameraMacOSMode.video,
                    onCameraInizialized: (CameraMacOSController controller) {
                      final Completer<CameraMacOSController>? ready =
                          _macController;
                      if (ready != null && !ready.isCompleted) {
                        ready.complete(controller);
                      }
                    },
                  )
                : const Center(child: Text('No preview')),
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
