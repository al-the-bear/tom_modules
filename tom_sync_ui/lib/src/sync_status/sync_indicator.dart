/// One sync state on a status line: icon (or a progress ring), label, tooltip,
/// and the action the state asks for.
library;

import 'package:flutter/material.dart';

import 'sync_presentation.dart';

/// Renders a [TomSyncPresentation].
///
/// One widget for every scope — a unit, a storage location, a workspace —
/// because the difference between them is which status was summarised, not
/// how it looks or what activating it does. The application supplies the two
/// actions a state can ask for; activating the indicator runs the one the
/// presentation names, the key prompt before the merge view (a container that
/// will not open has nothing to merge).
class TomSyncIndicator extends StatelessWidget {
  final TomSyncPresentation presentation;

  /// Drops the label and keeps the icon — a compact strip.
  final bool iconOnly;

  /// Opens the conflict review, for a presentation that asks for it.
  final VoidCallback? onOpenMergeView;

  /// Opens the key prompt, for a presentation that asks for it.
  final VoidCallback? onOpenKeyPrompt;

  /// The key of the tappable surface, for a test or a golden to find it.
  final Key? tapKey;

  /// The key of the progress ring, when one is drawn.
  final Key progressKey;

  const TomSyncIndicator({
    super.key,
    required this.presentation,
    this.iconOnly = false,
    this.onOpenMergeView,
    this.onOpenKeyPrompt,
    this.tapKey,
    this.progressKey = const Key('tom-sync-progress'),
  });

  @override
  Widget build(BuildContext context) {
    final color = presentation.color(context);
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color);

    // The label ellipsizes when — and only when — the caller has bounded us: a
    // status line is one fixed-height row and the text has to give way, but
    // the same widget sits in unbounded rows too, where a `Flexible` would
    // assert. The incoming constraints are the only thing that tells the two
    // apart.
    final row = LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (presentation.progress case final fraction?)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                key: progressKey,
                value: fraction,
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(presentation.icon, size: 14, color: color),
          if (!iconOnly) ...[
            const SizedBox(width: 4),
            if (constraints.maxWidth.isFinite)
              Flexible(
                child: Text(
                  presentation.label,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Text(presentation.label, style: style),
          ],
        ],
      ),
    );

    return Tooltip(
      message: presentation.tooltip,
      child: InkWell(
        key: tapKey,
        onTap: switch (presentation) {
          TomSyncPresentation(opensKeyPrompt: true) => onOpenKeyPrompt,
          TomSyncPresentation(opensMergeView: true) => onOpenMergeView,
          _ => null,
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: row,
        ),
      ),
    );
  }
}
