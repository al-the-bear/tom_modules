/// The tree: the controller's state and the view drawn from it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_controls/tom_ui_controls.dart';

TreeController<String> _tree() => TreeController<String>(
  roots: [
    TreeNode(
      id: 'docs',
      data: 'docs',
      children: [
        TreeNode(id: 'docs/a', data: 'a.md'),
        TreeNode(id: 'docs/b', data: 'b.md'),
      ],
    ),
    TreeNode(id: 'readme', data: 'README.md'),
  ],
);

List<String> _visible(TreeController<String> c) =>
    c.visibleNodes.map((n) => n.id).toList();

void main() {
  test('TUC-T1: expand, collapse, toggle, expandAll and collapseAll', () {
    final tree = _tree();
    addTearDown(tree.dispose);
    expect(_visible(tree), ['docs', 'readme']);
    tree.expand('docs');
    expect(_visible(tree), ['docs', 'docs/a', 'docs/b', 'readme']);
    expect(tree.isExpanded('docs'), isTrue);
    tree.toggle('docs');
    expect(_visible(tree), ['docs', 'readme']);
    tree.expandAll();
    expect(_visible(tree), hasLength(4));
    tree.collapseAll();
    expect(_visible(tree), ['docs', 'readme']);
  });

  test('TUC-T2: select and focus move through the visible nodes', () {
    final tree = _tree()..expand('docs');
    addTearDown(tree.dispose);
    var notified = 0;
    tree.addListener(() => notified++);
    tree.select('docs/b');
    expect(tree.selectedId, 'docs/b');
    tree.focusNext();
    expect(tree.focusedId, 'docs');
    tree.focusNext();
    expect(tree.focusedId, 'docs/a');
    tree.focusPrevious();
    expect(tree.focusedId, 'docs');
    expect(notified, greaterThan(0));
  });

  test('TUC-T3: a node knows its children, depth and descendants', () {
    final root = TreeNode<String>(id: 'r', data: 'r');
    root.addChild(TreeNode(id: 'r/x', data: 'x'));
    expect(root.isLeaf, isFalse);
    expect(root.children.single.depth, 1);
    // Depth first, the node itself included.
    expect(root.allDescendants.map((n) => n.id), ['r', 'r/x']);
    expect(root.removeChild('r/x'), isTrue);
    expect(root.isLeaf, isTrue);
  });

  testWidgets('TUC-T4: the view draws the visible nodes, a tap selects, the '
      'keyboard toggles', (tester) async {
    final tree = _tree();
    addTearDown(tree.dispose);
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreeView<String>(
            controller: tree,
            onNodeTap: (n) => tapped.add(n.id),
            nodeBuilder: (context, node, isSelected) =>
                Text(isSelected ? '[${node.data}]' : node.data),
          ),
        ),
      ),
    );
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('a.md'), findsNothing);

    await tester.tap(find.text('README.md'));
    // The view rebuilds one frame after the controller changes.
    await tester.pump();
    await tester.pump();
    expect(tree.selectedId, 'readme');
    expect(tapped, ['readme']);
    expect(find.text('[README.md]'), findsOneWidget);

    // The click gave the tree the keyboard: the arrows and Enter work at
    // once, with no code focusing it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump();
    expect(tree.focusedId, 'docs');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(tree.isExpanded('docs'), isTrue);
    expect(find.text('a.md'), findsOneWidget);
  });

  testWidgets('TUC-T5: a click into a text field inside a row keeps the text '
      'field focused; a click on a row label gives the tree the keyboard', (
    tester,
  ) async {
    final tree = _tree();
    addTearDown(tree.dispose);
    final field = FocusNode();
    addTearDown(field.dispose);
    final text = TextEditingController(text: 'value');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreeView<String>(
            controller: tree,
            nodeBuilder: (context, node, isSelected) => node.id == 'readme'
                ? Row(
                    children: [
                      Text(node.data),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          key: const Key('inline-editor'),
                          focusNode: field,
                          controller: text,
                        ),
                      ),
                    ],
                  )
                : Text(node.data),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('inline-editor')));
    await tester.pump();
    await tester.pump();
    expect(field.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('inline-editor')), 'typed');
    expect(text.text, 'typed');
    expect(field.hasFocus, isTrue);

    // A click on the row's label takes the keyboard from the field.
    await tester.tap(find.text('README.md'));
    await tester.pump();
    await tester.pump();
    expect(field.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump();
    expect(tree.focusedId, 'docs');
    expect(text.text, 'typed');
  });
}
