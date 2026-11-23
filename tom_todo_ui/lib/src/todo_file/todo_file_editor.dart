/// The todo-file editor — a `*.todo.yaml` file as a list of todos, edited
/// with [TomTodoRow] and [showTomTodoDetails], with an aggregate over every
/// todo file under a root and the file's YAML source; a board and moving
/// todos to and from other places are the host's to add.
///
/// The editor writes nothing itself: a change is a text edit through the
/// file's session ([TomTodoFileController]), one history entry per gesture,
/// and the host decides where the file is, how it is saved, which schema
/// applies and who the author is ([TomTodoFileEditorHost]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

import 'package:tom_file_editors/tom_file_editors.dart';
import 'package:tom_ui_support/tom_ui_support.dart';
import '../todo/todo_details.dart';
import '../todo/todo_row.dart';
import 'todo_aggregate.dart';
import 'todo_file_controller.dart';
import 'todo_relocation.dart';
import 'todo_validation.dart';

/// The views of a todo file.
enum TomTodoFileView { list, board, aggregate, source }

/// What the todo-file editor asks of the place it is hosted in: the file's
/// session, name, path, history and notices ([TomFileEditorHost]), the
/// schemas, and the todo file's own needs.
abstract interface class TomTodoFileEditorHost implements TomFileEditorHost {
  /// The schemas the files it opens name.
  TomSchemaCache get schemas;

  /// Checks the file against the schema it names, or the todo model.
  TomTodoFileValidator get validator;

  /// Moves a todo to the file's `-archived` / `-deleted` sibling.
  TomTodoRelocator get relocator;

  /// Today, for date stamps and minted ids.
  DateTime Function() get clock;

  /// Who is editing, as a todo's `completed_by` and a decision's author
  /// record it; null when unknown.
  String? author();

  /// A todo to select and reveal when the editor opens — a link that named
  /// one — taken once; null for none.
  String? takeSelection();

  /// Saves the file through the host's save flow, answering whether it
  /// landed — what a relocation does first when the file has unsaved work.
  Future<bool> save(BuildContext context);

  /// Every todo file under a root, for the aggregate view; null drops the
  /// view.
  TomTodoAggregateSource? get aggregate;

  /// Moving and copying todos to and from other places; null drops the
  /// selection, cut, copy, paste and drag.
  TomTodoFileTransfer? get transfer;

  /// The file as a board, built by the host; null drops the board view.
  Widget Function(BuildContext context, TomTodoFileController controller)?
  get board;
}

/// Moving and copying todos between this file and other places (a host's
/// other todo files, a document's todo lists), as one host does it: its
/// clipboard, its drag payload, its confirmation.
abstract interface class TomTodoFileTransfer {
  /// The selection actions above the list, as the host draws them.
  Widget bar({
    required bool selecting,
    required int selectedCount,
    required VoidCallback onToggleSelecting,
    required VoidCallback? onCut,
    required VoidCallback? onCopy,
    required VoidCallback? onPaste,
  });

  /// Puts [ids] of [controller]'s file on the host's clipboard as a copy.
  Future<void> copy(TomTodoFileController controller, List<String> ids);

  /// Puts [ids] on the clipboard as a move; the editor removes them.
  Future<void> cut(TomTodoFileController controller, List<String> ids);

  /// Lands what the clipboard holds in [controller]'s file after [after],
  /// once the user confirmed it; the todos that landed, or null.
  Future<List<TomItem>?> paste(
    BuildContext context,
    TomTodoFileController controller, {
    String? after,
  });

  /// The handle [ids] are dragged out of the list by; [movedOut] removes them
  /// once a move landed elsewhere.
  Widget dragHandle({
    required TomTodoFileController controller,
    required List<String> ids,
    required String label,
    required VoidCallback movedOut,
  });

  /// The list as a drop target; [landed] reports the todos that landed.
  Widget dropZone({
    required BuildContext context,
    required TomTodoFileController controller,
    required Widget child,
    required String? Function() after,
    required void Function(List<TomItem> todos) landed,
  });
}

/// A todo file's editor.
class TomTodoFileEditor extends StatefulWidget {
  const TomTodoFileEditor({super.key, required this.host});

  final TomTodoFileEditorHost host;

  @override
  State<TomTodoFileEditor> createState() => _TodoFileEditorState();
}

class _TodoFileEditorState extends State<TomTodoFileEditor> {
  TomTodoFileController? _controller;
  TomTodoFileView _view = TomTodoFileView.list;
  String? _selected;

  /// whether rows show their selection control, and which are in it.
  bool _selecting = false;
  final Set<String> _selection = {};

  // The list's filters.
  TomTodoStatus? _status;
  bool _hideDone = false;
  final TextEditingController _query = TextEditingController();

  final Map<String, TextEditingController> _titles = {};
  final Map<String, FocusNode> _focus = {};
  final Map<String, GlobalKey> _rowKeys = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(TomTodoFileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  /// A controller over the host's session — again when the session changed.
  void _bind() {
    final session = widget.host.session;
    if (_controller?.session != session) {
      if (_controller?.session.beforeSave == _beforeSave) {
        _controller!.session.beforeSave = null;
      }
      _controller?.dispose();
      _controller = TomTodoFileController(
        session: session,
        absolutePath: widget.host.filePath,
        validator: widget.host.validator,
        relocator: widget.host.relocator,
        clock: widget.host.clock,
        author: widget.host.author,
      );
      session.beforeSave = _beforeSave;
    }
    final select = widget.host.takeSelection();
    if (select != null) {
      _selected = select;
      _view = TomTodoFileView.list;
      _clearFilters();
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(select));
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null && controller.session.beforeSave == _beforeSave) {
      controller.session.beforeSave = null;
    }
    controller?.dispose();
    _query.dispose();
    for (final c in _titles.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _clearFilters() {
    _status = null;
    _hideDone = false;
    _query.clear();
  }

  void _reveal(String id) {
    final ctx = _rowKeys[id]?.currentContext;
    if (ctx != null) {
      unawaited(Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 200), alignment: 0.3));
    }
  }

  /// a save is refused while the file is invalid, unless the user
  /// insists after reading what is wrong.
  Future<bool> _beforeSave() async {
    final validation = await _controller?.validateNow();
    if (validation == null || validation.valid || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tom-todo-file-invalid'),
        title: const Text('This file does not validate'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(validation.schemaPath == null
                  ? 'The todo model\'s rules refuse it:'
                  : 'The schema ${validation.schemaPath} refuses it:'),
              const SizedBox(height: 8),
              for (final issue in validation.issues.take(20))
                Text('• $issue',
                    style: Theme.of(context).textTheme.bodySmall),
              if (validation.issues.length > 20)
                Text('… and ${validation.issues.length - 20} more.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('tom-todo-file-save-anyway'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final file = controller.file;
        // A file the model cannot read opens in its source, below the
        // reason, so it can be repaired here.
        if (file == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'This is not a todo file the editor can read: '
                  '${controller.parseError ?? 'unknown reason'}. '
                  'Its source is shown below.',
                  key: const Key('tom-todo-file-unreadable'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: TomTodoFileSource(host: widget.host)),
            ],
          );
        }
        return Column(
          key: const Key('tom-todo-file-editor'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(context, controller),
            if (_view == TomTodoFileView.list ||
                _view == TomTodoFileView.board)
              _HeaderPanel(controller: controller),
            if (_view != TomTodoFileView.source)
              _FileIssues(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: switch (_view) {
                TomTodoFileView.list => _list(context, controller, file),
                TomTodoFileView.board =>
                  widget.host.board?.call(context, controller) ??
                      const SizedBox.shrink(),
                TomTodoFileView.aggregate => switch (widget.host.aggregate) {
                  final source? => TomTodoAggregateView(source: source),
                  null => const SizedBox.shrink(),
                },
                TomTodoFileView.source => TomTodoFileSource(host: widget.host),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(BuildContext context, TomTodoFileController controller) {
    final validation = controller.validation;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<TomTodoFileView>(
            key: const Key('tom-todo-file-view'),
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: TomTodoFileView.list,
                icon: Icon(Icons.checklist, size: 16),
                label: Text('List'),
              ),
              if (widget.host.board != null)
                const ButtonSegment(
                  value: TomTodoFileView.board,
                  icon: Icon(Icons.view_kanban_outlined, size: 16),
                  label: Text('Board'),
                ),
              if (widget.host.aggregate != null)
                const ButtonSegment(
                  value: TomTodoFileView.aggregate,
                  icon: Icon(Icons.folder_copy_outlined, size: 16),
                  label: Text('All files'),
                ),
              const ButtonSegment(
                value: TomTodoFileView.source,
                icon: Icon(Icons.code, size: 16),
                label: Text('Source'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
          if (_view == TomTodoFileView.list ||
              _view == TomTodoFileView.board)
            FilledButton.tonalIcon(
              key: const Key('tom-todo-file-add'),
              onPressed: controller.editable
                  ? () => unawaited(_addTodo(context, controller))
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add todo'),
            ),
          if (validation != null && _view != TomTodoFileView.source)
            Tooltip(
              message: validation.schemaPath == null
                  ? (validation.note ?? 'Checked against the todo model')
                  : 'Checked against ${validation.schemaPath}',
              child: Chip(
                key: const Key('tom-todo-file-validity'),
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  validation.valid
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 16,
                  color: validation.valid ? scheme.primary : scheme.error,
                ),
                label: Text(validation.valid
                    ? 'Valid'
                    : '${validation.issues.length} '
                        '${validation.issues.length == 1 ? 'problem' : 'problems'}'),
              ),
            ),
          if (controller.session.readOnlyReason != null)
            Text(controller.session.readOnlyReason!),
        ],
      ),
    );
  }

  // ── List ────────────────────────────────────────────────────────────────

  bool get _filtered =>
      _status != null || _hideDone || _query.text.trim().isNotEmpty;

  bool _matches(TomItem todo) {
    if (_status != null && todo.status != _status) return false;
    if (_hideDone && todo.isDone) return false;
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return todo.id.toLowerCase().contains(q) ||
        todo.headline.toLowerCase().contains(q) ||
        (todo.description ?? '').toLowerCase().contains(q) ||
        todo.tags.any((t) => t.toLowerCase().contains(q));
  }

  Widget _list(
    BuildContext context,
    TomTodoFileController controller,
    TomTodoFile file,
  ) {
    final entries = [
      for (final e in file.entries)
        if (e.item == null || _matches(e.item!)) e,
    ];
    // A wrap rather than a row: in a pane half a window wide the filters and
    // the transfer bar do not fit one line.
    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('tom-todo-file-search'),
              controller: _query,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Filter by id, title, tag',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          DropdownButton<TomTodoStatus?>(
            key: const Key('tom-todo-file-status-filter'),
            value: _status,
            hint: const Text('Any status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any status')),
              for (final s in TomTodoStatus.values)
                DropdownMenuItem(value: s, child: Text(s.wire)),
            ],
            onChanged: (v) => setState(() => _status = v),
          ),
          FilterChip(
            label: const Text('Hide done'),
            selected: _hideDone,
            onSelected: (v) => setState(() => _hideDone = v),
          ),
          Text('${entries.length} of ${file.entries.length}',
              style: Theme.of(context).textTheme.labelSmall),
          if (widget.host.transfer case final transfer?) transfer.bar(
            selecting: _selecting,
            selectedCount: _selection.length,
            onToggleSelecting: () => setState(() {
              _selecting = !_selecting;
              if (!_selecting) _selection.clear();
            }),
            onCut: _selection.isEmpty || !controller.editable
                ? null
                : () => unawaited(_cut(controller, _idsFor(file, null))),
            onCopy: _selection.isEmpty
                ? null
                : () => unawaited(_copy(controller, _idsFor(file, null))),
            onPaste: controller.editable
                ? () => unawaited(_paste(context, controller))
                : null,
          ),
        ],
      ),
    );
    final transfer = widget.host.transfer;
    Widget droppable(Widget child) => !controller.editable || transfer == null
        ? child
        : transfer.dropZone(
            context: context,
            controller: controller,
            child: child,
            after: () => _selected,
            landed: _landed,
          );
    if (file.entries.isEmpty) {
      return Column(children: [
        filters,
        Expanded(
          child: droppable(
              const Center(child: Text('No todos in this file yet.'))),
        ),
      ]);
    }
    final reorderable = !_filtered && controller.editable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filters,
        Expanded(
          child: droppable(ReorderableListView.builder(
            key: const Key('tom-todo-file-list'),
            buildDefaultDragHandles: false,
            itemCount: entries.length,
            onReorderItem: (from, to) {
              if (!reorderable) return;
              controller.move(entries[from].index, entries[to].index);
            },
            itemBuilder: (context, i) =>
                _row(context, controller, file, entries[i],
                    reorderable ? i : null),
          )),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    TomTodoFileController controller,
    TomTodoFile file,
    TomTodoFileEntry entry,
    int? index,
  ) {
    final key = _rowKeys.putIfAbsent(entry.id, GlobalKey.new);
    final scheme = Theme.of(context).colorScheme;
    final issues = controller.validation?.forTodo(entry.index) ?? const [];
    final todo = entry.item;
    final Widget body;
    if (todo == null) {
      body = ListTile(
        dense: true,
        leading: Icon(Icons.error_outline, color: scheme.error),
        title: Text(entry.id.isEmpty ? 'Todo ${entry.index + 1}' : entry.id),
        subtitle: Text('Shown, not edited: ${entry.error}'),
      );
    } else {
      final title = _titles.putIfAbsent(
          entry.id, () => TextEditingController(text: todo.headline));
      final focus = _focus.putIfAbsent(entry.id, FocusNode.new);
      if (!focus.hasFocus && title.text != todo.headline) title.text = todo.headline;
      final editable = controller.editable;
      body = TomTodoRow(
        index: index,
        item: todo,
        readOnly: !editable,
        controller: title,
        focusNode: focus,
        onToggleDone: () => controller.toggleDone(entry.index),
        onCommitTitle: (text) {
          if (text.trim() != todo.headline) controller.retitle(entry.index, text);
        },
        onDetails: () => unawaited(_details(context, controller, file, entry)),
        onArchive: controller.relocationRefusal(
                    entry.index, TomTodoRelocationKind.archive) ==
                null
            ? () => unawaited(_relocate(context, controller, entry,
                TomTodoRelocationKind.archive))
            : null,
        onDelete: controller.relocationRefusal(
                    entry.index, TomTodoRelocationKind.delete) ==
                null
            ? () => unawaited(_relocate(context, controller, entry,
                TomTodoRelocationKind.delete))
            : null,
        selected: _selecting && widget.host.transfer != null
            ? _selection.contains(entry.id)
            : null,
        onSelectedChanged: (on) => setState(() {
          if (on) {
            _selection.add(entry.id);
          } else {
            _selection.remove(entry.id);
          }
        }),
        onCut: editable && widget.host.transfer != null
            ? () => unawaited(_cut(controller, _idsFor(file, entry.id)))
            : null,
        onCopy: widget.host.transfer == null
            ? null
            : () => unawaited(_copy(controller, _idsFor(file, entry.id))),
        dragHandle: switch (widget.host.transfer) {
          final transfer? when editable => transfer.dragHandle(
            controller: controller,
            ids: _idsFor(file, entry.id),
            label: _idsFor(file, entry.id).length == 1
                ? todo.headline
                : '${_idsFor(file, entry.id).length} todos',
            movedOut: () => _movedOut(controller, _idsFor(file, entry.id)),
          ),
          _ => null,
        },
      );
    }
    return Container(
      key: ValueKey('tom-todo-file-row-${entry.id}-${entry.index}'),
      color: _selected == entry.id ? scheme.secondaryContainer : null,
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  entry.id,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          body,
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 8, 4),
              child: Text(
                '${issue.path.isEmpty ? '' : '${issue.path.substring(1)}: '}'
                '${issue.message}',
                key: Key('tom-todo-file-issue-${entry.index}'),
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ── moving and copying, through the host's transfer ────────────────────

  /// The ids a gesture on [id] acts on: the selection when the todo is in
  /// it, the todo alone otherwise; the selection with no todo named.
  List<String> _idsFor(TomTodoFile file, String? id) {
    if (id == null || _selection.contains(id)) {
      return [for (final t in file.items) if (_selection.contains(t.id)) t.id];
    }
    return [id];
  }

  Future<void> _copy(TomTodoFileController controller, List<String> ids) async {
    final transfer = widget.host.transfer;
    if (transfer == null || ids.isEmpty) return;
    await transfer.copy(controller, ids);
  }

  Future<void> _cut(TomTodoFileController controller, List<String> ids) async {
    final transfer = widget.host.transfer;
    if (transfer == null || ids.isEmpty || !controller.editable) return;
    await transfer.cut(controller, ids);
    if (!mounted) return;
    controller.removeMany(
      ids.toSet(),
      ids.length == 1 ? 'Cut `${ids.single}`' : 'Cut ${ids.length} todos',
    );
    setState(() => _selection.removeAll(ids));
  }

  /// A dragged move landed elsewhere: the todos leave this file.
  void _movedOut(TomTodoFileController controller, List<String> ids) {
    if (!mounted) return;
    final idSet = ids.toSet();
    controller.removeMany(
      idSet,
      idSet.length == 1 ? 'Move todo out' : 'Move ${idSet.length} todos out',
    );
    setState(() => _selection.removeAll(idSet));
  }

  Future<void> _paste(
    BuildContext context,
    TomTodoFileController controller,
  ) async {
    final transfer = widget.host.transfer;
    if (transfer == null) return;
    final todos = await transfer.paste(context, controller, after: _selected);
    if (todos != null) _landed(todos);
  }

  /// Todos landed in this file: the last is selected, the filters cleared.
  void _landed(List<TomItem> todos) {
    if (todos.isEmpty || !mounted) return;
    setState(() {
      _selected = todos.last.id;
      _clearFilters();
    });
  }

  Future<void> _details(
    BuildContext context,
    TomTodoFileController controller,
    TomTodoFile file,
    TomTodoFileEntry entry,
  ) async {
    final edited = await showTomTodoDetails(
      context,
      todo: entry.item!.copy(),
      candidates: [
        for (final other in file.items)
          if (other.id != entry.id)
            TomTodoCandidate(
              id: other.id,
              title: other.headline,
              where: controller.fileName,
            ),
      ],
      author: controller.author(),
    );
    if (edited == null || !mounted) return;
    final current = controller.file?.entryFor(entry.id);
    if (current == null) return;
    controller.write(current.index, edited, 'Edit `${entry.id}`');
  }

  Future<void> _relocate(
    BuildContext context,
    TomTodoFileController controller,
    TomTodoFileEntry entry,
    TomTodoRelocationKind kind,
  ) async {
    final sibling = tomTodoSiblingName(controller.fileName, kind);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: Key('tom-todo-file-confirm-${kind.name}'),
        title: Text('${kind.verb} `${entry.id}`?'),
        content: Text(
          '${kind == TomTodoRelocationKind.archive ? 'The todo moves to' : 'The todo moves to'} '
          '$sibling, stamped "${kind.stamp}: ${TomItem.encodeDate(controller.today)}". '
          '${controller.session.dirty ? 'Your other unsaved changes to this file are saved first. ' : ''}'
          'This writes the files now; Undo moves it back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('tom-todo-file-relocate'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(kind.verb),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (controller.session.dirty &&
          !await widget.host.save(context)) {
        return;
      }
      final current = controller.file?.entryFor(entry.id);
      if (current == null) return;
      await controller.relocate(current.index, kind);
      tomShowNotice(
        messenger,
        kind: 'todo-relocation',
        message: '${kind == TomTodoRelocationKind.archive ? 'Archived' : 'Deleted'} '
            '`${entry.id}` to $sibling.',
      );
    } on Object catch (e) {
      tomShowNotice(messenger, kind: 'todo-relocation', message: '$e');
    }
  }

  Future<void> _addTodo(
    BuildContext context,
    TomTodoFileController controller,
  ) async {
    final ids = await controller.folderIds();
    if (!context.mounted) return;
    final todo = await showDialog<TomItem>(
      context: context,
      builder: (context) => _AddTodoDialog(
        controller: controller,
        folderIds: ids,
      ),
    );
    if (todo == null || !mounted) return;
    controller.add(todo);
    setState(() {
      _selected = todo.id;
      _clearFilters();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(todo.id));
  }
}

/// the file-level keys, shown and edited above the list.
class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({required this.controller});

  final TomTodoFileController controller;

  @override
  Widget build(BuildContext context) {
    final header = controller.file!.header;
    final editable = controller.editable;
    String text(String key) => header[key]?.toString() ?? '';
    Widget field(String key, String label, {double width = 160}) => SizedBox(
          width: width,
          child: _CommitField(
            key: Key('tom-todo-file-header-$key'),
            label: label,
            value: text(key),
            enabled: editable,
            onCommit: (v) =>
                controller.setFileKey(key, v.trim().isEmpty ? null : v.trim()),
          ),
        );
    final scope = header['scope'];
    final references = header['references'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          field('quest', 'Quest'),
          field('author', 'Author'),
          field('created', 'Created', width: 110),
          field('updated', 'Updated', width: 110),
          TextButton.icon(
            key: const Key('tom-todo-file-header-more'),
            onPressed: editable
                ? () => unawaited(_editScope(context, controller))
                : null,
            icon: const Icon(Icons.tune, size: 16),
            label: Text([
              if (scope is Map && scope.isNotEmpty) 'Scope',
              if (references is List && references.isNotEmpty)
                '${references.length} references',
            ].join(', ').ifEmpty('Scope and references…')),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// The file's scope and references in one dialog.
Future<void> _editScope(
  BuildContext context,
  TomTodoFileController controller,
) async {
  final header = controller.file!.header;
  final scopeMap = header['scope'];
  final scope = scopeMap is Map
      ? TomTodoScope.fromMap(scopeMap)
      : TomTodoScope();
  final refs = [
    for (final r in (header['references'] as List? ?? const []))
      if (r is Map) TomTodoReference.fromMap(r),
  ];
  final project = TextEditingController(text: scope.project ?? '');
  final module = TextEditingController(text: scope.module ?? '');
  final area = TextEditingController(text: scope.area ?? '');
  final files = TextEditingController(text: scope.files.join('\n'));
  final references = TextEditingController(text: [
    for (final r in refs)
      [r.path ?? r.url ?? '', if (r.description != null) r.description]
          .join(' — '),
  ].join('\n'));
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tom-todo-file-scope-dialog'),
        title: const Text('Scope and references'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextField(
                  controller: project,
                  decoration: const InputDecoration(labelText: 'Project')),
              TextField(
                  controller: module,
                  decoration: const InputDecoration(labelText: 'Module')),
              TextField(
                  controller: area,
                  decoration: const InputDecoration(labelText: 'Area')),
              TextField(
                controller: files,
                maxLines: 4,
                minLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Files, one per line'),
              ),
              TextField(
                key: const Key('tom-todo-file-references'),
                controller: references,
                maxLines: 6,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'References, one per line',
                  helperText: 'A path or URL, then " — " and a description',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('tom-todo-file-scope-apply'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    String? or(String v) => v.trim().isEmpty ? null : v.trim();
    final nextScope = TomTodoScope(
      project: or(project.text),
      projects: scope.projects,
      module: or(module.text),
      area: or(area.text),
      files: [
        for (final f in files.text.split('\n'))
          if (f.trim().isNotEmpty) f.trim(),
      ],
      path: scope.path,
    );
    final nextRefs = [
      for (final line in references.text.split('\n'))
        if (line.trim().isNotEmpty) _reference(line.trim()),
    ];
    final file = controller.file!;
    var text = file.withFileKey(
        'scope', nextScope.isEmpty ? null : nextScope.toMap());
    text = TomTodoFile.parse(text).withFileKey('references',
        nextRefs.isEmpty ? null : [for (final r in nextRefs) r.toMap()]);
    if (text != controller.session.text) {
      controller.session.edit(text, 'Edit the file\'s scope and references');
    }
  } finally {
    for (final c in [project, module, area, files, references]) {
      c.dispose();
    }
  }
}

TomTodoReference _reference(String line) {
  final parts = line.split(' — ');
  final target = parts.first.trim();
  final description =
      parts.length > 1 ? parts.sublist(1).join(' — ').trim() : null;
  final url = Uri.tryParse(target)?.hasScheme ?? false;
  return TomTodoReference(
    path: url ? null : target,
    url: url ? target : null,
    description: description,
  );
}

/// The file-level problems — those no single todo carries.
class _FileIssues extends StatelessWidget {
  const _FileIssues({required this.controller});

  final TomTodoFileController controller;

  @override
  Widget build(BuildContext context) {
    final validation = controller.validation;
    final issues = validation?.fileIssues.toList() ?? const [];
    final note = validation?.note;
    if (issues.isEmpty && note == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null)
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          for (final issue in issues)
            Text(issue.message,
                key: const Key('tom-todo-file-file-issue'),
                style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A text field that reports its value when the user commits it — Enter or
/// leaving the field — and shows the stored value otherwise.
class _CommitField extends StatefulWidget {
  const _CommitField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onCommit,
  });

  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onCommit;

  @override
  State<_CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<_CommitField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_CommitField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != widget.value) {
      _text.text = widget.value;
    }
  }

  void _commit() {
    if (_text.text != widget.value) widget.onCommit(_text.text);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        enabled: widget.enabled,
        decoration: InputDecoration(isDense: true, labelText: widget.label),
        onSubmitted: (_) => _commit(),
      );
}

/// a new todo — its id by the date-code convention, with the
/// stem-reuse warning, its title and description.
class _AddTodoDialog extends StatefulWidget {
  const _AddTodoDialog({required this.controller, required this.folderIds});

  final TomTodoFileController controller;
  final Set<String> folderIds;

  @override
  State<_AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends State<_AddTodoDialog> {
  late final TextEditingController _base = TextEditingController(
      text: widget.controller.suggestedBase(widget.folderIds));
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  @override
  void dispose() {
    _base.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String? get _id {
    final base = _base.text.trim();
    if (!tomIsTodoBase(base)) return null;
    return tomMintTodoId(base, widget.controller.clock(),
        slug: _title.text);
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    final scheme = Theme.of(context).colorScheme;
    final duplicate = id != null && widget.folderIds.contains(id);
    final warning = id == null
        ? null
        : tomTodoStemReuseWarning(id, tomTodoStemReuse(id, widget.folderIds));
    final ready = id != null &&
        !duplicate &&
        _title.text.trim().isNotEmpty &&
        _description.text.trim().isNotEmpty;
    return AlertDialog(
      key: const Key('tom-todo-file-add-dialog'),
      title: const Text('Add todo'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('tom-todo-file-add-base'),
              controller: _base,
              decoration: const InputDecoration(
                labelText: 'Base id',
                helperText: 'Letters and digits; the date code is added',
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('tom-todo-file-add-title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('tom-todo-file-add-description'),
              controller: _description,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              id == null ? 'The base id is not valid.' : 'Id: $id',
              key: const Key('tom-todo-file-add-id'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (duplicate)
              Text('This id is already used in this folder.',
                  style: TextStyle(color: scheme.error)),
            if (warning != null)
              Text(warning,
                  key: const Key('tom-todo-file-add-warning'),
                  style: TextStyle(color: scheme.tertiary)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('tom-todo-file-add-confirm'),
          onPressed: !ready
              ? null
              : () => Navigator.pop(
                    context,
                    TomItem(
                      id: id,
                      headline: _title.text.trim(),
                      description: _description.text.trim(),
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// A todo file's YAML source: the file's text, edited through its session as
/// the todos are, so the list and the source share the file's one history.
class TomTodoFileSource extends StatelessWidget {
  const TomTodoFileSource({super.key, required this.host});

  final TomFileEditorHost host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: TomFileSessionListenable(host.session),
        builder: (context, _) {
          final session = host.session;
          return TomTextSource(
            key: const Key('tom-todo-file-source'),
            highlighter: tomYamlSourceHighlighter(
              Theme.of(context).colorScheme,
            ),
            text: session.text,
            readOnly: session.readOnlyReason != null,
            onChanged: (text) =>
                session.edit(text, 'Edit ${host.name}', group: 'typing'),
            onUndo: () => unawaited(host.undo(context)),
            onRedo: () => unawaited(host.redo(context)),
            onSelectionMoved: session.endGesture,
          );
        },
      );
}
