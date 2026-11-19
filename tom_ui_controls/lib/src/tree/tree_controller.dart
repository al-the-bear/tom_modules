import 'package:flutter/foundation.dart';

import 'tree_node.dart';

/// Controller for a [TreeView] that manages expand/collapse state, selection,
/// and provides keyboard navigation support.
///
/// ```dart
/// final controller = TreeController<MyData>(roots: myRoots);
///
/// controller.expand('node-3');
/// controller.expandAll();
/// controller.select('node-5');
/// ```
class TreeController<T> extends ChangeNotifier {
  /// The root nodes of the tree.
  List<TreeNode<T>> _roots;

  /// Set of currently expanded node IDs.
  final Set<String> _expandedIds = {};

  /// Currently selected node ID, if any.
  String? _selectedId;

  /// Currently focused node ID (for keyboard navigation), if any.
  String? _focusedId;

  /// Cached visible-node list, invalidated on structural changes.
  List<TreeNode<T>>? _visibleCache;

  /// Creates a tree controller with the given [roots].
  ///
  /// The initial expansion state is synchronised from each node's
  /// [TreeNode.isExpanded] property.
  TreeController({required List<TreeNode<T>> roots}) : _roots = roots {
    // Sync initial expand state from tree nodes
    for (var node in _allNodes) {
      if (node.isExpanded) _expandedIds.add(node.id);
    }
  }

  /// The root nodes.
  List<TreeNode<T>> get roots => _roots;

  /// Update the root nodes (e.g. when the document model changes).
  ///
  /// Expansion rules:
  /// * **Existing nodes** — their expansion state is preserved (controlled by
  ///   [_expandedIds] which reflects the user's explicit expand/collapse actions).
  /// * **New nodes** — expansion state is seeded from [TreeNode.isExpanded] set
  ///   by the caller before assigning roots (so newly inserted containers open
  ///   automatically without requiring a separate expand call).
  /// * Stale IDs (nodes that no longer exist) are pruned from [_expandedIds].
  set roots(List<TreeNode<T>> newRoots) {
    // Snapshot IDs of currently known nodes *before* replacing roots.
    final knownIds = <String>{for (final n in _allNodes) n.id};
    _roots = newRoots;

    // Seed _expandedIds for genuinely-new nodes; prune stale ones.
    final currentIds = <String>{};
    for (final node in _allNodes) {
      currentIds.add(node.id);
      if (!knownIds.contains(node.id) && node.isExpanded) {
        _expandedIds.add(node.id);
      }
    }
    _expandedIds.retainAll(currentIds);

    // Re-apply to keep node.isExpanded in sync with _expandedIds.
    for (final node in _allNodes) {
      node.isExpanded = _expandedIds.contains(node.id);
    }
    notifyListeners();
  }

  /// The currently selected node ID.
  String? get selectedId => _selectedId;

  /// The currently focused node ID.
  String? get focusedId => _focusedId;

  /// All visible nodes (respecting expand/collapse).
  ///
  /// The result is cached and only recomputed when [notifyListeners] is
  /// called (i.e. on expand, collapse, root replacement, etc.).
  List<TreeNode<T>> get visibleNodes {
    return _visibleCache ??= _computeVisibleNodes();
  }

  List<TreeNode<T>> _computeVisibleNodes() {
    var result = <TreeNode<T>>[];
    for (var root in _roots) {
      result.addAll(root.visibleDescendants);
    }
    return result;
  }

  @override
  void notifyListeners() {
    _visibleCache = null;
    super.notifyListeners();
  }

  /// All nodes in the tree, regardless of expand state.
  Iterable<TreeNode<T>> get _allNodes sync* {
    for (var root in _roots) {
      yield root;
      for (var child in root.children) {
        yield* child.allDescendants;
      }
    }
  }

  /// Expand a node by ID.
  void expand(String id) {
    _expandedIds.add(id);
    _findAndUpdate(id, true);
    notifyListeners();
  }

  /// Collapse a node by ID.
  void collapse(String id) {
    _expandedIds.remove(id);
    _findAndUpdate(id, false);
    notifyListeners();
  }

  /// Toggle expand/collapse for a node.
  void toggle(String id) {
    if (_expandedIds.contains(id)) {
      collapse(id);
    } else {
      expand(id);
    }
  }

  /// Expand all nodes.
  void expandAll() {
    for (var node in _allNodes) {
      if (!node.isLeaf) {
        _expandedIds.add(node.id);
        node.isExpanded = true;
      }
    }
    notifyListeners();
  }

  /// Collapse all nodes.
  void collapseAll() {
    _expandedIds.clear();
    for (var node in _allNodes) {
      node.isExpanded = false;
    }
    notifyListeners();
  }

  /// Expand the path to a specific node (so it becomes visible).
  void revealNode(String id) {
    for (var root in _roots) {
      if (_revealInSubtree(root, id)) {
        notifyListeners();
        return;
      }
    }
  }

  /// Select a node by ID.
  void select(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  /// Set focus to a node (keyboard navigation).
  void focus(String? id) {
    _focusedId = id;
    notifyListeners();
  }

  /// Move focus to the next visible node (down arrow).
  void focusNext() {
    var visible = visibleNodes;
    if (visible.isEmpty) return;

    if (_focusedId == null) {
      focus(visible.first.id);
      return;
    }

    var idx = visible.indexWhere((n) => n.id == _focusedId);
    if (idx >= 0 && idx < visible.length - 1) {
      focus(visible[idx + 1].id);
    }
  }

  /// Move focus to the previous visible node (up arrow).
  void focusPrevious() {
    var visible = visibleNodes;
    if (visible.isEmpty) return;

    if (_focusedId == null) {
      focus(visible.last.id);
      return;
    }

    var idx = visible.indexWhere((n) => n.id == _focusedId);
    if (idx > 0) {
      focus(visible[idx - 1].id);
    }
  }

  /// Check if a node is expanded.
  bool isExpanded(String id) => _expandedIds.contains(id);

  void _findAndUpdate(String id, bool expanded) {
    for (var node in _allNodes) {
      if (node.id == id) {
        node.isExpanded = expanded;
        return;
      }
    }
  }

  bool _revealInSubtree(TreeNode<T> node, String targetId) {
    if (node.id == targetId) return true;
    for (var child in node.children) {
      if (_revealInSubtree(child, targetId)) {
        node.isExpanded = true;
        _expandedIds.add(node.id);
        return true;
      }
    }
    return false;
  }
}
