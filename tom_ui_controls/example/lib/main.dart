import 'package:flutter/material.dart';
import 'package:tom_ui_controls/tom_ui_controls.dart';

void main() => runApp(const ControlsExampleApp());

/// A tree in a split panel with a search box filtering it; the selected
/// node shows on the right with its validation marker.
class ControlsExampleApp extends StatelessWidget {
  const ControlsExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tom UI Controls',
    theme: ThemeData(useMaterial3: true),
    home: const ControlsExample(),
  );
}

const _files = {
  'docs': ['getting_started.md', 'tree_view.md', 'split_panel.md'],
  'lib': ['main.dart', 'tree.dart'],
  'test': ['tree_test.dart'],
};

/// Files with a validation problem, by name.
const _problems = {
  'tree.dart': [
    ValidationError(path: ['lib', 'tree.dart'], message: 'Unused import'),
  ],
};

class ControlsExample extends StatefulWidget {
  const ControlsExample({super.key});

  @override
  State<ControlsExample> createState() => _ControlsExampleState();
}

class _ControlsExampleState extends State<ControlsExample> {
  late TreeController<String> _tree = _build('');
  String _query = '';

  /// The folders and the files matching [query], every folder expanded
  /// while a query is set.
  TreeController<String> _build(String query) {
    final roots = <TreeNode<String>>[
      for (final MapEntry(key: folder, value: files) in _files.entries)
        if (files.any((f) => f.contains(query)))
          TreeNode(
            id: folder,
            data: folder,
            isExpanded: query.isNotEmpty,
            children: [
              for (final file in files)
                if (file.contains(query))
                  TreeNode(id: '$folder/$file', data: file),
            ],
          ),
    ];
    final controller = TreeController<String>(roots: roots);
    if (query.isNotEmpty) controller.expandAll();
    return controller;
  }

  void _search(String query) {
    final old = _tree;
    setState(() {
      _query = query;
      _tree = _build(query);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _tree.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _tree.selectedId;
    final name = selected?.split('/').last;
    final problems = _problems[name] ?? const <ValidationError>[];
    return Scaffold(
      body: SplitPanel(
        initialRatio: 0.35,
        first: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SearchBox(
                onSearch: _search,
                showNavigation: false,
                hintText: 'Filter files…',
              ),
            ),
            Expanded(
              child: TreeView<String>(
                key: ValueKey(_query),
                controller: _tree,
                onNodeTap: (_) => setState(() {}),
                nodeBuilder: (context, node, isSelected) => Row(
                  children: [
                    Icon(
                      node.isLeaf ? Icons.description : Icons.folder,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(node.data),
                  ],
                ),
              ),
            ),
          ],
        ),
        second: Center(
          child: selected == null
              ? const Text('Select a file')
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(selected),
                    const SizedBox(width: 8),
                    ValidationBadge(errorCount: problems.length),
                  ],
                ),
        ),
      ),
    );
  }
}
