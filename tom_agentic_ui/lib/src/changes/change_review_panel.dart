import 'package:flutter/material.dart';

import 'change_entry.dart';

/// The three-pane **pick-a-pane** review (§9, M1) for a single [ChangeEntry].
///
/// Three read-only panes are shown side by side:
///   1. **Base** — the section value at the last save (`baseAtLastSave`).
///   2. **This edit** — the value this change produced (`afterThisEdit`).
///   3. **Current** — the live value (supplied via [currentValue], since later
///      edits may have changed it).
///
/// This is an inspection/merge view, *not* a blocking gate — the agent's edit
/// already landed. Choosing a pane raises [onPick]; applying that pick is an
/// ordinary, fully-undoable edit that creates a new undo entry (the host wires
/// that through the document controller).
class ChangeReviewPanel extends StatelessWidget {
  /// The entry under review.
  final ChangeEntry entry;

  /// The live current value at [ChangeEntry.sectionId] (review pane 3).
  final String? currentValue;

  /// Raised with the chosen pane when the user applies a pick.
  final ValueChanged<ReviewPane> onPick;

  const ChangeReviewPanel({
    super.key,
    required this.entry,
    required this.onPick,
    this.currentValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            entry.sectionId,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pane(context, 'Base (last save)', ReviewPane.base,
                  entry.baseAtLastSave),
              _pane(context, 'This edit', ReviewPane.thisEdit,
                  entry.afterThisEdit),
              _pane(context, 'Current', ReviewPane.current, currentValue),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pane(
    BuildContext context,
    String title,
    ReviewPane pane,
    String? value,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: SingleChildScrollView(
                  child: Text(value ?? '(empty)'),
                ),
              ),
            ),
            const SizedBox(height: 4),
            OutlinedButton(
              onPressed: () => onPick(pane),
              child: const Text('Use this pane'),
            ),
          ],
        ),
      ),
    );
  }
}
