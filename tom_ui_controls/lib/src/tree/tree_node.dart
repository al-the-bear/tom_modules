/// A node in a generic tree structure.
///
/// Each node holds data of type [T], an optional list of children,
/// and tracks whether it is currently expanded in the UI.
///
/// ```dart
/// final root = TreeNode<String>(
///   id: 'root',
///   data: 'Root',
///   children: [
///     TreeNode(id: 'child1', data: 'Child 1'),
///     TreeNode(id: 'child2', data: 'Child 2'),
///   ],
/// );
/// ```
class TreeNode<T> {
  /// Unique identifier for this node.
  final String id;

  /// The data payload.
  final T data;

  /// This node's children (empty for leaves).
  final List<TreeNode<T>> children;

  /// Whether this node is currently expanded in the tree view.
  bool isExpanded;

  /// Depth of this node in the tree (0 for roots).
  int depth;

  /// Creates a tree node with the given [id] and [data].
  ///
  /// Optionally provide [children], an initial [isExpanded] state, and a
  /// [depth] (defaults to 0). Child depths are updated automatically.
  TreeNode({
    required this.id,
    required this.data,
    List<TreeNode<T>>? children,
    this.isExpanded = false,
    this.depth = 0,
  }) : children = children ?? [] {
    _updateChildDepths();
  }

  /// Whether this node has children.
  bool get isLeaf => children.isEmpty;

  /// Whether this node has children and is not expanded.
  bool get isCollapsed => !isLeaf && !isExpanded;

  /// Add a child node, updating its depth.
  void addChild(TreeNode<T> child) {
    children.add(child);
    child.depth = depth + 1;
    child._updateChildDepths();
  }

  /// Remove a child by ID. Returns true if a child was removed.
  bool removeChild(String childId) {
    var before = children.length;
    children.removeWhere((c) => c.id == childId);
    return children.length < before;
  }

  /// Find a descendant by ID using depth-first search.
  TreeNode<T>? findById(String targetId) {
    if (id == targetId) return this;
    for (var child in children) {
      var found = child.findById(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// Iterate all nodes depth-first (including this node).
  Iterable<TreeNode<T>> get allDescendants sync* {
    yield this;
    for (var child in children) {
      yield* child.allDescendants;
    }
  }

  /// The visible nodes when respecting expand/collapse state.
  Iterable<TreeNode<T>> get visibleDescendants sync* {
    yield this;
    if (isExpanded) {
      for (var child in children) {
        yield* child.visibleDescendants;
      }
    }
  }

  void _updateChildDepths() {
    for (var child in children) {
      child.depth = depth + 1;
      child._updateChildDepths();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TreeNode($id, children: ${children.length}, expanded: $isExpanded)';
}
