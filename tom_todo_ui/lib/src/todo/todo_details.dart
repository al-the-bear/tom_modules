/// The todo details editor: every field of a todo in one place.
///
/// The row stays a line — checkbox, title, badges — and this dialog is where a
/// todo's facets are edited: whose it is, status, priority, due date,
/// estimate, tags, the description, the dependencies, blockers, decisions,
/// scope and references. What other todos it blocks and the last queue run's
/// answer are shown, never edited: the first is derived, the second written
/// by the run.
/// It is one surface for every host: each opens it and writes what it returns
/// through its own one write path, so a todo is edited the same way wherever
/// it is shown.
///
/// The dialog edits a **copy** and returns it; it never writes. Cancel returns
/// null and changes nothing.
library;

import 'package:flutter/material.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

import 'package:tom_file_editors/tom_file_editors.dart';

/// A todo the dependency picker can offer: its id, its title, and where it
/// lives, so two todos with the same title can be told apart.
class TomTodoCandidate {
  const TomTodoCandidate({
    required this.id,
    required this.title,
    required this.where,
  });

  final String id;
  final String title;
  final String where;
}

/// Copies every editable field of [from] onto [to] — the one place that knows
/// what "the details" are, so the three hosts cannot apply a different subset.
void tomCopyTodoDetails(TomTodo from, TomTodo to) {
  final copy = from.copy();
  to
    ..title = copy.title
    ..description = copy.description
    ..userAction = copy.userAction
    ..status = copy.status
    ..priority = copy.priority
    ..due = copy.due
    ..estimate = copy.estimate
    ..tags = copy.tags
    ..scope = copy.scope
    ..decisions = copy.decisions
    ..references = copy.references
    ..dependencies = copy.dependencies
    ..blockedBy = copy.blockedBy
    ..blockedUntil = copy.blockedUntil
    ..notes = copy.notes
    ..created = copy.created
    ..updated = copy.updated
    ..completedDate = copy.completedDate
    ..author = copy.author
    ..completedBy = copy.completedBy
    ..archived = copy.archived
    ..deleted = copy.deleted;
}

/// One decision's three fields in the editor.
class _DecisionFields {
  _DecisionFields(TomTodoDecision d)
      : summary = TextEditingController(text: d.summary),
        question = TextEditingController(text: d.decisionNeeded),
        answer = TextEditingController(text: d.decision ?? '');

  final TextEditingController summary;
  final TextEditingController question;
  final TextEditingController answer;

  TomTodoDecision toDecision() => TomTodoDecision(
        summary: summary.text.trim(),
        decisionNeeded: question.text.trim(),
        decision: answer.text.trim().isEmpty ? null : answer.text.trim(),
      );

  void dispose() {
    summary.dispose();
    question.dispose();
    answer.dispose();
  }
}

/// One reference's fields in the editor.
class _ReferenceFields {
  _ReferenceFields(TomTodoReference r)
      : path = TextEditingController(text: r.path ?? ''),
        url = TextEditingController(text: r.url ?? ''),
        description = TextEditingController(text: r.description ?? ''),
        type = TextEditingController(text: r.type ?? ''),
        lines = TextEditingController(text: r.lines ?? '');

  final TextEditingController path;
  final TextEditingController url;
  final TextEditingController description;
  final TextEditingController type;
  final TextEditingController lines;

  static String? _value(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Null when the row is empty; a reference needs a path, a URL or a
  /// description (the schema's rule).
  TomTodoReference? toReference() {
    final reference = TomTodoReference(
      path: _value(path),
      url: _value(url),
      description: _value(description),
      type: _value(type),
      lines: _value(lines),
    );
    return reference.path == null &&
            reference.url == null &&
            reference.description == null
        ? null
        : reference;
  }

  bool get isBlank => [path, url, description, type, lines]
      .every((c) => c.text.trim().isEmpty);

  void dispose() {
    for (final c in [path, url, description, type, lines]) {
      c.dispose();
    }
  }
}

/// Opens the details editor for [todo] and returns the edited copy, or null
/// when the user cancelled.
///
/// [candidates] are the todos a dependency may name; [todo] itself is never
/// offered. A dependency naming a todo that is not among them is kept and
/// shown as missing rather than dropped.
///
/// [author] is the identity the edit is made as (`TomIdentity.
/// attributionOf`): a status moved to `completed` here records it as
/// `completed_by`, null when no identity is set.
Future<TomTodo?> showTomTodoDetails(
  BuildContext context, {
  required TomTodo todo,
  required List<TomTodoCandidate> candidates,
  String? author,
}) =>
    showDialog<TomTodo>(
      context: context,
      builder: (context) {
        final editor = _TodoDetailsEditor(
          todo: todo,
          candidates: candidates,
          author: author,
        );
        // A phone gets the whole screen: a form this long in a centred dialog
        // leaves a strip of fields between two margins.
        return MediaQuery.sizeOf(context).width < 600
            ? Dialog.fullscreen(child: editor)
            : Dialog(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 640, maxHeight: 720),
                  child: editor,
                ),
              );
      },
    );

class _TodoDetailsEditor extends StatefulWidget {
  const _TodoDetailsEditor({
    required this.todo,
    required this.candidates,
    required this.author,
  });

  final TomTodo todo;
  final List<TomTodoCandidate> candidates;
  final String? author;

  @override
  State<_TodoDetailsEditor> createState() => _TodoDetailsEditorState();
}

class _TodoDetailsEditorState extends State<_TodoDetailsEditor> {
  late final TomTodo _draft = widget.todo.copy();
  late final TextEditingController _title =
      TextEditingController(text: _draft.title);
  late final TextEditingController _description =
      TextEditingController(text: _draft.description ?? '');
  late final TextEditingController _estimate =
      TextEditingController(text: _draft.estimate ?? '');
  final TextEditingController _tag = TextEditingController();
  late final TextEditingController _notes =
      TextEditingController(text: _draft.notes ?? '');
  late final TextEditingController _blockedUntil =
      TextEditingController(text: _draft.blockedUntil.join('\n'));
  late final TextEditingController _scopeProject =
      TextEditingController(text: _draft.scope?.project ?? '');
  late final TextEditingController _scopeProjects =
      TextEditingController(text: (_draft.scope?.projects ?? []).join(', '));
  late final TextEditingController _scopeModule =
      TextEditingController(text: _draft.scope?.module ?? '');
  late final TextEditingController _scopeArea =
      TextEditingController(text: _draft.scope?.area ?? '');
  late final TextEditingController _scopePath =
      TextEditingController(text: _draft.scope?.path ?? '');
  late final TextEditingController _scopeFiles =
      TextEditingController(text: (_draft.scope?.files ?? []).join('\n'));
  late final List<_DecisionFields> _decisions = [
    for (final d in _draft.decisions) _DecisionFields(d),
  ];
  late final List<_ReferenceFields> _references = [
    for (final r in _draft.references) _ReferenceFields(r),
  ];
  String? _estimateError;
  String? _blockedUntilError;

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _estimate,
      _tag,
      _notes,
      _blockedUntil,
      _scopeProject,
      _scopeProjects,
      _scopeModule,
      _scopeArea,
      _scopePath,
      _scopeFiles,
    ]) {
      c.dispose();
    }
    for (final d in _decisions) {
      d.dispose();
    }
    for (final r in _references) {
      r.dispose();
    }
    super.dispose();
  }

  static List<String> _lines(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  /// The `blocked_until` lines, validated as the model validates them.
  String? _checkBlockedUntil(String text) {
    for (final line in _lines(text)) {
      try {
        TomTodo.checkBlockedUntil(line);
      } on FormatException {
        return '"$line" — one condition per line, like '
            '"tom_basics >= 1.2.0"';
      }
    }
    return null;
  }

  /// The estimate as the model would store it, or the reason it would not.
  ///
  /// Validated by the model's own constructor rather than a pattern of this
  /// dialog's, so the dialog cannot accept a value the codec would refuse.
  String? _checkEstimate(String text) {
    if (text.trim().isEmpty) return null;
    try {
      TomTodo(id: 'check', title: 'check', estimate: text.trim());
      return null;
    } on Object {
      return 'An ISO-8601 duration, such as PT2H, PT30M or P1D';
    }
  }

  bool get _canSave =>
      _title.text.trim().isNotEmpty &&
      _estimateError == null &&
      _blockedUntilError == null &&
      _decisions.every((d) => d.summary.text.trim().isNotEmpty) &&
      _references.every((r) => r.isBlank || r.toReference() != null);

  void _addTag() {
    final tag = _tag.text.trim().replaceFirst(RegExp('^#'), '');
    if (tag.isEmpty) return;
    setState(() {
      if (!_draft.tags.contains(tag)) _draft.tags.add(tag);
      _tag.clear();
    });
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    final scope = TomTodoScope(
      project: _text(_scopeProject),
      projects: [
        for (final p in _scopeProjects.text.split(','))
          if (p.trim().isNotEmpty) p.trim(),
      ],
      module: _text(_scopeModule),
      area: _text(_scopeArea),
      path: _text(_scopePath),
      files: _lines(_scopeFiles.text),
    );
    _draft
      ..title = _title.text.trim()
      ..description =
          _description.text.trim().isEmpty ? null : _description.text
      ..estimate = _estimate.text.trim().isEmpty ? null : _estimate.text.trim()
      ..notes = _notes.text.trim().isEmpty ? null : _notes.text
      ..blockedUntil = _lines(_blockedUntil.text)
      ..scope = scope.isEmpty ? null : scope
      ..decisions = [for (final d in _decisions) d.toDecision()]
      ..references = [
        for (final r in _references) ?r.toReference(),
      ];
    // The schema's decision rule, applied in the same edit: an open question
    // makes the todo decision-needed, answering the last one moves it back to
    // not-started — so the answer and the status are one undo entry.
    tomApplyDecisionRule(_draft, previous: widget.todo);
    // The status the form ended on, applied as one change from the stored
    // one, so completing records the date and the completer and reopening
    // clears them — the same rule as the checkbox.
    final today = DateTime.now();
    final next = _draft.status;
    _draft
      ..status = widget.todo.status
      ..changeStatus(next, on: today, by: widget.author)
      ..updated = today;
    Navigator.of(context).pop(_draft);
  }

  TomTodoCandidate? _candidate(String id) {
    for (final c in widget.candidates) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.due ?? DateTime.now(),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked != null && mounted) setState(() => _draft.due = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offered = [
      for (final c in widget.candidates)
        if (c.id != _draft.id && !_draft.dependencies.contains(c.id)) c,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text('Todo details', style: theme.textTheme.titleLarge),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('tom-todo-details-title'),
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownMenu<TomTodoStatus>(
                      key: const Key('tom-todo-details-status'),
                      label: const Text('Status'),
                      initialSelection: _draft.status,
                      onSelected: (s) {
                        if (s != null) setState(() => _draft.status = s);
                      },
                      dropdownMenuEntries: [
                        for (final s in TomTodoStatus.values)
                          DropdownMenuEntry(value: s, label: s.wire),
                      ],
                    ),
                    DropdownMenu<TomTodoPriority?>(
                      key: const Key('tom-todo-details-priority'),
                      label: const Text('Priority'),
                      initialSelection: _draft.priority,
                      onSelected: (p) => setState(() => _draft.priority = p),
                      dropdownMenuEntries: [
                        const DropdownMenuEntry(value: null, label: 'none'),
                        for (final p in TomTodoPriority.values)
                          DropdownMenuEntry(value: p, label: p.wire),
                      ],
                    ),
                    InputChip(
                      key: const Key('tom-todo-details-due'),
                      avatar: const Icon(Icons.event, size: 18),
                      label: Text(_draft.due == null
                          ? 'No due date'
                          : 'Due ${TomTodo.encodeDate(_draft.due!)}'),
                      onPressed: _pickDue,
                      onDeleted: _draft.due == null
                          ? null
                          : () => setState(() => _draft.due = null),
                      deleteButtonTooltipMessage: 'Clear due date',
                    ),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        key: const Key('tom-todo-details-estimate'),
                        controller: _estimate,
                        decoration: InputDecoration(
                          labelText: 'Estimate',
                          hintText: 'PT2H',
                          errorText: _estimateError,
                          errorMaxLines: 2,
                        ),
                        onChanged: (text) => setState(
                          () => _estimateError = _checkEstimate(text),
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('tom-todo-details-user-action'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('👤 Yours to do'),
                  subtitle: const Text(
                    'An agent only prepares and reports; a queue walk passes '
                    'it by',
                  ),
                  value: _draft.userAction,
                  onChanged: (v) => setState(() => _draft.userAction = v),
                ),
                const SizedBox(height: 8),
                Text('Tags', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tag in _draft.tags)
                      InputChip(
                        key: Key('tom-todo-details-tag-$tag'),
                        label: Text('#$tag'),
                        onDeleted: () =>
                            setState(() => _draft.tags.remove(tag)),
                      ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        key: const Key('tom-todo-details-tag-input'),
                        controller: _tag,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Add tag',
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('tom-todo-details-description'),
                  controller: _description,
                  minLines: 4,
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Depends on', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final id in _draft.dependencies)
                      InputChip(
                        key: Key('tom-todo-details-dependency-$id'),
                        avatar: Icon(
                          _candidate(id) == null
                              ? Icons.link_off
                              : Icons.link,
                          size: 18,
                        ),
                        // A target that cannot be found is named, not dropped:
                        // it may be in a document that is not open, or come
                        // back with an undo.
                        label: Text(_candidate(id)?.title ?? 'Missing: $id'),
                        tooltip: _candidate(id)?.where,
                        onDeleted: () =>
                            setState(() => _draft.dependencies.remove(id)),
                      ),
                    if (offered.isNotEmpty)
                      PopupMenuButton<String>(
                        key: const Key('tom-todo-details-add-dependency'),
                        tooltip: 'Add a dependency',
                        onSelected: (id) =>
                            setState(() => _draft.dependencies.add(id)),
                        itemBuilder: (context) => [
                          for (final c in offered)
                            PopupMenuItem(
                              value: c.id,
                              child: Text('${c.title} — ${c.where}'),
                            ),
                        ],
                        child: const Chip(
                          avatar: Icon(Icons.add, size: 18),
                          label: Text('Add dependency'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._blockerFields(theme),
                if (_draft.blocking.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ..._blockingList(theme),
                ],
                const SizedBox(height: 16),
                ..._decisionFields(theme),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('tom-todo-details-notes'),
                  controller: _notes,
                  minLines: 2,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_draft.lastAnswer case final answer?
                    when answer.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _lastAnswer(theme, answer),
                ],
                const SizedBox(height: 8),
                _scopeTile(),
                _referencesTile(),
                _record(theme),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('tom-todo-details-save'),
                onPressed: _canSave ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _blockerFields(ThemeData theme) {
    final offered = [
      for (final c in widget.candidates)
        if (c.id != _draft.id && !_draft.blockedBy.contains(c.id)) c,
    ];
    return [
      Text('Blocked by', style: theme.textTheme.labelLarge),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in _draft.blockedBy)
            InputChip(
              key: Key('tom-todo-details-blocker-$id'),
              avatar: const Icon(Icons.block, size: 18),
              label: Text(_candidate(id)?.title ?? id),
              tooltip: _candidate(id)?.where,
              onDeleted: () => setState(() => _draft.blockedBy.remove(id)),
            ),
          if (offered.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('tom-todo-details-add-blocker'),
              tooltip: 'Add a blocking todo',
              onSelected: (id) => setState(() => _draft.blockedBy.add(id)),
              itemBuilder: (context) => [
                for (final c in offered)
                  PopupMenuItem(
                    value: c.id,
                    child: Text('${c.title} — ${c.where}'),
                  ),
              ],
              child: const Chip(
                avatar: Icon(Icons.add, size: 18),
                label: Text('Add blocker'),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('tom-todo-details-blocked-until'),
        controller: _blockedUntil,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: 'Blocked until a release',
          hintText: 'tom_basics >= 1.2.0',
          helperText: 'One condition per line',
          errorText: _blockedUntilError,
          errorMaxLines: 2,
        ),
        onChanged: (text) =>
            setState(() => _blockedUntilError = _checkBlockedUntil(text)),
      ),
    ];
  }

  /// The todos whose `blocked_by` names this one: derived, kept in step by
  /// the todo writers, so shown here and never edited. A todo the candidates
  /// know is named by its title, one in another quest by its reference.
  List<Widget> _blockingList(ThemeData theme) => [
        Text('Blocks', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in _draft.blocking)
              Chip(
                key: Key('tom-todo-details-blocks-$id'),
                avatar: const Text('⛓️'),
                label: Text(_candidate(id)?.title ?? id),
              ),
          ],
        ),
      ];

  /// The final answer of the queue run that executed the todo (Markdown),
  /// written by the run and replaced by the next one.
  Widget _lastAnswer(ThemeData theme, String answer) => Container(
        key: const Key('tom-todo-details-last-answer'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Answer', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectionArea(
              child: TomMarkdownBody(markdown: answer, compact: true),
            ),
          ],
        ),
      );

  List<Widget> _decisionFields(ThemeData theme) => [
        Row(
          children: [
            Expanded(
              child: Text(
                'Decisions',
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              key: const Key('tom-todo-details-add-decision'),
              onPressed: () => setState(() => _decisions.add(
                    _DecisionFields(TomTodoDecision(
                      summary: '',
                      decisionNeeded: '',
                    )),
                  )),
              icon: const Icon(Icons.add),
              label: const Text('Add decision'),
            ),
          ],
        ),
        for (final (i, d) in _decisions.indexed)
          Card(
            key: Key('tom-todo-details-decision-$i'),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: Key('tom-todo-details-decision-$i-summary'),
                          controller: d.summary,
                          decoration: const InputDecoration(
                            labelText: 'What has to be decided',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove decision',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _decisions.removeAt(i).dispose();
                        }),
                      ),
                    ],
                  ),
                  TextField(
                    key: Key('tom-todo-details-decision-$i-question'),
                    controller: d.question,
                    minLines: 1,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'The question, its context and the options',
                    ),
                  ),
                  TextField(
                    key: Key('tom-todo-details-decision-$i-answer'),
                    controller: d.answer,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Decision (empty while open)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),
      ];

  Widget _scopeTile() {
    Widget field(String label, TextEditingController c, {int lines = 1}) =>
        TextField(
          controller: c,
          minLines: 1,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
        );
    return ExpansionTile(
      key: const Key('tom-todo-details-scope'),
      title: const Text('Scope'),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: !(_draft.scope?.isEmpty ?? true),
      children: [
        field('Project', _scopeProject),
        field('Projects (comma-separated)', _scopeProjects),
        field('Module', _scopeModule),
        field('Area', _scopeArea),
        field('Path', _scopePath),
        field('Files (one per line)', _scopeFiles, lines: 6),
      ],
    );
  }

  Widget _referencesTile() => ExpansionTile(
        key: const Key('tom-todo-details-references'),
        title: Text('References (${_references.length})'),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: _references.isNotEmpty,
        children: [
          for (final (i, r) in _references.indexed)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: Key('tom-todo-details-reference-$i-path'),
                            controller: r.path,
                            decoration: const InputDecoration(
                              labelText: 'Path',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove reference',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _references.removeAt(i).dispose();
                          }),
                        ),
                      ],
                    ),
                    TextField(
                      controller: r.url,
                      decoration: const InputDecoration(labelText: 'URL'),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: r.description,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                      onChanged: (_) => setState(() {}),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: r.type,
                            decoration:
                                const InputDecoration(labelText: 'Type'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: r.lines,
                            decoration:
                                const InputDecoration(labelText: 'Lines'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('tom-todo-details-add-reference'),
              onPressed: () => setState(() => _references
                  .add(_ReferenceFields(const TomTodoReference()))),
              icon: const Icon(Icons.add),
              label: const Text('Add reference'),
            ),
          ),
        ],
      );

  /// Who and when — set by whoever wrote the todo, shown and never edited
  /// here. A save stamps `updated`, and `completed_date` when this save
  /// completes it.
  Widget _record(ThemeData theme) {
    String date(DateTime? d) => d == null ? '—' : TomTodo.encodeDate(d);
    final rows = <(String, String)>[
      ('Author', _draft.author ?? '—'),
      ('Created', date(_draft.created)),
      ('Updated', date(_draft.updated)),
      ('Completed', date(_draft.completedDate)),
      ('Completed by', _draft.completedBy ?? '—'),
    ];
    return Padding(
      key: const Key('tom-todo-details-record'),
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final (label, value) in rows)
            Text('$label: $value', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
