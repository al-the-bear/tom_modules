/// The one todo row, shared by every surface that shows a todo as a line
/// rather than as a card: a checklist, an annotation panel, a todo file.
///
/// The row is deliberately **controlled** — it owns no state and reports
/// every change — so one host can edit a document body in place while another
/// writes through its own store, without the row knowing which it is in. Two
/// rows would mean two places to keep the checkbox-is-`not-started`↔
/// `completed`-only rule, two row menus, and two answers to what a blank title
/// means.
library;

import 'package:flutter/material.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

import 'package:tom_ui_support/tom_ui_support.dart';
import 'todo_badges.dart';

/// One todo rendered as a row: checkbox, title field, badges, row menu, and —
/// when [index] is given — a reorder handle.
///
/// [index] is null wherever the row is not inside a `ReorderableListView`; a
/// drag handle outside one throws, so the absence of an index is what makes
/// this reusable rather than a flag that asks for the same thing.
///
/// The title is written however its field is left: Enter, a tap outside, Tab,
/// Shift+Tab, or another control taking the focus. Every way of leaving but
/// Enter ends in the field losing focus, so losing focus is the one commit
/// path beside Enter, and each stay in the field writes at most once — Enter
/// then the blur it causes is one write, and so is a tap outside.
class TomTodoRow extends StatefulWidget {
  const TomTodoRow({
    super.key,
    this.index,
    required this.item,
    required this.readOnly,
    required this.controller,
    required this.focusNode,
    required this.onToggleDone,
    required this.onCommitTitle,
    this.onSubmitted,
    this.onDetails,
    this.onPromote,
    this.onArchive,
    this.onDelete,
    this.selected,
    this.onSelectedChanged,
    this.dragHandle,
    this.onCut,
    this.onCopy,
  });

  /// Whether the row is in its list's selection, shown while the
  /// list is selecting; null outside selection mode.
  final bool? selected;
  final ValueChanged<bool>? onSelectedChanged;

  /// The handle that drags the row (or the selection) to another
  /// list or file; null where nothing may be dragged out.
  final Widget? dragHandle;

  /// Cut and Copy of this row's todo (or the selection), offered
  /// where the host has a clipboard to put it on.
  final VoidCallback? onCut;
  final VoidCallback? onCopy;

  /// Position within the enclosing reorderable list, or null when there is
  /// none.
  final int? index;

  final TomItem item;

  /// A merge view renders base, ours and theirs through this same row. Read-only means no
  /// checkbox, no editable title, no menu and no handle — not a greyed-out copy
  /// of the editing surface.
  final bool readOnly;

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onToggleDone;
  final ValueChanged<String> onCommitTitle;

  /// Enter behaviour. Null where there is no "next row" to insert (an annotation
  /// panel edits one todo, not a list), in which case Enter commits in place.
  final VoidCallback? onSubmitted;

  /// Opens the details editor — status, priority, due date, estimate,
  /// tags, description and dependencies are edited there, not on the row.
  final VoidCallback? onDetails;

  /// Promotion of the item to a section of its own, offered only where the
  /// item lives in a document body.
  ///
  /// Null where the todo lives in a store rather than a body, and absent from
  /// the menu there rather than disabled: there is nothing to move out.
  final VoidCallback? onPromote;

  /// Deletes the item, offered where the host's list owns deletion.
  ///
  /// Null where deleting is the host's own explicit act with its own control
  /// beside the row, and absent from the menu there.
  final VoidCallback? onDelete;

  /// Moves a completed todo to its file's archived sibling.
  ///
  /// Offered only by a host that has a sibling to move to — a todo file. A
  /// section, an annotation and a board card have no archive, so it is null
  /// and absent from the menu there.
  final VoidCallback? onArchive;

  @override
  State<TomTodoRow> createState() => _TomTodoRowState();

  /// Below this width the badges go on a line under the title.
  static const double _stackedBadgesBelow = 520;

  /// The most of the row's width the badges may take; they wrap inside it.
  static const double _badgeShare = 0.5;
}

class _TomTodoRowState extends State<TomTodoRow> {
  /// The text written during the current stay in the field, or null when
  /// nothing has been written since it took the focus. A blur commits only
  /// text that differs from it, so Enter followed by the blur Enter causes
  /// writes once.
  String? _committed;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TomTodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      _committed = null;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      _committed = null;
      return;
    }
    if (widget.readOnly) return;
    final text = widget.controller.text;
    if (text == _committed) return;
    _committed = text;
    widget.onCommitTitle(text);
  }

  void _submit() {
    _committed = widget.controller.text;
    (widget.onSubmitted ?? () => widget.onCommitTitle(_committed!))();
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final item = widget.item;
    final readOnly = widget.readOnly;
    final selected = widget.selected;
    final onSelectedChanged = widget.onSelectedChanged;
    final index = widget.index;
    final dragHandle = widget.dragHandle;
    // A todo that is the user's to do has a purple title, as in the VS Code
    // extension, moved until it reads on the surface in either theme.
    final titleColor = (item.workflow?.userAction ?? false)
        ? tomReadableOn(Colors.purple, Theme.of(context).colorScheme.surface)
        : null;
    final titleStyle = item.isDone || titleColor != null
        ? TextStyle(
            decoration: item.isDone ? TextDecoration.lineThrough : null,
            color: titleColor,
          )
        : null;
    final title = Text(item.headline, style: titleStyle);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      // The row's width decides where the badges go. On a narrow row (a phone,
      // a 260 px annotation panel) they take a line of their own under the
      // title, full width, so the title keeps the row; a title squeezed beside
      // them read 'Draft the bud…' at 390 lp (wonetestb11). On a wide row they
      // sit beside the title, capped at half of it: a `Wrap` placed in a `Row`
      // as a non-flex child is given no width limit, so it never wrapped — a
      // row with a due date, an estimate and three tags ran 450 px past a
      // desktop pane's edge (woneqrc7).
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              constraints.maxWidth < TomTodoRow._stackedBadgesBelow;
          final line = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selected case final isSelected?)
                IconButton(
                  key: Key('todo-select-${item.id}'),
                  tooltip: isSelected ? 'Deselect' : 'Select',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  onPressed: onSelectedChanged == null
                      ? null
                      : () => onSelectedChanged(!isSelected),
                ),
              Checkbox(
                // Keyed per item so the control is addressable rather than found
                // by type. Hosts' suites stub this row and key it exactly
                // this way; an unkeyed production checkbox meant the
                // stub and the real row could not be driven by the same finder,
                // which is how the join between them went untested.
                key: Key('todo-done-${item.id}'),
                value: item.isDone,
                // The checkbox is the `not-started` ↔ `completed` control only;
                // the other three statuses come from the row menu, so a
                // blocked item's box is unchecked and stays that way when clicked
                // into `completed`.
                // A group (`status: group`) is no work: it completes when its
                // members do, never by its own box.
                onChanged: readOnly || item.isGroup ? null : (_) => widget.onToggleDone(),
              ),
              Expanded(
                child: readOnly
                    ? title
                    : TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Todo',
                        ),
                        style: titleStyle,
                        // No rich-text toolbar binds to a title — it is a
                        // plain single-line string, and this is the whole editor
                        // for it.
                        // Exactly two commit paths, Enter and losing focus;
                        // a tap outside only takes the focus away. There is
                        // deliberately no `onEditingComplete` — it fires *in
                        // addition to* `onSubmitted` on a done action, so one
                        // keypress would run two writes and yield two
                        // inverses for a single user action.
                        onSubmitted: (_) => _submit(),
                        onTapOutside: (_) => widget.focusNode.unfocus(),
                      ),
              ),
              if (!narrow)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth.isFinite
                        ? constraints.maxWidth * TomTodoRow._badgeShare
                        : double.infinity,
                  ),
                  child: TomTodoBadges(item: item),
                ),
              if (!readOnly)
                TomTodoRowMenu(
                  onDetails: widget.onDetails,
                  onPromote: widget.onPromote,
                  onArchive: widget.onArchive,
                  onDelete: widget.onDelete,
                  onCut: widget.onCut,
                  onCopy: widget.onCopy,
                ),
              if (!readOnly && dragHandle != null) dragHandle,
              if (!readOnly && index != null)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_handle, size: 18),
                  ),
                ),
            ],
          );
          if (!narrow || !TomTodoBadges.hasAny(item)) return line;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              line,
              Padding(
                key: Key('tom-todo-badges-below-${item.id}'),
                // Under the title, past the checkbox.
                padding: const EdgeInsets.only(left: 48, bottom: 4),
                child: TomTodoBadges(item: item),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The row's menu: the details editor, promotion and deletion.
///
/// Short on purpose. The facets — status, priority, due date, estimate, tags,
/// description, dependencies — are edited in the details dialog; a menu that
/// listed every status and priority as its own entry grew to fifteen entries
/// and filled the window.
class TomTodoRowMenu extends StatelessWidget {
  const TomTodoRowMenu({
    super.key,
    this.onDetails,
    this.onPromote,
    this.onArchive,
    this.onDelete,
    this.onCut,
    this.onCopy,
  });

  final VoidCallback? onDetails;
  final VoidCallback? onPromote;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;

  PopupMenuItem<void> _item(
          String key, VoidCallback onTap, IconData icon, String label) =>
      PopupMenuItem<void>(
        key: Key(key),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    icon: const Icon(Icons.more_horiz, size: 18),
    tooltip: 'Todo options',
    itemBuilder: (context) => [
      if (onDetails != null)
        PopupMenuItem<void>(
          key: const Key('tom-todo-details'),
          onTap: onDetails,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note, size: 16),
              SizedBox(width: 8),
              Flexible(
                child: Text('Details…', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      if (onPromote != null)
        PopupMenuItem<void>(
          key: const Key('tom-todo-promote'),
          onTap: onPromote,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_split, size: 16),
              SizedBox(width: 8),
              Flexible(
                child: Text('Promote to section…', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      if (onCut != null || onCopy != null) const PopupMenuDivider(),
      if (onCut != null)
        _item('tom-todo-row-cut', onCut!, Icons.content_cut, 'Cut'),
      if (onCopy != null)
        _item('tom-todo-row-copy', onCopy!, Icons.content_copy, 'Copy'),
      if (onArchive != null || onDelete != null) const PopupMenuDivider(),
      if (onArchive != null)
        PopupMenuItem<void>(
          key: const Key('tom-todo-archive'),
          onTap: onArchive,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.archive_outlined, size: 16),
              SizedBox(width: 8),
              Flexible(
                child: Text('Archive todo', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      if (onDelete != null) ...[
        PopupMenuItem<void>(
          key: const Key('tom-todo-delete'),
          onTap: onDelete,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 16),
              SizedBox(width: 8),
              Flexible(
                child: Text('Delete todo', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
