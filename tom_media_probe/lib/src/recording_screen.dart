import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'level_meter.dart';
import 'probe_out.dart';

/// Recording by hand: audio with a level meter, video with a preview.
class RecordingScreen extends StatelessWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recording'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.mic), text: 'Audio'),
              Tab(icon: Icon(Icons.videocam), text: 'Video'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[AudioRecordingPane(), VideoRecordingPane()],
        ),
      ),
    );
  }
}

const Map<AudioEncoder, String> encoderExtensions = <AudioEncoder, String>{
  AudioEncoder.aacLc: 'm4a',
  AudioEncoder.aacEld: 'm4a',
  AudioEncoder.aacHe: 'm4a',
  AudioEncoder.amrNb: '3gp',
  AudioEncoder.amrWb: '3gp',
  AudioEncoder.opus: 'opus',
  AudioEncoder.flac: 'flac',
  AudioEncoder.wav: 'wav',
  AudioEncoder.pcm16bits: 'pcm',
};

class AudioRecordingPane extends StatefulWidget {
  const AudioRecordingPane({super.key});

  @override
  State<AudioRecordingPane> createState() => _AudioRecordingPaneState();
}

class _AudioRecordingPaneState extends State<AudioRecordingPane> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _levels;
  StreamSubscription<RecordState>? _states;
  List<InputDevice> _devices = <InputDevice>[];
  List<AudioEncoder> _encoders = <AudioEncoder>[];
  InputDevice? _device;
  AudioEncoder _encoder = AudioEncoder.aacLc;
  RecordState _state = RecordState.stop;
  double? _level;
  String _message = '';
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _states = _recorder.onStateChanged().listen((RecordState state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final bool granted = await _recorder.hasPermission();
      if (!granted) {
        _say('The microphone permission was refused.');
        return;
      }
      final List<InputDevice> devices = await _recorder.listInputDevices();
      final List<AudioEncoder> encoders = <AudioEncoder>[];
      for (final AudioEncoder encoder in AudioEncoder.values) {
        if (await _recorder.isEncoderSupported(encoder)) {
          encoders.add(encoder);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _encoders = encoders;
        if (encoders.isNotEmpty && !encoders.contains(_encoder)) {
          _encoder = encoders.first;
        }
      });
    } on Object catch (error) {
      _say('Could not read the microphones: $error');
    }
  }

  void _say(String message) {
    if (mounted) {
      setState(() => _message = message);
    }
  }

  Future<void> _start() async {
    try {
      final String folder = await probeFolder();
      final String name =
          'audio_${DateTime.now().millisecondsSinceEpoch}.${encoderExtensions[_encoder]}';
      await _recorder.start(
        RecordConfig(encoder: _encoder, device: _device),
        path: folder.isEmpty ? name : '$folder/$name',
      );
      _levels = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((Amplitude amplitude) {
            if (mounted) {
              setState(() => _level = amplitude.current);
            }
          });
      _clock
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      _say('Recording.');
    } on Object catch (error) {
      _say('Could not start: $error');
    }
  }

  Future<void> _stop() async {
    try {
      final String? path = await _recorder.stop();
      await _levels?.cancel();
      _tick?.cancel();
      _clock.stop();
      int? size;
      if (path != null) {
        size = await XFile(path).length();
      }
      if (mounted) {
        setState(() => _level = null);
      }
      _say('Saved ${size ?? '?'} bytes: $path');
    } on Object catch (error) {
      _say('Could not stop: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_levels?.cancel());
    unawaited(_states?.cancel());
    _tick?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool recording = _state != RecordState.stop;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        DropdownButton<InputDevice?>(
          isExpanded: true,
          value: _device,
          hint: const Text('Default microphone'),
          items: <DropdownMenuItem<InputDevice?>>[
            const DropdownMenuItem<InputDevice?>(
              child: Text('Default microphone'),
            ),
            for (final InputDevice device in _devices)
              DropdownMenuItem<InputDevice?>(
                value: device,
                child: Text(device.label),
              ),
          ],
          onChanged: recording
              ? null
              : (InputDevice? device) => setState(() => _device = device),
        ),
        DropdownButton<AudioEncoder>(
          isExpanded: true,
          value: _encoders.contains(_encoder) ? _encoder : null,
          hint: const Text('Format'),
          items: <DropdownMenuItem<AudioEncoder>>[
            for (final AudioEncoder encoder in _encoders)
              DropdownMenuItem<AudioEncoder>(
                value: encoder,
                child: Text(encoder.name),
              ),
          ],
          onChanged: recording
              ? null
              : (AudioEncoder? encoder) =>
                    setState(() => _encoder = encoder ?? _encoder),
        ),
        const SizedBox(height: 12),
        LevelMeter(dbfs: _level),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            FilledButton.icon(
              onPressed: recording ? null : _start,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Record'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: recording ? _stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
            const SizedBox(width: 16),
            Text('${_state.name}  ${_clock.elapsed.inSeconds} s'),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(_message),
      ],
    );
  }
}

class VideoRecordingPane extends StatefulWidget {
  const VideoRecordingPane({super.key});

  @override
  State<VideoRecordingPane> createState() => _VideoRecordingPaneState();
}

class _VideoRecordingPaneState extends State<VideoRecordingPane> {
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraDescription? _camera;
  CameraController? _controller;
  String _message = '';
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (!mounted) {
        return;
      }
      setState(() => _cameras = cameras);
      if (cameras.isEmpty) {
        _say('No camera found.');
      } else {
        await _open(cameras.first);
      }
    } on Object catch (error) {
      _say('Could not read the cameras: $error');
    }
  }

  Future<void> _open(CameraDescription camera) async {
    final CameraController? old = _controller;
    setState(() {
      _controller = null;
      _camera = camera;
    });
    await old?.dispose();
    final CameraController controller = CameraController(
      camera,
      ResolutionPreset.high,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _say('Camera ready: ${controller.value.previewSize}');
    } on CameraException catch (error) {
      await controller.dispose();
      _say('Camera refused (${error.code}): ${error.description}');
    }
  }

  void _say(String message) {
    if (mounted) {
      setState(() => _message = message);
    }
  }

  Future<void> _start() async {
    try {
      await _controller!.startVideoRecording();
      _clock
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      _say('Recording.');
    } on Object catch (error) {
      _say('Could not start: $error');
    }
  }

  Future<void> _stop() async {
    try {
      final XFile file = await _controller!.stopVideoRecording();
      _tick?.cancel();
      _clock.stop();
      _say('Saved ${await file.length()} bytes: ${file.path}');
    } on Object catch (error) {
      _say('Could not stop: $error');
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;
    final bool recording = controller?.value.isRecordingVideo ?? false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        DropdownButton<CameraDescription>(
          isExpanded: true,
          value: _camera,
          hint: const Text('Camera'),
          items: <DropdownMenuItem<CameraDescription>>[
            for (final CameraDescription camera in _cameras)
              DropdownMenuItem<CameraDescription>(
                value: camera,
                child: Text('${camera.name} (${camera.lensDirection.name})'),
              ),
          ],
          onChanged: recording
              ? null
              : (CameraDescription? camera) {
                  if (camera != null) {
                    unawaited(_open(camera));
                  }
                },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: controller == null
              ? const Center(child: Text('No preview'))
              : Center(child: CameraPreview(controller)),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            FilledButton.icon(
              onPressed: controller == null || recording ? null : _start,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Record'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: recording ? _stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
            const SizedBox(width: 16),
            Text('${_clock.elapsed.inSeconds} s'),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(_message),
      ],
    );
  }
}
