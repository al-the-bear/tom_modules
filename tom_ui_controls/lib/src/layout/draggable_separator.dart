import 'package:flutter/material.dart';

/// Direction of the draggable separator.
enum SeparatorDirection {
  /// Horizontal separator — drag up/down to resize.
  horizontal,

  /// Vertical separator — drag left/right to resize.
  vertical,
}

/// Theme for [DraggableSeparator].
class SeparatorTheme {
  const SeparatorTheme({
    this.color,
    this.hoverColor,
    this.thickness = 4.0,
    this.handleSize = 24.0,
    this.showHandle = true,
  });

  final Color? color;
  final Color? hoverColor;
  final double thickness;
  final double handleSize;
  final bool showHandle;
}

/// A draggable separator between two panels that allows resizing.
///
/// Reports position changes as a ratio (0.0–1.0) relative to the total
/// available size along the drag axis.
class DraggableSeparator extends StatefulWidget {
  const DraggableSeparator({
    super.key,
    required this.direction,
    required this.ratio,
    required this.onRatioChanged,
    this.minRatio = 0.1,
    this.maxRatio = 0.9,
    this.theme = const SeparatorTheme(),
    this.enabled = true,
  });

  final SeparatorDirection direction;

  /// Current position as a ratio 0.0–1.0.
  final double ratio;

  /// Called when the user drags the separator.
  final ValueChanged<double> onRatioChanged;

  /// Minimum allowed ratio.
  final double minRatio;

  /// Maximum allowed ratio.
  final double maxRatio;

  final SeparatorTheme theme;

  /// Whether dragging is enabled.
  final bool enabled;

  @override
  State<DraggableSeparator> createState() => _DraggableSeparatorState();
}

class _DraggableSeparatorState extends State<DraggableSeparator> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor =
        widget.theme.color ?? colorScheme.outlineVariant.withValues(alpha: 0.5);
    final hoverColor = widget.theme.hoverColor ?? colorScheme.primary;
    final color = (_hovering && widget.enabled) ? hoverColor : baseColor;

    final isVertical = widget.direction == SeparatorDirection.vertical;

    return MouseRegion(
      cursor:
          widget.enabled
              ? (isVertical
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.resizeRow)
              : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate:
            widget.enabled
                ? (details) {
                  _handleDrag(context, details);
                }
                : null,
        child: SizedBox(
          width: isVertical ? widget.theme.thickness : double.infinity,
          height: isVertical ? double.infinity : widget.theme.thickness,
          child: Center(
            child: Container(
              width:
                  isVertical
                      ? 2
                      : (widget.theme.showHandle ? widget.theme.handleSize : 0),
              height:
                  isVertical
                      ? (widget.theme.showHandle ? widget.theme.handleSize : 0)
                      : 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleDrag(BuildContext context, DragUpdateDetails details) {
    final renderBox = context.findAncestorRenderObjectOfType<RenderBox>();
    if (renderBox == null) return;

    // Walk up to find the parent that holds total size
    final parentBox =
        context
            .findAncestorRenderObjectOfType<RenderBox>()
            ?.parent as RenderBox?;
    if (parentBox == null) return;

    final isVertical = widget.direction == SeparatorDirection.vertical;
    final totalSize =
        isVertical ? parentBox.size.width : parentBox.size.height;
    if (totalSize <= 0) return;

    final delta = isVertical ? details.delta.dx : details.delta.dy;
    final deltaRatio = delta / totalSize;
    final newRatio = (widget.ratio + deltaRatio).clamp(
      widget.minRatio,
      widget.maxRatio,
    );

    widget.onRatioChanged(newRatio);
  }
}
