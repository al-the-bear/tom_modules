/// The shared todo model: the field set of the workspace todo schema
/// (`todo.schema.json`), used by every `*.todo.yaml` file, by Worktracker, and
/// by applications that keep todos inside their own documents.
///
/// The two enums are the single source for every todo-shaped thing: a status
/// or a priority is written with the wire names below and no others.
library;

/// Todo lifecycle state. Wire names match the workspace `todo.schema.json`
/// enum exactly, in both directions: the six values here are the six the
/// schema lists, which `_bin/check_todo_model.py` in the workspace holds.
///
/// [decisionNeeded] is the workspace's: a todo with an open question the user
/// has to answer before work can start. It is an **open** status (not in the
/// done group) and, like [blocked], one the checkbox cannot express.
enum TomTodoStatus {
  notStarted('not-started'),
  inProgress('in-progress'),
  blocked('blocked'),
  decisionNeeded('decision-needed'),
  completed('completed'),
  cancelled('cancelled');

  const TomTodoStatus(this.wire);

  final String wire;

  static TomTodoStatus fromWire(String value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => throw FormatException('Unknown todo status: "$value"'),
  );
}

/// Todo priority, ordered low → critical.
enum TomTodoPriority {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const TomTodoPriority(this.wire);

  final String wire;

  static TomTodoPriority fromWire(String value) => values.firstWhere(
    (p) => p.wire == value,
    orElse: () => throw FormatException('Unknown todo priority: "$value"'),
  );
}

/// One todo item.
///
/// [due] and the other dates are **date-only**. The two boundaries treat that
/// differently on purpose: [fromMap] — the *wire* boundary — rejects anything
/// that is not exactly `YYYY-MM-DD`, because a stored time of day means the
/// file is wrong and silently dropping it would hide that. The constructor —
/// the *API* boundary — truncates instead, because a Dart `DateTime` always
/// carries a time and callers such as an iCalendar import legitimately hand
/// one in for coercion.
///
/// [estimate] is a **verbatim ISO-8601 duration string** (`PT2H`, `P1D`). Its
/// form is validated but its value is never round-tripped through a Dart
/// `Duration`: `P1D` and `PT24H` denote the same span but are different
/// authored text, and the text is kept so a save is byte-stable.
///
/// The six orchestration fields — [executionRole], [qaRole],
/// [orchestrationRole], [bundleId], [derivedFrom], [feedbackSource] — are the
/// ones agent-driven execution groups and routes todos by.
class TomTodo {
  /// Stable todo id (becomes the iCalendar `UID` on export).
  final String id;

  String title;
  String? description;
  TomTodoStatus status;
  TomTodoPriority? priority;
  String? estimate;
  List<String> tags;

  /// Workspace-schema scope: where the todo applies.
  TomTodoScope? scope;

  /// Open and answered questions. An entry with no answer makes
  /// the todo `decision-needed` — see [tomApplyDecisionRule].
  List<TomTodoDecision> decisions;

  /// Documents and resources the todo points at.
  List<TomTodoReference> references;

  List<String> dependencies;

  /// Todos (or `<quest>/<todo>` pairs) that block this one.
  List<String> blockedBy;

  /// The reverse of [blockedBy]: the live todos whose `blocked_by` names this
  /// one — a bare id in the same quest, `<quest>/<todo>` from another. Derived:
  /// the VS Code extension's writers keep it in step after every write, and
  /// `validate_todo_corpus.py` reports a pair that does not match. A writer
  /// using this model that changes [blockedBy] leaves the other end to them.
  List<String> blocking;

  /// Publish conditions that block this one, each `<package> >= <x.y.z>`
  /// — the form `_bin/check_todo_blocks.py` reads.
  List<String> blockedUntil;

  /// Free-form context.
  String? notes;

  /// Who wrote the todo, and who completed it.
  String? author;
  String? completedBy;

  /// The role that carries the todo out, and the one that checks it.
  String? executionRole;
  String? qaRole;

  /// The role that orchestrates the bundle the todo belongs to.
  String? orchestrationRole;

  /// The execution bundle the todo is grouped into.
  String? bundleId;

  /// The todo this one was derived from, and the feedback that raised it.
  String? derivedFrom;
  String? feedbackSource;

  /// The todo is the user's to do (looking at something, answering, deciding
  /// by hand): an agent only prepares and reports, so a `<prefix>*` queue walk
  /// passes it by and lets the series go on. Stored as `user_action: true`;
  /// absent when false.
  bool userAction;

  DateTime? _due;
  DateTime? _created;
  DateTime? _updated;
  DateTime? _completedDate;
  DateTime? _archived;
  DateTime? _deleted;

  TomTodo({
    required this.id,
    required this.title,
    this.description,
    this.status = TomTodoStatus.notStarted,
    this.priority,
    DateTime? due,
    this.estimate,
    List<String> tags = const [],
    this.scope,
    List<TomTodoDecision> decisions = const [],
    List<TomTodoReference> references = const [],
    List<String> dependencies = const [],
    List<String> blockedBy = const [],
    List<String> blocking = const [],
    List<String> blockedUntil = const [],
    this.notes,
    DateTime? created,
    DateTime? updated,
    DateTime? completedDate,
    this.author,
    this.completedBy,
    DateTime? archived,
    DateTime? deleted,
    this.executionRole,
    this.qaRole,
    this.orchestrationRole,
    this.bundleId,
    this.derivedFrom,
    this.feedbackSource,
    this.userAction = false,
  }) : tags = List.of(tags),
       decisions = [for (final d in decisions) d.copy()],
       references = List.of(references),
       dependencies = List.of(dependencies),
       blockedBy = List.of(blockedBy),
       blocking = List.of(blocking),
       blockedUntil = List.of(blockedUntil),
       _due = _canonicalDue(due),
       _created = _canonicalDue(created),
       _updated = _canonicalDue(updated),
       _completedDate = _canonicalDue(completedDate),
       _archived = _canonicalDue(archived),
       _deleted = _canonicalDue(deleted) {
    if (estimate != null) _checkEstimate(estimate!);
    for (final condition in this.blockedUntil) {
      checkBlockedUntil(condition);
    }
  }

  /// Due date, always UTC midnight.
  DateTime? get due => _due;

  set due(DateTime? value) => _due = _canonicalDue(value);

  /// The workspace schema's dates, date-only like [due].
  DateTime? get created => _created;
  set created(DateTime? value) => _created = _canonicalDue(value);
  DateTime? get updated => _updated;
  set updated(DateTime? value) => _updated = _canonicalDue(value);
  DateTime? get completedDate => _completedDate;
  set completedDate(DateTime? value) => _completedDate = _canonicalDue(value);
  DateTime? get archived => _archived;
  set archived(DateTime? value) => _archived = _canonicalDue(value);
  DateTime? get deleted => _deleted;
  set deleted(DateTime? value) => _deleted = _canonicalDue(value);

  /// Records that this todo was written on [on] by [author].
  ///
  /// The one place a new todo gets its `created` date and its `author`, so
  /// every surface that makes one — a checklist row, the annotation panel,
  /// the todo-file editor, an import — writes the same two fields the same
  /// way. A null [author] (no identity is set) leaves `author` absent rather
  /// than writing a placeholder into a shared file.
  void recordCreation({required DateTime on, String? author}) {
    created = on;
    if (author != null) this.author = author;
  }

  /// Moves this todo to [next] on [on], keeping the completion facts true
  /// entering `completed` records `completed_date` and
  /// `completed_by` ([by], left absent when null); leaving `completed` clears
  /// both, since a reopened todo was not completed. `updated` is stamped.
  /// Moving to the status it already has changes nothing.
  void changeStatus(TomTodoStatus next, {required DateTime on, String? by}) {
    if (next == status) return;
    final wasCompleted = status == TomTodoStatus.completed;
    status = next;
    updated = on;
    if (next == TomTodoStatus.completed) {
      completedDate = on;
      completedBy = by;
    } else if (wasCompleted) {
      completedDate = null;
      completedBy = null;
    }
  }

  /// True for the **done group**: `completed` and `cancelled`.
  bool get isDone =>
      status == TomTodoStatus.completed || status == TomTodoStatus.cancelled;

  /// True while at least one decision has no answer.
  bool get hasOpenDecision => decisions.any((d) => d.isOpen);

  /// True when a blocker is recorded — a todo id or a publish condition.
  bool get hasBlocker => blockedBy.isNotEmpty || blockedUntil.isNotEmpty;

  /// A detached copy carrying the same id.
  ///
  /// Needed wherever a candidate value has to be evaluated or edited *without*
  /// touching the stored item: a planner tests "the item as it would be"
  /// before deciding, and a write-through has to keep the
  /// pre-write value intact to serve as the edit's inverse.
  TomTodo copy() => TomTodo(
    id: id,
    title: title,
    description: description,
    status: status,
    priority: priority,
    due: _due,
    estimate: estimate,
    tags: tags,
    scope: scope?.copy(),
    decisions: decisions,
    references: references,
    dependencies: dependencies,
    blockedBy: blockedBy,
    blocking: blocking,
    blockedUntil: blockedUntil,
    notes: notes,
    created: _created,
    updated: _updated,
    completedDate: _completedDate,
    author: author,
    completedBy: completedBy,
    archived: _archived,
    deleted: _deleted,
    executionRole: executionRole,
    qaRole: qaRole,
    orchestrationRole: orchestrationRole,
    bundleId: bundleId,
    derivedFrom: derivedFrom,
    feedbackSource: feedbackSource,
    userAction: userAction,
  );

  /// The calendar day [value] names, held as UTC midnight of that day.
  ///
  /// The day is read from the value's own fields: a local `DateTime` gives
  /// its local day, a UTC one its UTC day. Converting to UTC first moved a
  /// local value by a day wherever the machine is off UTC (00:30 local in
  /// Berlin became the previous day).
  static DateTime? _canonicalDue(DateTime? value) {
    if (value == null) return null;
    return DateTime.utc(value.year, value.month, value.day);
  }

  /// `yyyy-MM-dd` — the date-only form used in the YAML bodies: the calendar
  /// day [date] names, from its own fields (see [_canonicalDue]).
  static String encodeDate(DateTime date) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${p2(date.month)}-${p2(date.day)}';
  }

  static final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Parses a stored date field, rejecting anything that is not date-only.
  static DateTime decodeDate(Object value, {String field = 'due'}) {
    final text = value.toString();
    if (!_dateRe.hasMatch(text)) {
      throw FormatException(
        'Todo "$field" must be date-only "yyyy-MM-dd": "$text"',
      );
    }
    return DateTime.parse('${text}T00:00:00Z');
  }

  /// ISO-8601 durations, `P[nY][nM][nW][nD][T[nH][nM][nS]]`, requiring at
  /// least one component so bare `P` / `PT` are rejected.
  static final RegExp _durationRe = RegExp(
    r'^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?!$)(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?$',
  );

  /// Validates the **form** of an `estimate` without interpreting its value —
  /// the string is stored exactly as authored.
  static void _checkEstimate(String estimate) {
    if (!_durationRe.hasMatch(estimate)) {
      throw FormatException(
        'Todo "estimate" must be an ISO-8601 duration: "$estimate"',
      );
    }
  }

  /// `<package> >= <x.y.z>` or `<package> > <x.y.z>` — the form
  /// `_bin/check_todo_blocks.py` reads.
  static final RegExp _blockedUntilRe = RegExp(
    r'^[a-z][a-z0-9_]*\s*>=?\s*\d+\.\d+\.\d+$',
  );

  /// Validates one `blocked_until` condition.
  static void checkBlockedUntil(String condition) {
    if (!_blockedUntilRe.hasMatch(condition.trim())) {
      throw FormatException(
        'Todo "blocked_until" must read '
        '"<package> >= <x.y.z>": "$condition"',
      );
    }
  }

  /// Field order is the workspace schema's so every save path yields
  /// identical YAML, and a field is
  /// written only when it holds something.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    'status': status.wire,
    if (priority != null) 'priority': priority!.wire,
    if (_due != null) 'due': encodeDate(_due!),
    if (estimate != null) 'estimate': estimate,
    if (tags.isNotEmpty) 'tags': List.of(tags),
    if (scope != null && !scope!.isEmpty) 'scope': scope!.toMap(),
    if (decisions.isNotEmpty)
      'decisions': [for (final d in decisions) d.toMap()],
    if (references.isNotEmpty)
      'references': [for (final r in references) r.toMap()],
    if (dependencies.isNotEmpty) 'dependencies': List.of(dependencies),
    if (blockedBy.isNotEmpty) 'blocked_by': List.of(blockedBy),
    if (blocking.isNotEmpty) 'blocking': List.of(blocking),
    if (blockedUntil.isNotEmpty) 'blocked_until': List.of(blockedUntil),
    if (userAction) 'user_action': true,
    if (notes != null) 'notes': notes,
    if (_created != null) 'created': encodeDate(_created!),
    if (_updated != null) 'updated': encodeDate(_updated!),
    if (_completedDate != null) 'completed_date': encodeDate(_completedDate!),
    if (author != null) 'author': author,
    if (completedBy != null) 'completed_by': completedBy,
    if (_archived != null) 'archived': encodeDate(_archived!),
    if (_deleted != null) 'deleted': encodeDate(_deleted!),
    if (executionRole != null) 'execution_role': executionRole,
    if (qaRole != null) 'qa_role': qaRole,
    if (orchestrationRole != null) 'orchestration_role': orchestrationRole,
    if (bundleId != null) 'bundle_id': bundleId,
    if (derivedFrom != null) 'derived_from': derivedFrom,
    if (feedbackSource != null) 'feedback_source': feedbackSource,
  };

  /// The closed field set: exactly the workspace todo schema's properties
  /// (its `todo` definition forbids any other). The workspace script
  /// `_bin/check_todo_model.py` holds this set to the schema in both
  /// directions.
  static const Set<String> fields = {
    'id',
    'title',
    'description',
    'status',
    'priority',
    'due',
    'estimate',
    'tags',
    'scope',
    'decisions',
    'references',
    'dependencies',
    'blocked_by',
    'blocking',
    'blocked_until',
    'user_action',
    'notes',
    'created',
    'updated',
    'completed_date',
    'author',
    'completed_by',
    'archived',
    'deleted',
    'execution_role',
    'qa_role',
    'orchestration_role',
    'bundle_id',
    'derived_from',
    'feedback_source',
  };

  static List<String> _strings(Object? value) => [
    for (final v in (value as List? ?? const [])) v.toString(),
  ];

  static DateTime? _date(Map<dynamic, dynamic> map, String key) =>
      map[key] == null ? null : decodeDate(map[key] as Object, field: key);

  /// Parses a stored item. The unknown-field gate keeps the set the schema's:
  /// a key the schema does not name is a format error, not a field to guess
  /// at.
  static TomTodo fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!fields.contains(key)) {
        throw FormatException('Unknown todo field: "$key"');
      }
    }
    final id = map['id'];
    final title = map['title'];
    if (id is! String || title is! String) {
      throw FormatException('Invalid todo map (id/title): $map');
    }
    final status = map['status'];
    final priority = map['priority'];
    final scope = map['scope'];
    return TomTodo(
      id: id,
      title: title,
      description: map['description'] as String?,
      status: status == null
          ? TomTodoStatus.notStarted
          : TomTodoStatus.fromWire(status.toString()),
      priority: priority == null
          ? null
          : TomTodoPriority.fromWire(priority.toString()),
      due: _date(map, 'due'),
      estimate: map['estimate'] as String?,
      tags: _strings(map['tags']),
      scope: scope == null ? null : TomTodoScope.fromMap(scope as Map),
      decisions: [
        for (final d in (map['decisions'] as List? ?? const []))
          TomTodoDecision.fromMap(d as Map),
      ],
      references: [
        for (final r in (map['references'] as List? ?? const []))
          TomTodoReference.fromMap(r as Map),
      ],
      dependencies: _strings(map['dependencies']),
      blockedBy: _strings(map['blocked_by']),
      blocking: _strings(map['blocking']),
      blockedUntil: _strings(map['blocked_until']),
      notes: map['notes'] as String?,
      created: _date(map, 'created'),
      updated: _date(map, 'updated'),
      completedDate: _date(map, 'completed_date'),
      author: map['author'] as String?,
      completedBy: map['completed_by'] as String?,
      archived: _date(map, 'archived'),
      deleted: _date(map, 'deleted'),
      executionRole: map['execution_role'] as String?,
      qaRole: map['qa_role'] as String?,
      orchestrationRole: map['orchestration_role'] as String?,
      bundleId: map['bundle_id'] as String?,
      derivedFrom: map['derived_from'] as String?,
      feedbackSource: map['feedback_source'] as String?,
      userAction: _userAction(map['user_action']),
    );
  }

  /// `user_action` is a boolean; anything else is a format error, like an
  /// unknown key.
  static bool _userAction(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    throw FormatException('Todo "user_action" must be true or false, not "$value"');
  }

  /// Equal when the stored forms are equal — every field, in its wire form.
  @override
  bool operator ==(Object other) =>
      other is TomTodo && _deepEquals(other.toMap(), toMap());

  @override
  int get hashCode => Object.hash(id, title, status, _due);

  @override
  String toString() => 'TomTodo($id "$title" ${status.wire})';

  static bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// The workspace schema's decision rule.
///
/// Applied to an edit, comparing [todo] (the edited value) with [previous]
/// (the value before it): when the edit opens a question on a todo that had
/// none open, the todo becomes `decision-needed`; when it answers or removes
/// the last open question of a `decision-needed` todo, the todo goes back to
/// `not-started`. A done todo keeps its status, and a status the user chose
/// in an edit that did not change the open questions is left alone — setting
/// `decision-needed` by hand stays possible. Returns true when it changed the
/// status. The details editor applies it before a save, so the answer and the
/// status are one undo entry.
bool tomApplyDecisionRule(TomTodo todo, {required TomTodo previous}) {
  if (todo.isDone) return false;
  final wasOpen = previous.hasOpenDecision;
  final isOpen = todo.hasOpenDecision;
  if (isOpen && !wasOpen && todo.status != TomTodoStatus.decisionNeeded) {
    todo.status = TomTodoStatus.decisionNeeded;
    return true;
  }
  if (!isOpen && wasOpen && todo.status == TomTodoStatus.decisionNeeded) {
    todo.status = TomTodoStatus.notStarted;
    return true;
  }
  return false;
}

/// One open or answered question on a todo (workspace schema `decisions`).
class TomTodoDecision {
  TomTodoDecision({
    required this.summary,
    required this.decisionNeeded,
    this.decision,
  });

  /// One line naming what has to be decided.
  String summary;

  /// The full question, its context and the options.
  String decisionNeeded;

  /// The answer, or null while the question is open.
  String? decision;

  bool get isOpen => decision == null || decision!.trim().isEmpty;

  TomTodoDecision copy() => TomTodoDecision(
    summary: summary,
    decisionNeeded: decisionNeeded,
    decision: decision,
  );

  Map<String, Object?> toMap() => {
    'summary': summary,
    'decision_needed': decisionNeeded,
    if (decision != null && decision!.trim().isNotEmpty) 'decision': decision,
  };

  static TomTodoDecision fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!const {'summary', 'decision_needed', 'decision'}.contains(key)) {
        throw FormatException('Unknown todo decision field: "$key"');
      }
    }
    return TomTodoDecision(
      summary: (map['summary'] ?? '').toString(),
      decisionNeeded: (map['decision_needed'] ?? '').toString(),
      decision: map['decision']?.toString(),
    );
  }
}

/// Where a todo applies (workspace schema `scope`).
class TomTodoScope {
  TomTodoScope({
    this.project,
    List<String> projects = const [],
    this.module,
    this.area,
    List<String> files = const [],
    this.path,
  }) : projects = List.of(projects),
       files = List.of(files);

  String? project;
  List<String> projects;
  String? module;
  String? area;
  List<String> files;
  String? path;

  bool get isEmpty =>
      project == null &&
      projects.isEmpty &&
      module == null &&
      area == null &&
      files.isEmpty &&
      path == null;

  TomTodoScope copy() => TomTodoScope(
    project: project,
    projects: projects,
    module: module,
    area: area,
    files: files,
    path: path,
  );

  Map<String, Object?> toMap() => {
    if (project != null) 'project': project,
    if (projects.isNotEmpty) 'projects': List.of(projects),
    if (module != null) 'module': module,
    if (area != null) 'area': area,
    if (files.isNotEmpty) 'files': List.of(files),
    if (path != null) 'path': path,
  };

  static TomTodoScope fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!const {
        'project',
        'projects',
        'module',
        'area',
        'files',
        'path',
      }.contains(key)) {
        throw FormatException('Unknown todo scope field: "$key"');
      }
    }
    return TomTodoScope(
      project: map['project']?.toString(),
      projects: [for (final p in (map['projects'] as List? ?? const [])) '$p'],
      module: map['module']?.toString(),
      area: map['area']?.toString(),
      files: [for (final f in (map['files'] as List? ?? const [])) '$f'],
      path: map['path']?.toString(),
    );
  }
}

/// A document or resource a todo points at (workspace schema `references`):
/// a workspace file, a URL, or a note — at least one of the three.
class TomTodoReference {
  const TomTodoReference({
    this.type,
    this.path,
    this.url,
    this.description,
    this.lines,
  });

  final String? type;
  final String? path;
  final String? url;
  final String? description;
  final String? lines;

  Map<String, Object?> toMap() => {
    if (type != null) 'type': type,
    if (path != null) 'path': path,
    if (url != null) 'url': url,
    if (description != null) 'description': description,
    if (lines != null) 'lines': lines,
  };

  static TomTodoReference fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!const {
        'type',
        'path',
        'url',
        'description',
        'lines',
      }.contains(key)) {
        throw FormatException('Unknown todo reference field: "$key"');
      }
    }
    final reference = TomTodoReference(
      type: map['type']?.toString(),
      path: map['path']?.toString(),
      url: map['url']?.toString(),
      description: map['description']?.toString(),
      lines: map['lines']?.toString(),
    );
    if (reference.path == null &&
        reference.url == null &&
        reference.description == null) {
      throw const FormatException(
        'A todo reference needs a path, a url or a description',
      );
    }
    return reference;
  }

  @override
  bool operator ==(Object other) =>
      other is TomTodoReference &&
      other.type == type &&
      other.path == path &&
      other.url == url &&
      other.description == description &&
      other.lines == lines;

  @override
  int get hashCode => Object.hash(type, path, url, description, lines);
}
