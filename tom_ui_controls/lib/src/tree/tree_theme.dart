import 'package:flutter/material.dart';

/// Visual theme for the [TreeView] widget.
class TreeTheme {
  /// Color of the tree-line guides.
  final Color treeLineColor;

  /// Color of the expand/collapse toggle icons. Kept apart from
  /// [treeLineColor] because a guide line is decoration and may be faint,
  /// while a toggle is a control and has to be readable on the background.
  final Color toggleIconColor;

  /// Icon for the collapse toggle when expanded.
  final IconData expandedIcon;

  /// Icon for the collapse toggle when collapsed.
  final IconData collapsedIcon;

  /// Background color when hovering over a node.
  final Color hoverColor;

  /// Background color of the selected node.
  final Color selectionColor;

  /// Background color of the focused node (keyboard).
  final Color focusColor;

  /// Indent width per depth level in logical pixels.
  final double indentWidth;

  /// Height of each node row in logical pixels, or null for variable height.
  final double? rowHeight;

  /// Whether to show tree-line guides.
  final bool showTreeLines;

  /// Icon size for expand/collapse toggles.
  final double toggleIconSize;

  /// Text style for node labels.
  final TextStyle? labelStyle;

  const TreeTheme({
    this.treeLineColor = const Color(0xFF404040),
    this.toggleIconColor = const Color(0xFFA0A0A0),
    this.expandedIcon = Icons.expand_more,
    this.collapsedIcon = Icons.chevron_right,
    this.hoverColor = const Color(0x1AFFFFFF),
    this.selectionColor = const Color(0xFF094771),
    this.focusColor = const Color(0xFF062F4A),
    this.indentWidth = 20.0,
    this.rowHeight = 24.0,
    this.showTreeLines = true,
    this.toggleIconSize = 16.0,
    this.labelStyle,
  });

  /// Returns a copy of this theme with the given fields replaced.
  TreeTheme copyWith({
    Color? treeLineColor,
    Color? toggleIconColor,
    IconData? expandedIcon,
    IconData? collapsedIcon,
    Color? hoverColor,
    Color? selectionColor,
    Color? focusColor,
    double? indentWidth,
    double? rowHeight,
    bool? showTreeLines,
    double? toggleIconSize,
    TextStyle? labelStyle,
  }) {
    return TreeTheme(
      treeLineColor: treeLineColor ?? this.treeLineColor,
      toggleIconColor: toggleIconColor ?? this.toggleIconColor,
      expandedIcon: expandedIcon ?? this.expandedIcon,
      collapsedIcon: collapsedIcon ?? this.collapsedIcon,
      hoverColor: hoverColor ?? this.hoverColor,
      selectionColor: selectionColor ?? this.selectionColor,
      focusColor: focusColor ?? this.focusColor,
      indentWidth: indentWidth ?? this.indentWidth,
      rowHeight: rowHeight ?? this.rowHeight,
      showTreeLines: showTreeLines ?? this.showTreeLines,
      toggleIconSize: toggleIconSize ?? this.toggleIconSize,
      labelStyle: labelStyle ?? this.labelStyle,
    );
  }
}
