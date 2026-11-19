import 'package:flutter/material.dart';

import 'draggable_separator.dart';

/// A two-panel layout with a draggable separator between them.
///
/// [direction] controls the split axis:
/// - [Axis.horizontal] places panels side by side (left | right).
/// - [Axis.vertical] stacks panels top and bottom.
class SplitPanel extends StatefulWidget {
  const SplitPanel({
    super.key,
    required this.first,
    required this.second,
    this.direction = Axis.horizontal,
    this.initialRatio = 0.5,
    this.minRatio = 0.1,
    this.maxRatio = 0.9,
    this.separatorTheme = const SeparatorTheme(),
    this.draggable = true,
  });

  final Widget first;
  final Widget second;
  final Axis direction;
  final double initialRatio;
  final double minRatio;
  final double maxRatio;
  final SeparatorTheme separatorTheme;
  final bool draggable;

  @override
  State<SplitPanel> createState() => _SplitPanelState();
}

class _SplitPanelState extends State<SplitPanel> {
  late double _ratio;

  @override
  void initState() {
    super.initState();
    _ratio = widget.initialRatio;
  }

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.direction == Axis.horizontal;
    final separatorDir =
        isHorizontal
            ? SeparatorDirection.vertical
            : SeparatorDirection.horizontal;

    final children = <Widget>[
      Expanded(flex: (_ratio * 1000).round(), child: widget.first),
      DraggableSeparator(
        direction: separatorDir,
        ratio: _ratio,
        onRatioChanged: (r) => setState(() => _ratio = r),
        minRatio: widget.minRatio,
        maxRatio: widget.maxRatio,
        theme: widget.separatorTheme,
        enabled: widget.draggable,
      ),
      Expanded(flex: ((1 - _ratio) * 1000).round(), child: widget.second),
    ];

    return isHorizontal ? Row(children: children) : Column(children: children);
  }
}
