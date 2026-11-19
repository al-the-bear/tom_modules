import 'package:flutter/material.dart';

/// A small action button for tree node inline actions.
///
/// Renders as a compact icon button with hover feedback.
/// Used in [NodeActionRow] for operations like add, delete, copy.
///
/// ```dart
/// ActionButton(
///   icon: Icons.add,
///   tooltip: 'Add child key',
///   onPressed: () => addKey(),
/// )
/// ```
class ActionButton extends StatefulWidget {
  /// The icon to display.
  final IconData icon;

  /// Tooltip text.
  final String? tooltip;

  /// Callback when pressed.
  final VoidCallback? onPressed;

  /// Icon size.
  final double size;

  /// Icon color (defaults to theme icon color).
  final Color? color;

  /// Hover background color.
  final Color? hoverColor;

  const ActionButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.size = 16.0,
    this.color,
    this.hoverColor,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget button = Semantics(
      label: widget.tooltip ?? 'Action',
      button: true,
      enabled: widget.onPressed != null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: widget.size + 8,
            height: widget.size + 8,
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.hoverColor ?? Colors.white.withAlpha(25))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: widget.onPressed != null
                  ? (widget.color ?? Theme.of(context).iconTheme.color)
                  : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
