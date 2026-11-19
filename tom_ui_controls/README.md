# Tom UI Controls

Flutter controls any application can use. Each imports nothing but Flutter.

| Area | What it holds |
| --- | --- |
| Tree | `TreeView<T>` over a `TreeController<T>` of `TreeNode<T>`s, drawn with a `TreeTheme`: expand and collapse, keyboard navigation (arrows, Enter to toggle, Space to select), indent guides, selection and focus. A `TreeNodeBuilder<T>` draws each row's content. |
| Layout | `SplitPanel` (two children side by side or one above the other) with a `DraggableSeparator` the user drags between `minRatio` and `maxRatio`. |
| Search | `SearchBox`: a search field, an optional replace field, previous and next with *n of m*. |
| Controls | `ActionButton` (a small icon button with hover colour), `CollapseToggle` (an animated chevron), `NodeActionRow` of `NodeAction`s (the actions a row shows on hover). |
| Validation | `ValidationError` (a path, a message, a `ValidationSeverity`), `ErrorPropagator` (errors summed up to every ancestor path), `ValidationBadge` (error and warning counts) and `ValidationTooltip` (the messages), drawn with a `ValidationTheme`. |

Tom Forge's editor kit `tom_editors_shared` depends on this package and
re-exports it, so the YAML, Markdown and specs editors and every application
built on them use these controls.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:tom_ui_controls/tom_ui_controls.dart';

final tree = TreeController<String>(
  roots: [
    TreeNode(id: 'docs', data: 'docs', children: [
      TreeNode(id: 'docs/readme', data: 'README.md'),
    ]),
  ],
);

SplitPanel(
  initialRatio: 0.3,
  first: TreeView<String>(
    controller: tree,
    nodeBuilder: (context, node, isSelected) => Text(node.data),
  ),
  second: SearchBox(onSearch: (text) {}),
);
```

`example/` is that: a tree in a split panel with a search box filtering it.

## License

BSD-3-Clause, see [LICENSE](LICENSE).
