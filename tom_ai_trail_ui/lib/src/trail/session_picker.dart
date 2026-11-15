/// The session an AI gesture runs in, chosen where the gesture is
/// made.
library;

import 'package:flutter/material.dart';
import 'package:tom_llm/tom_llm.dart';

/// A dropdown of every session; choosing one makes it the
/// session the agent runs in when [agent], and the session of the other AI
/// actions otherwise.
class TomAiSessionPicker extends StatelessWidget {
  const TomAiSessionPicker({
    super.key,
    required this.registry,
    required this.agent,
    this.onChanged,
  });

  final LlmSessionRegistry registry;
  final bool agent;

  /// Called with the chosen session after the registry took it — the agent
  /// run's docked view moves itself to that session's tab.
  final void Function(String id)? onChanged;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream: registry.changes,
        builder: (context, _) {
          final current = agent ? registry.agentSession : registry.actionSession;
          // A labelled field rather than a row with a label beside it: at a
          // phone's width and double text the label and the menu do not fit
          // side by side.
          return DropdownButtonFormField<String>(
            key: ValueKey('tom-ai-session-picker-$current'),
            isExpanded: true,
            initialValue: current,
            decoration: const InputDecoration(labelText: 'Session'),
            items: [
              for (final s in registry.sessions)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    s.kind == LlmSessionKind.quest
                        ? '${s.name} (quest)'
                        : s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              agent ? registry.useForAgent(id) : registry.useForActions(id);
              onChanged?.call(id);
            },
          );
        },
      );
}

/// The line a run's view shows to say which session it is in.
String tomAiSessionLine(LlmSessionRegistry registry, String id) {
  final session = registry.byId(id);
  final name = session?.name ?? id;
  return session?.kind == LlmSessionKind.quest
      ? 'Runs in the $name session, written to its quest folder.'
      : 'Runs in the $name session.';
}
