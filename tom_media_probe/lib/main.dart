import 'package:flutter/material.dart';

import 'src/auto_run.dart';
import 'src/extraction_auto_run.dart';
import 'src/extraction_screen.dart';
import 'src/recording_screen.dart';

/// `--dart-define=PROBE_AUTO=recording` (or `extraction`) starts the
/// automated run of a capability instead of the menu.
const String _auto = String.fromEnvironment('PROBE_AUTO');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MediaProbeApp());
}

class MediaProbeApp extends StatelessWidget {
  const MediaProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tom Media Probe',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: switch (_auto) {
        'recording' => const RecordingAutoRun(),
        'extraction' => const ExtractionAutoRun(),
        _ => const CapabilityMenu(),
      },
    );
  }
}

/// One entry per capability; each prototype todo adds its screen.
class CapabilityMenu extends StatelessWidget {
  const CapabilityMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tom Media Probe')),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Recording'),
            subtitle: const Text(
              'Audio from a microphone, video from a camera',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecordingScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Recording: automated run'),
            subtitle: const Text('Measures every format and writes a report'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecordingAutoRun()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.movie_filter),
            title: const Text('Extraction'),
            subtitle: const Text('The sound and still frames out of a video'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ExtractionScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Extraction: automated run'),
            subtitle: const Text('Measures every fixture and writes a report'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExtractionAutoRun(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
