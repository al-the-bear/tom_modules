import 'package:flutter/material.dart';
import 'package:tom_agentic_ui/tom_agentic_ui.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';
import 'package:tom_file_system/tom_file_system.dart';

void main() => runApp(const AgenticExampleApp());

/// The agent connection picker and the chat composer over a fake agent
/// connection: the scan finds one made-up server, and the prompts the
/// composer sends or queues are listed instead of reaching an agent.
class AgenticExampleApp extends StatelessWidget {
  const AgenticExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tom Agentic UI',
    theme: ThemeData(useMaterial3: true),
    home: const AgenticExample(),
  );
}

/// A connection service whose scan answers one server without opening a
/// socket.
BridgeConnectionService fakeConnectionService() => BridgeConnectionService(
  scanner: ({required host, required minPort, required maxPort}) async =>
      const {19900: 'example_workspace'},
);

class AgenticExample extends StatefulWidget {
  const AgenticExample({super.key});

  @override
  State<AgenticExample> createState() => _AgenticExampleState();
}

class _AgenticExampleState extends State<AgenticExample> {
  // One in-memory workspace for the stored connection choice and sessions.
  final _workspace = TomMemoryFileSystem();
  late final _connection = AgentConnectionController(
    service: fakeConnectionService(),
    store: BridgeChoiceStore.resolveDefault(_workspace),
  );
  late final _send = AgentSendController(
    connection: _connection,
    sessionStore: SpecSessionStore.resolveDefault(_workspace),
  );
  final _log = <String>[];

  @override
  void initState() {
    super.initState();
    _connection.scan().ignore();
  }

  @override
  void dispose() {
    _send.dispose();
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agent chat over a fake connection')),
    body: Column(
      children: [
        SizedBox(
          height: 180,
          child: AgentConnectionPicker(controller: _connection),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: const ValueKey('example.log'),
            children: [for (final line in _log) ListTile(title: Text(line))],
          ),
        ),
        // The composer fills the space it is given.
        Expanded(
          flex: 2,
          child: ChatComposerPanel(
            controller: _send,
            onSendNow: (prompt) => setState(() => _log.add('sent: $prompt')),
            onAddToQueue: (prompt) =>
                setState(() => _log.add('queued: $prompt')),
            profiles: const [
              ChatComposerProfile(id: 'engineer', name: 'Engineer'),
              ChatComposerProfile(id: 'reviewer', name: 'Reviewer'),
            ],
            selectedProfileId: 'engineer',
          ),
        ),
      ],
    ),
  );
}
