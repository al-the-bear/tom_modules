import 'package:flutter/material.dart';

import 'action_button.dart';

/// A row of action buttons shown inline with a tree node.
///
/// Typically displayed on hover at the right edge of a node row.
/// Supports common operations like add, delete, copy, reorder.
///
/// ```dart
/// NodeActionRow(
///   visible: isHovered,
///   actions: [
///     NodeAction(icon: Icons.add, tooltip: 'Add', onPressed: onAdd),
///     NodeAction(icon: Icons.delete, tooltip: 'Delete', onPressed: onDelete),
///   ],
/// )
/// ```
class NodeActionRow extends StatelessWidget {
  /// Whether the action row is visible.
  final bool visible;

  /// The actions to display.
  final List<NodeAction> actions;

  /// Spacing between action buttons.
  final double spacing;

  const NodeActionRow({
    super.key,
    this.visible = true,
    required this.actions,
    this.spacing = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              ActionButton(
                icon: actions[i].icon,
                tooltip: actions[i].tooltip,
                onPressed: actions[i].onPressed,
                size: actions[i].size,
                color: actions[i].color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Describes a single action in a [NodeActionRow].
class NodeAction {
  /// Icon to display.
  final IconData icon;

  /// Tooltip text.
  final String? tooltip;

  /// Callback when pressed.
  final VoidCallback? onPressed;

  /// Icon size.
  final double size;

  /// Icon color.
  final Color? color;

  const NodeAction({
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.size = 14.0,
    this.color,
  });
}
