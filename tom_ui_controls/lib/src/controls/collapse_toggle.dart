import 'package:flutter/material.dart';

/// An animated expand/collapse toggle icon.
///
/// Shows a chevron that rotates between collapsed (right) and expanded (down)
/// states. For leaf nodes with no children, renders nothing.
///
/// ```dart
/// CollapseToggle(
///   isExpanded: true,
///   onToggle: () => controller.toggle(nodeId),
/// )
/// ```
class CollapseToggle extends StatelessWidget {
  /// Whether the associated node is expanded.
  final bool isExpanded;

  /// Callback when toggled.
  final VoidCallback? onToggle;

  /// Icon size.
  final double size;

  /// Icon color.
  final Color? color;

  /// Animation duration.
  final Duration duration;

  const CollapseToggle({
    super.key,
    required this.isExpanded,
    this.onToggle,
    this.size = 16.0,
    this.color,
    this.duration = const Duration(milliseconds: 150),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isExpanded ? 'Collapse' : 'Expand',
      button: true,
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedRotation(
          turns: isExpanded ? 0.25 : 0.0,
          duration: duration,
          child: Icon(
            Icons.chevron_right,
            size: size,
            color: color ?? Theme.of(context).iconTheme.color,
          ),
        ),
      ),
    );
  }
}
