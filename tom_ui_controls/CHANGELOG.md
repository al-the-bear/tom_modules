# Changelog

## 0.1.0

- `TreeView`: a click on a row's content gives the tree the keyboard, so the
  arrows, Enter and Space work at once (a focusable child of the row, such as
  an inline text field, keeps its own focus); a controller change schedules
  the frame that redraws the tree, so a change from the keyboard is drawn at
  once instead of with the next frame something else asks for.
- The tree view (`TreeView`, `TreeController`, `TreeNode`, `TreeTheme`), the
  split panels (`SplitPanel`, `DraggableSeparator`), the search box
  (`SearchBox`), the small controls (`ActionButton`, `CollapseToggle`,
  `NodeActionRow`) and the validation markers (`ValidationBadge`,
  `ValidationTooltip`, `ValidationError`, `ErrorPropagator`), taken out of
  Tom Forge's `tom_editors_shared`, which re-exports them.
- Widget tests for each, and an example: a tree in a split panel with a
  search box.
