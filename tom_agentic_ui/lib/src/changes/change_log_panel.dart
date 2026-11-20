import 'package:flutter/material.dart';

import 'change_entry.dart';
import 'change_log.dart';

/// The right-panel **Change Log** (§9): lists [ChangeEntry]s newest first,
/// grouped by agent turn, each row showing its section id + summary.
///
/// Selecting a row raises [onSelect] so the host can open the three-way
/// [ChangeReviewPanel] for that entry. The panel is pure UI: it renders over a
/// [ChangeLog] and owns no document state.
class ChangeLogPanel extends StatelessWidget {
  /// The change log to render.
  final ChangeLog log;

  /// The currently selected entry (highlighted), if any.
  final ChangeEntry? selected;

  /// Raised when the user taps an entry row.
  final ValueChanged<ChangeEntry> onSelect;

  const ChangeLogPanel({
    super.key,
    required this.log,
    required this.onSelect,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        if (log.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No agent changes since the last save.'),
            ),
          );
        }
        final groups = log.groups;
        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, i) {
            final group = groups[i];
            return ExpansionTile(
              key: ValueKey(group.turnId),
              initiallyExpanded: true,
              title: Text('Turn ${group.turnId}  ·  ${group.entries.length}'),
              children: [
                for (final entry in group.entries.reversed)
                  ListTile(
                    dense: true,
                    selected: entry.id == selected?.id,
                    title: Text(entry.sectionId),
                    subtitle: Text(entry.summary),
                    onTap: () => onSelect(entry),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
