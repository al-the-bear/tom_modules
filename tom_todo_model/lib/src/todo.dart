/// The todo shapes of the item model: the status and priority enums, the
/// workflow value types of the workspace todo schema (`todo.schema.json`) and
/// its decision rule.
///
/// The two enums are the single source for every todo-shaped thing: a status
/// or a priority is written with the wire names below and no others.
library;

import 'item.dart';
import 'todo_repeat.dart';

/// An item's status. Wire names match the workspace `todo.schema.json` enum
/// exactly, in both directions: the nine values here are the nine the schema
/// lists, which `_bin/check_todo_model.py` in the workspace holds.
///
/// Every item has a status. [none] is an item that is currently not treated
/// as a todo — a section, a note, an idea — and so stays out of the todo and
/// reminder handling; setting a todo status brings it in. It is neither open
/// work nor in the done group.
///
/// [group] is a todo group: not work itself, it lists its members in
/// [TomItem.comprisedOf]. The VS Code extension completes it once every member
/// is done and sets it back to `group` when a member is reopened; a
/// `<prefix>*` queue walk passes it. It is neither open work nor in the done
/// group ([TomItem.isDone] is false, [TomItem.isGroup] true).
///
/// [waitingForRepeat] is a repeated todo that was done and waits for its next
/// repetition ([TomItem.repeat], [TomItem.nextRepeat]); like [decisionNeeded]
/// it is an open status, not in the done group.
///
/// [decisionNeeded] is the workspace's: a todo with an open question the user
/// has to answer before work can start. It is an **open** status (not in the
/// done group) and, like [blocked], one the checkbox cannot express.
enum TomTodoStatus {
  notStarted('not-started'),
  inProgress('in-progress'),
  blocked('blocked'),
  decisionNeeded('decision-needed'),
  waitingForRepeat('waiting-for-repeat'),
  group('group'),
  none('none'),
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

/// The 3.x todo class: a todo is an item.
///
/// Every 3.x member is on [TomItem], the renamed ones deprecated with what
/// replaces them (`title` → `headline`, `references` → `links.external`, the
/// workflow fields → `workflow`).
@Deprecated('Use TomItem')
typedef TomTodo = TomItem;

/// The workspace schema's decision rule.
///
/// Applied to an edit, comparing [todo] (the edited value) with [previous]
/// (the value before it): when the edit opens a question on a todo that had
/// none open, the todo becomes `decision-needed`; when it answers or removes
/// the last open question of a `decision-needed` todo, the todo goes back to
/// `not-started`. A done todo, and an item with status `none` (not treated as
/// a todo), keeps its status, and a status the user chose
/// in an edit that did not change the open questions is left alone — setting
/// `decision-needed` by hand stays possible. Returns true when it changed the
/// status. The details editor applies it before a save, so the answer and the
/// status are one undo entry.
bool tomApplyDecisionRule(TomItem todo, {required TomItem previous}) {
  if (todo.isDone || todo.status == TomTodoStatus.none) return false;
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
    // The schema requires only `summary`: a decision recorded without its
    // question reads back as written.
    if (decisionNeeded.isNotEmpty) 'decision_needed': decisionNeeded,
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

/// One action of [TomTodoOnDone.action] (workspace schema `on_done.action`).
enum TomTodoOnDoneAction {
  /// When the todo is completed, set the [TomTodoOnDone.todos] free: a group
  /// todo to `group`, any other to `not-started` (`decision-needed` while it
  /// has an open decision), without looking at their other conditions.
  unblock('unblock'),

  /// Send the done notification to the quest and run in `filed_by` instead of
  /// the run that queued the todo.
  notify('notify');

  const TomTodoOnDoneAction(this.wire);

  final String wire;

  /// The actions 4.x knew and 5.0 retired (`queue`, `none`): read as nothing.
  static const Set<String> retiredWires = {'queue', 'none'};

  static TomTodoOnDoneAction fromWire(String value) => values.firstWhere(
    (a) => a.wire == value,
    orElse: () =>
        throw FormatException('Unknown todo on_done action: "$value"'),
  );
}

/// What happens when a todo is completed (workspace schema `on_done`). Every
/// part is optional.
class TomTodoOnDone {
  TomTodoOnDone({
    this.quest,
    this.run,
    List<String> todos = const [],
    List<TomTodoOnDoneAction> action = const [],
    this.instructions,
    this.notifyPrompt,
    this.reportTo,
  }) : todos = List.of(todos),
       action = List.of(action);

  /// The quest [instructions] are sent to; null: the todo's own quest.
  String? quest;

  /// The process run [instructions] are sent to; null: the run the todo is
  /// completed in (in another [quest]: its `default` run).
  String? run;

  /// The target todos (`unblock`): a bare id in the todo's own quest,
  /// `<quest>/<id>` in another.
  List<String> todos;

  /// The actions, in order.
  List<TomTodoOnDoneAction> action;

  /// Sent as a prompt to [quest] / [run] when the todo is completed.
  String? instructions;

  /// The done notification: sent to the run that queued the todo, with
  /// `notify` to the quest and run in `filed_by`.
  String? notifyPrompt;

  /// The document (`path#section`) the outcome is recorded in.
  String? reportTo;

  TomTodoOnDone copy() => TomTodoOnDone(
    quest: quest,
    run: run,
    todos: todos,
    action: action,
    instructions: instructions,
    notifyPrompt: notifyPrompt,
    reportTo: reportTo,
  );

  static const Set<String> fields = {
    'quest',
    'run',
    'todos',
    'action',
    'instructions',
    'notify_prompt',
    'report_to',
  };

  Map<String, Object?> toMap() => {
    if (quest != null) 'quest': quest,
    if (run != null) 'run': run,
    if (todos.isNotEmpty) 'todos': List.of(todos),
    if (action.isNotEmpty) 'action': [for (final a in action) a.wire],
    if (instructions != null) 'instructions': instructions,
    if (notifyPrompt != null) 'notify_prompt': notifyPrompt,
    if (reportTo != null) 'report_to': reportTo,
  };

  static TomTodoOnDone fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!fields.contains(key)) {
        throw FormatException('Unknown todo on_done field: "$key"');
      }
    }
    final action = map['action'];
    if (action != null && action is! List) {
      throw FormatException(
        'Todo "on_done.action" must be a list, not "$action"',
      );
    }
    return TomTodoOnDone(
      quest: map['quest']?.toString(),
      run: map['run']?.toString(),
      todos: [for (final t in (map['todos'] as List? ?? const [])) '$t'],
      action: [
        for (final a in (action as List? ?? const []))
          if (!TomTodoOnDoneAction.retiredWires.contains('$a'))
            TomTodoOnDoneAction.fromWire('$a'),
      ],
      instructions: map['instructions']?.toString(),
      notifyPrompt: map['notify_prompt']?.toString(),
      reportTo: map['report_to']?.toString(),
    );
  }
}

/// Who filed a todo (workspace schema `filed_by`). Every part is optional;
/// [at] is `yyyy-MM-ddTHH:MM` with `Z` or an offset, kept verbatim.
class TomTodoFiledBy {
  TomTodoFiledBy({this.quest, this.run, this.session, this.todo, this.at}) {
    check();
  }

  String? quest;
  String? run;
  String? session;
  String? todo;
  String? at;

  /// Rejects an [at] that is not `yyyy-MM-ddTHH:MM` with `Z` or an offset.
  void check() {
    if (at != null && !TomTodoRepeat.nextRepeatRe.hasMatch(at!)) {
      throw FormatException(
        'Todo "filed_by.at" must read yyyy-MM-ddTHH:MM with Z or an offset: "$at"',
      );
    }
  }

  TomTodoFiledBy copy() => TomTodoFiledBy(
    quest: quest,
    run: run,
    session: session,
    todo: todo,
    at: at,
  );

  static const Set<String> fields = {'quest', 'run', 'session', 'todo', 'at'};

  Map<String, Object?> toMap() => {
    if (quest != null) 'quest': quest,
    if (run != null) 'run': run,
    if (session != null) 'session': session,
    if (todo != null) 'todo': todo,
    if (at != null) 'at': at,
  };

  static TomTodoFiledBy fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!fields.contains(key)) {
        throw FormatException('Unknown todo filed_by field: "$key"');
      }
    }
    return TomTodoFiledBy(
      quest: map['quest']?.toString(),
      run: map['run']?.toString(),
      session: map['session']?.toString(),
      todo: map['todo']?.toString(),
      at: map['at']?.toString(),
    );
  }
}
