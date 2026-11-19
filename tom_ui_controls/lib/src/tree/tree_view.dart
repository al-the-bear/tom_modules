import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tree_controller.dart';
import 'tree_node.dart';
import 'tree_theme.dart';

/// Signature for building the content of a single tree node row.
///
/// The builder receives the node, whether it's selected, and a callback
/// to toggle expand/collapse.
typedef TreeNodeBuilder<T> = Widget Function(
  BuildContext context,
  TreeNode<T> node,
  bool isSelected,
);

/// A generic tree view widget that renders [TreeNode] hierarchies.
///
/// Supports:
/// - Expand/collapse with animated toggle
/// - Keyboard navigation (arrow keys, Enter to toggle, Space to select)
/// - Custom node rendering via [nodeBuilder]
/// - Tree line guides
/// - Selection and focus highlighting
///
/// ```dart
/// TreeView<YamlNodeData>(
///   controller: treeController,
///   nodeBuilder: (context, node, isSelected) {
///     return Text(node.data.label);
///   },
/// )
/// ```
class TreeView<T> extends StatefulWidget {
  /// Controller managing expand/collapse, selection, and focus.
  final TreeController<T> controller;

  /// Builder for individual node content.
  final TreeNodeBuilder<T> nodeBuilder;

  /// Visual theme.
  final TreeTheme theme;

  /// Callback when a node is tapped.
  final ValueChanged<TreeNode<T>>? onNodeTap;

  /// Callback when a node is double-tapped.
  final ValueChanged<TreeNode<T>>? onNodeDoubleTap;

  /// Whether keyboard navigation is enabled.
  final bool enableKeyboardNavigation;

  const TreeView({
    super.key,
    required this.controller,
    required this.nodeBuilder,
    this.theme = const TreeTheme(),
    this.onNodeTap,
    this.onNodeDoubleTap,
    this.enableKeyboardNavigation = true,
  });

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

class _TreeViewState<T> extends State<TreeView<T>> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(TreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Defer setState to avoid calling it while the widget tree is locked
    // (e.g. during element unmount when a gesture recognizer fires select).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    var visible = widget.controller.visibleNodes;
    var guides = widget.theme.showTreeLines ? _computeGuides(visible) : null;

    // Always keep KeyboardListener in the widget tree so that toggling
    // enableKeyboardNavigation never changes the root widget type returned
    // from build().  A type change (KeyboardListener ↔ bare ListView) would
    // deactivate the ListView's element and unmount every row State inside it,
    // which breaks any async operation (e.g. context menus) that is waiting
    // across a frame boundary while the subtree gets rebuilt.
    // Instead, simply pass null for onKeyEvent when navigation is disabled.
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: widget.enableKeyboardNavigation ? _handleKeyEvent : null,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: visible.length,
        itemExtent: widget.theme.rowHeight,
        // Right padding wide enough that the macOS/Windows overlay scrollbar
        // thumb (~10 px) does not obscure the action buttons at the row edge.
        padding: const EdgeInsets.only(right: 12),
        itemBuilder: (context, index) {
          return _buildRow(visible[index], guides?[index] ?? const []);
        },
      ),
    );
  }

  Widget _buildRow(TreeNode<T> node, List<_GuideType> guides) {
    return _TreeRow<T>(
      node: node,
      guides: guides,
      controller: widget.controller,
      theme: widget.theme,
      nodeBuilder: widget.nodeBuilder,
      onNodeTap: widget.onNodeTap,
      onNodeDoubleTap: widget.onNodeDoubleTap,
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        widget.controller.focusNext();
      case LogicalKeyboardKey.arrowUp:
        widget.controller.focusPrevious();
      case LogicalKeyboardKey.arrowRight:
        var id = widget.controller.focusedId;
        if (id != null) widget.controller.expand(id);
      case LogicalKeyboardKey.arrowLeft:
        var id = widget.controller.focusedId;
        if (id != null) widget.controller.collapse(id);
      case LogicalKeyboardKey.enter:
        var id = widget.controller.focusedId;
        if (id != null) widget.controller.toggle(id);
      case LogicalKeyboardKey.space:
        var id = widget.controller.focusedId;
        if (id != null) widget.controller.select(id);
    }
  }

  /// Compute indent guide types for every (row, level) pair.
  ///
  /// For each visible node at depth D the result contains a list of length D
  /// describing the guide type at each level 0 … D-1.
  ///
  /// Uses a bottom-to-top scan per level — O(N × maxDepth).
  List<List<_GuideType>> _computeGuides(List<TreeNode<T>> visible) {
    if (visible.isEmpty) return [];

    var maxDepth = 0;
    for (var node in visible) {
      if (node.depth > maxDepth) maxDepth = node.depth;
    }

    var result = List.generate(
      visible.length,
      (i) => List<_GuideType>.filled(visible[i].depth, _GuideType.none),
    );

    for (var level = 0; level < maxDepth; level++) {
      var hasMore = false;
      for (var i = visible.length - 1; i >= 0; i--) {
        if (visible[i].depth <= level) {
          hasMore = false;
        } else if (level < result[i].length) {
          result[i][level] =
              hasMore ? _GuideType.continues : _GuideType.lastChild;
          hasMore = true;
        }
      }
    }

    return result;
  }
}

// ---------------------------------------------------------------------------
// Per-row widget (isolates hover state so mouse events don't rebuild the tree)
// ---------------------------------------------------------------------------

/// A single tree row that manages its own hover state.
///
/// Keeping hover state local prevents [MouseRegion] enter/exit events from
/// triggering a full `setState` rebuild on the parent [TreeView], which would
/// re-layout every visible row on every mouse movement.
class _TreeRow<T> extends StatefulWidget {
  final TreeNode<T> node;
  final List<_GuideType> guides;
  final TreeController<T> controller;
  final TreeTheme theme;
  final TreeNodeBuilder<T> nodeBuilder;
  final ValueChanged<TreeNode<T>>? onNodeTap;
  final ValueChanged<TreeNode<T>>? onNodeDoubleTap;

  const _TreeRow({
    required this.node,
    required this.guides,
    required this.controller,
    required this.theme,
    required this.nodeBuilder,
    this.onNodeTap,
    this.onNodeDoubleTap,
  });

  @override
  State<_TreeRow<T>> createState() => _TreeRowState<T>();
}

class _TreeRowState<T> extends State<_TreeRow<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final theme = widget.theme;
    final guides = widget.guides;

    final isSelected = node.id == widget.controller.selectedId;
    final isFocused = node.id == widget.controller.focusedId;

    Color? bgColor;
    if (isSelected) {
      bgColor = theme.selectionColor;
    } else if (isFocused) {
      bgColor = theme.focusColor;
    } else if (_isHovered) {
      bgColor = theme.hoverColor;
    }

    final indentPx = node.depth * theme.indentWidth;

    // Gesture design:
    // - Arrow icon uses HitTestBehavior.opaque so it exclusively owns its tap
    //   zone. No gesture-arena competition — toggle fires immediately.
    // - Content area (Expanded) handles select/focus via onTap. onDoubleTap
    //   is registered on the content area for non-leaf nodes so Flutter defers
    //   the tap recognizer and allows double-click to also toggle. When null
    //   (leaf nodes), the tap fires immediately too.
    // - There is NO outer row-level GestureDetector. An outer tap-only
    //   GestureDetector would win the arena eagerly (added first) and block
    //   both the arrow tap and the inner double-tap recognizers.
    void selectAndFocus() {
      widget.controller.select(node.id);
      widget.controller.focus(node.id);
      widget.onNodeTap?.call(node);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: theme.rowHeight,
        color: bgColor,
        child: Stack(
          children: [
            // Indent guide lines (painted behind row content)
            if (guides.isNotEmpty)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: indentPx,
                child: CustomPaint(
                  painter: _IndentGuidePainter(
                    guides: guides,
                    indentWidth: theme.indentWidth,
                    color: theme.treeLineColor,
                  ),
                ),
              ),

            // Row content
            Row(
              children: [
                SizedBox(width: indentPx),

                // Expand/collapse toggle.
                // Uses onTapDown (fires immediately on pointer-down, before
                // arena resolution) so the toggle responds with zero delay.
                // GestureDetector.onTap would wait for the Scrollable's drag
                // recognizer to lose the arena (~200ms). Listener.onPointerUp
                // fired on every scroll pointer-up, causing spurious toggles
                // and rebuilds while scrolling which made the tree sluggish.
                if (!node.isLeaf)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => widget.controller.toggle(node.id),
                    child: Icon(
                      node.isExpanded
                          ? theme.expandedIcon
                          : theme.collapsedIcon,
                      size: theme.toggleIconSize,
                      color: theme.toggleIconColor,
                    ),
                  )
                else
                  SizedBox(width: theme.toggleIconSize),

                const SizedBox(width: 4),

                // Content area: select + focus on tap.
                // onDoubleTap is wired for non-leaf nodes so Flutter registers
                // a DoubleTapGestureRecognizer here, causing the TapRecognizer
                // to defer. This allows double-click expand/collapse (inside
                // nodeBuilder via MapNodeRow/ListNodeRow) to work properly.
                // For leaf nodes (no double-tap) the tap fires immediately.
                Expanded(
                  child: GestureDetector(
                    onTap: selectAndFocus,
                    onDoubleTap: !node.isLeaf
                        ? () {
                            widget.controller.toggle(node.id);
                            widget.onNodeDoubleTap?.call(node);
                          }
                        : (widget.onNodeDoubleTap != null
                            ? () => widget.onNodeDoubleTap!.call(node)
                            : null),
                    child: widget.nodeBuilder(context, node, isSelected),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Indent guide painting
// ---------------------------------------------------------------------------

/// Guide line type at a given depth level for one row.
enum _GuideType {
  /// No guide line at this level.
  none,

  /// Full vertical line — more descendants follow at this level.
  continues,

  /// Half vertical (top→centre) — last descendant at this level.
  lastChild,
}

/// Paints VS Code-style indent guide lines for a single tree row.
///
/// One thin vertical line per nesting level. At the deepest level a
/// horizontal branch extends toward the node's toggle / content.
class _IndentGuidePainter extends CustomPainter {
  final List<_GuideType> guides;
  final double indentWidth;
  final Color color;

  _IndentGuidePainter({
    required this.guides,
    required this.indentWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (var i = 0; i < guides.length; i++) {
      var guide = guides[i];
      if (guide == _GuideType.none) continue;

      var x = (i + 0.5) * indentWidth;
      var centerY = size.height / 2;
      var isLast = (i == guides.length - 1);

      switch (guide) {
        case _GuideType.continues:
          // │ — full vertical line
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
          if (isLast) {
            // ├ — T-branch toward the node
            canvas.drawLine(
                Offset(x, centerY), Offset(size.width, centerY), paint);
          }
        case _GuideType.lastChild:
          // top → centre
          canvas.drawLine(Offset(x, 0), Offset(x, centerY), paint);
          if (isLast) {
            // └ — L-branch toward the node
            canvas.drawLine(
                Offset(x, centerY), Offset(size.width, centerY), paint);
          }
        case _GuideType.none:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(_IndentGuidePainter oldDelegate) {
    if (oldDelegate.indentWidth != indentWidth || oldDelegate.color != color) {
      return true;
    }
    if (oldDelegate.guides.length != guides.length) return true;
    for (var i = 0; i < guides.length; i++) {
      if (oldDelegate.guides[i] != guides[i]) return true;
    }
    return false;
  }
}
