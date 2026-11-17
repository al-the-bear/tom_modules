/// Every todo file under a root, as one list.
///
/// Scanned lazily — a background walk that fills the list as it finds files
/// and never enters a hidden folder — and filtered by status, priority, tags,
/// quest, file subkind, blocked and decision-needed. Archived and deleted
/// siblings are included only while the source says so. Choosing a
/// row opens its file with the todo selected.
library;

import 'package:tom_basics/utilities.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

/// Where the aggregate view reads its todo files from, as one host has them.
abstract interface class TomTodoAggregateSource {
  /// The tree under the root, walked for `*.todo.yaml` files.
  TomFileSystem get tree;

  /// Whether the `-archived` / `-deleted` siblings are included — a root's
  /// own choice, where its host keeps one.
  bool get includeSiblings;

  /// Opens [id] of the todo file at [path] under the root.
  void openTodo(String path, String id);
}

/// One todo found by the walk.
class TomAggregateTodo {
  const TomAggregateTodo({
    required this.todo,
    required this.path,
    required this.name,
    required this.quest,
  });

  final TomTodo todo;

  /// The file's path under the root.
  final String path;

  /// The file's parsed name: family, sibling, quest.
  final TomTodoFileName? name;

  /// The `quest:` key, or the quest the file name carries.
  final String? quest;
}

/// The walk: every `*.todo.yaml` under [tree]'s root, and the todos in it.
///
/// [includeSiblings] is the root's `todoSiblings` choice. At most [limit]
/// files are read, so a root pointed at a home folder ends rather than runs.
Stream<List<TomAggregateTodo>> tomScanTodoFiles(
  TomFileSystem tree, {
  required bool includeSiblings,
  int limit = 2000,
}) async* {
  final queue = <String>[''];
  var files = 0;
  while (queue.isNotEmpty && files < limit) {
    final dir = queue.removeAt(0);
    final List<TomFileEntry> entries;
    try {
      entries = await tree.list(tree.uriOf(dir));
    } on Object {
      continue;
    }
    final found = <TomAggregateTodo>[];
    for (final entry in entries) {
      if (entry.name.startsWith('.') || entry.name == 'node_modules') continue;
      if (entry.isDirectory) {
        if (entry.expandable) queue.add(entry.path);
        continue;
      }
      if (!entry.name.endsWith('.todo.yaml')) continue;
      final name = TomTodoFileName.parse(entry.name);
      if (!includeSiblings &&
          name != null &&
          name.sibling != TomTodoFileSibling.live) {
        continue;
      }
      files++;
      try {
        final content = await tree.read(tree.uriOf(entry.path));
        final file =
            TomTodoFile.parse(tomDecodeTextBytes(content.bytes).text);
        for (final todo in file.todos) {
          found.add(TomAggregateTodo(
            todo: todo,
            path: entry.path,
            name: name,
            quest: file.quest ?? name?.quest,
          ));
        }
      } on Object {
        // A file that is not a todo file contributes nothing.
      }
    }
    if (found.isNotEmpty) yield found;
  }
}

/// The aggregate view over [root].
class TomTodoAggregateView extends StatefulWidget {
  const TomTodoAggregateView({super.key, required this.source});

  final TomTodoAggregateSource source;

  @override
  State<TomTodoAggregateView> createState() => _AggregateState();
}

class _AggregateState extends State<TomTodoAggregateView> {
  final List<TomAggregateTodo> _todos = [];
  StreamSubscription<List<TomAggregateTodo>>? _scan;
  bool _scanning = false;

  TomTodoStatus? _status;
  TomTodoPriority? _priority;
  String? _quest;
  TomTodoFileFamily? _family;
  bool _blocked = false;
  bool _decision = false;
  bool _hideDone = true;
  final TextEditingController _tag = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rescan();
  }

  @override
  void dispose() {
    unawaited(_scan?.cancel());
    _tag.dispose();
    super.dispose();
  }

  void _rescan() {
    unawaited(_scan?.cancel());
    setState(() {
      _todos.clear();
      _scanning = true;
    });
    _scan = tomScanTodoFiles(
      widget.source.tree,
      includeSiblings: widget.source.includeSiblings,
    ).listen(
      (batch) {
        if (mounted) setState(() => _todos.addAll(batch));
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  bool _matches(TomAggregateTodo row) {
    final t = row.todo;
    if (_status != null && t.status != _status) return false;
    if (_priority != null && t.priority != _priority) return false;
    if (_quest != null && row.quest != _quest) return false;
    if (_family != null && row.name?.family != _family) return false;
    if (_blocked && t.status != TomTodoStatus.blocked && !t.hasBlocker) {
      return false;
    }
    if (_decision &&
        t.status != TomTodoStatus.decisionNeeded &&
        !t.hasOpenDecision) {
      return false;
    }
    if (_hideDone && t.isDone) return false;
    final tag = _tag.text.trim().toLowerCase();
    if (tag.isNotEmpty && !t.tags.any((x) => x.toLowerCase().contains(tag))) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _todos.where(_matches).toList();
    final quests = {
      for (final t in _todos)
        if (t.quest != null) t.quest!,
    }.toList()
      ..sort();
    final theme = Theme.of(context);
    return Column(
      key: const Key('tom-todo-aggregate'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _drop<TomTodoStatus>('Any status', _status,
                  TomTodoStatus.values, (s) => s.wire,
                  (v) => setState(() => _status = v)),
              _drop<TomTodoPriority>('Any priority', _priority,
                  TomTodoPriority.values, (s) => s.wire,
                  (v) => setState(() => _priority = v)),
              _drop<String>('Any quest', _quest, quests, (q) => q,
                  (v) => setState(() => _quest = v)),
              _drop<TomTodoFileFamily>('Any file', _family,
                  TomTodoFileFamily.values, (f) => switch (f) {
                        TomTodoFileFamily.quest => 'Quest todo files',
                        TomTodoFileFamily.session => 'Session todo files',
                        TomTodoFileFamily.other => 'Other todo files',
                      }, (v) => setState(() => _family = v)),
              SizedBox(
                width: 140,
                child: TextField(
                  key: const Key('tom-todo-aggregate-tag'),
                  controller: _tag,
                  decoration:
                      const InputDecoration(isDense: true, hintText: 'Tag'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FilterChip(
                label: const Text('Blocked'),
                selected: _blocked,
                onSelected: (v) => setState(() => _blocked = v),
              ),
              FilterChip(
                label: const Text('Decision needed'),
                selected: _decision,
                onSelected: (v) => setState(() => _decision = v),
              ),
              FilterChip(
                label: const Text('Hide done'),
                selected: _hideDone,
                onSelected: (v) => setState(() => _hideDone = v),
              ),
              IconButton(
                tooltip: 'Scan again',
                onPressed: _rescan,
                icon: const Icon(Icons.refresh, size: 18),
              ),
              Text(
                _scanning
                    ? 'Scanning… ${rows.length} of ${_todos.length}'
                    : '${rows.length} of ${_todos.length} todos',
                key: const Key('tom-todo-aggregate-count'),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final t = row.todo;
              return ListTile(
                key: Key('tom-todo-aggregate-row-${t.id}'),
                dense: true,
                leading: TomTodoStatusIcon(status: t.status),
                title: Text(t.title.isEmpty ? (t.description ?? '') : t.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    t.id,
                    row.path,
                    if (t.priority != null) t.priority!.wire,
                    if (t.tags.isNotEmpty) t.tags.join(', '),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.source.openTodo(row.path, t.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _drop<T>(
    String any,
    T? value,
    List<T> values,
    String Function(T) label,
    ValueChanged<T?> onChanged,
  ) =>
      DropdownButton<T?>(
        value: value,
        hint: Text(any),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(any)),
          for (final v in values)
            DropdownMenuItem<T?>(value: v, child: Text(label(v))),
        ],
        onChanged: onChanged,
      );
}

/// A status as an icon, for lists where the row's checkbox does not fit.
class TomTodoStatusIcon extends StatelessWidget {
  const TomTodoStatusIcon({super.key, required this.status});

  final TomTodoStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      TomTodoStatus.notStarted => (Icons.radio_button_unchecked, null),
      TomTodoStatus.inProgress => (Icons.timelapse, scheme.primary),
      TomTodoStatus.blocked => (Icons.block, scheme.error),
      TomTodoStatus.decisionNeeded => (Icons.help_outline, scheme.tertiary),
      TomTodoStatus.waitingForRepeat => (Icons.event_repeat, scheme.secondary),
      TomTodoStatus.completed => (Icons.check_circle, scheme.primary),
      TomTodoStatus.cancelled => (Icons.cancel_outlined, scheme.outline),
      // A group of todos (its members in `comprised_of`), not work itself.
      TomTodoStatus.group => (Icons.account_tree_outlined, scheme.secondary),
    };
    return Tooltip(
      message: status.wire,
      child: Icon(icon, size: 18, color: color),
    );
  }
}
