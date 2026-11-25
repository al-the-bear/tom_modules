import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tom_media_extract_probe/tom_media_extract_probe.dart';

import 'extraction.dart';
import 'probe_out.dart';
import 'recording_screen.dart' show lastRecordedVideo;

/// Extraction by hand: the sound and still frames out of a fixture, of the
/// video the recording screen saved last, or of a file named by its path.
class ExtractionScreen extends StatefulWidget {
  const ExtractionScreen({super.key});

  @override
  State<ExtractionScreen> createState() => _ExtractionScreenState();
}

class _ExtractionScreenState extends State<ExtractionScreen> {
  static const String _recorded = 'the video recorded last';
  static const String _path = 'a file, by its path';

  final MediaExtract _extract = MediaExtract.instance;
  final TextEditingController _pathField = TextEditingController();
  String _choice = fixtures.first;
  String? _source;
  int _durationMs = 0;
  double _timeMs = 0;
  bool _exact = true;
  bool _busy = false;
  String _message = '';
  Uint8List? _frame;
  List<Uint8List> _strip = <Uint8List>[];

  @override
  void dispose() {
    _pathField.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (mounted) {
      setState(() => _message = message);
    }
  }

  Future<void> _work(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } on Object catch (error) {
      _say('Failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Opens the chosen video and reads what the platform says about it.
  Future<void> _open() => _work(() async {
    final String source;
    if (_choice == _recorded) {
      final String? last = lastRecordedVideo;
      if (last == null) {
        _say(
          'Nothing was recorded yet: record a video on the Recording screen.',
        );
        return;
      }
      source = last;
    } else if (_choice == _path) {
      source = _pathField.text.trim();
      if (source.isEmpty) {
        _say('Enter the path of a video file.');
        return;
      }
    } else {
      source = await assetSource('assets/fixtures/$_choice');
    }
    final Stopwatch clock = Stopwatch()..start();
    final Map<String, Object?> info = await _extract.info(source);
    setState(() {
      _source = source;
      _durationMs = (info['durationMs'] as num?)?.toInt() ?? 0;
      _timeMs = 0;
      _frame = null;
      _strip = <Uint8List>[];
    });
    _say('Opened in ${clock.elapsedMilliseconds} ms: $info');
  });

  Future<void> _audio() => _work(() async {
    final String folder = await probeFolder();
    final String out = folder.isEmpty ? '' : '$folder/extracted.wav';
    final Stopwatch clock = Stopwatch()..start();
    final Map<String, Object?> written = await _extract.audioToWav(
      _source!,
      out,
      sampleRate: 16000,
      channels: 1,
    );
    final int wavMs = clock.elapsedMilliseconds;
    clock.reset();
    final Uint8List pcm = await _extract.audioPcm(
      _source!,
      sampleRate: 16000,
      channels: 1,
      durationMs: 3000,
    );
    final ({double rmsDbfs, double frequency}) tone = describeTone(pcm, 16000);
    _say(
      'Sound as a 16 kHz mono WAV in $wavMs ms: '
      '${((written['frames']! as num) / 16000).toStringAsFixed(2)} s'
      '${out.isEmpty ? '' : ', $out'}.\n'
      'The first 3 s in memory in ${clock.elapsedMilliseconds} ms: '
      '${pcm.length} bytes, ${tone.rmsDbfs.toStringAsFixed(1)} dBFS, about '
      '${tone.frequency.round()} Hz.',
    );
  });

  Future<void> _oneFrame() => _work(() async {
    final Stopwatch clock = Stopwatch()..start();
    final Map<String, Object?> frame = await _extract.frame(
      _source!,
      timeMs: _timeMs.round(),
      exact: _exact,
    );
    final Uint8List jpeg = frame['jpeg']! as Uint8List;
    final int? number = fixtures.contains(_choice)
        ? await frameNumber(jpeg)
        : null;
    setState(() => _frame = jpeg);
    _say(
      'Frame at ${_timeMs.round()} ms in ${clock.elapsedMilliseconds} ms: '
      '${frame['width']}x${frame['height']}, ${jpeg.length} bytes of JPEG'
      '${frame['timeMs'] == null ? '' : ', the platform says ${frame['timeMs']} ms'}'
      '${number == null ? '' : ', it is frame $number (asked for frame ${_timeMs.round() * fixtureFps ~/ 1000})'}.',
    );
  });

  Future<void> _makeStrip() => _work(() async {
    final Stopwatch clock = Stopwatch()..start();
    final List<Uint8List> strip = <Uint8List>[];
    for (int i = 0; i < 8; i++) {
      final Map<String, Object?> frame = await _extract.frame(
        _source!,
        timeMs: _durationMs * i ~/ 8,
        maxWidth: 160,
        exact: false,
      );
      strip.add(frame['jpeg']! as Uint8List);
      if (mounted) {
        setState(() => _strip = List<Uint8List>.of(strip));
      }
    }
    _say('A strip of 8 thumbnails in ${clock.elapsedMilliseconds} ms.');
  });

  @override
  Widget build(BuildContext context) {
    final bool open = _source != null && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Extraction')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          DropdownButton<String>(
            isExpanded: true,
            value: _choice,
            items: <DropdownMenuItem<String>>[
              for (final String name in <String>[
                ...fixtures,
                _recorded,
                if (!kIsWeb) _path,
              ])
                DropdownMenuItem<String>(value: name, child: Text(name)),
            ],
            onChanged: _busy
                ? null
                : (String? value) => setState(() {
                    _choice = value ?? _choice;
                    _source = null;
                  }),
          ),
          if (_choice == _path)
            TextField(
              controller: _pathField,
              decoration: const InputDecoration(labelText: 'Path of a video'),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: _busy ? null : _open,
                child: const Text('Open'),
              ),
              OutlinedButton(
                onPressed: open ? _audio : null,
                child: const Text('Extract the sound'),
              ),
              OutlinedButton(
                onPressed: open ? _oneFrame : null,
                child: const Text('Frame at the time'),
              ),
              OutlinedButton(
                onPressed: open ? _makeStrip : null,
                child: const Text('Thumbnail strip'),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: _timeMs.clamp(0, _durationMs.toDouble()),
                  max: _durationMs <= 0 ? 1 : _durationMs.toDouble(),
                  onChanged: open
                      ? (double value) => setState(() => _timeMs = value)
                      : null,
                ),
              ),
              Text('${_timeMs.round()} ms'),
              const SizedBox(width: 12),
              const Text('exact'),
              Checkbox(
                value: _exact,
                onChanged: (bool? value) =>
                    setState(() => _exact = value ?? true),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          SelectableText(_message),
          const SizedBox(height: 8),
          if (_frame != null)
            Image.memory(_frame!, height: 240, gaplessPlayback: true),
          if (_strip.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView(
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
        ],
      ),
    );
  }
}
