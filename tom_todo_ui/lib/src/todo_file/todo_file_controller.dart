/// the todo-file editor's logic, apart from its widgets.
///
/// One controller per open todo file, over the file's [ForgeFileSession].
/// It reads the session's text into a [TomTodoFile], validates it, and
/// turns each gesture — a status, a title, the details, an added todo, a
/// move, a header key, an archive — into one text edit with one label, which
/// is one entry in the file's history.
library;

import 'package:tom_basics/utilities.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

import 'todo_relocation.dart';
import 'todo_validation.dart';

/// The todo-file editor's state over one session.
class TomTodoFileController extends ChangeNotifier {
  TomTodoFileController({
    required this.session,
    required this.absolutePath,
    required this.validator,
    required this.relocator,
    DateTime Function()? clock,
    String? Function()? author,
  })  : clock = clock ?? DateTime.now,
        author = author ?? _noAuthor {
    session.addListener(_onSession);
    _onSession();
  }

  final ForgeFileSession session;

  /// The file's absolute path: where its schema is resolved from.
  final String absolutePath;
  final TomTodoFileValidator validator;
  final TomTodoRelocator relocator;
  final DateTime Function() clock;

  /// Who edits made here are made as — the host.s author, or
  /// null when none is set. Read per edit, so a changed identity applies to
  /// the next one. A todo added here records it as `author`, one completed
  /// here as `completed_by`.
  final String? Function() author;

  static String? _noAuthor() => null;

  String? _parsedText;
  TomTodoFile? _file;
  String? _parseError;
  TomTodoFileValidation? _validation;
  String? _validatedText;

  /// The file as last parsed, or null when it is not a todo file
  /// ([parseError] says why).
  TomTodoFile? get file => _file;
  String? get parseError => _parseError;

  /// The validation of the current text, or null while it runs.
  TomTodoFileValidation? get validation =>
      _validatedText == session.text ? _validation : null;

  /// The file's name.
  String get fileName => p.posix.basename(session.path);

  bool get editable => session.readOnlyReason == null && _file != null;

  void _onSession() {
    if (session.state != ForgeFileSessionState.ready) return;
    final text = session.text;
    if (text == _parsedText) return;
    _parsedText = text;
    try {
      _file = TomTodoFile.parse(text);
      _parseError = null;
    } on TomTodoFileFormatException catch (e) {
      _file = null;
      _parseError = e.message;
    }
    notifyListeners();
    unawaited(_validate(text));
  }

  Future<void> _validate(String text) async {
    final file = _file;
    if (file == null) return;
    final result = await validator.validate(file, absolutePath);
    if (_disposed || session.text != text) return;
    _validation = result;
    _validatedText = text;
    notifyListeners();
  }

  /// Validates now and answers the result — what a save consults.
  Future<TomTodoFileValidation?> validateNow() async {
    final file = _file;
    if (file == null) return null;
    final text = session.text;
    await _validate(text);
    return validation;
  }

  /// The date-only today, local.
  DateTime get today {
    final now = clock();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Writes [edited] over todo [index] as one history entry. The todo's
  /// `updated` date is stamped when anything else changed.
  void write(int index, TomItem edited, String label) {
    final file = _file!;
    final before = file.entries[index].item!;
    if (before == edited) return;
    final stamped = edited.copy()..updated = today;
    session.edit(file.withItem(index, stamped), label);
  }

  /// Checks or unchecks todo [index].
  /// Completing records the date and [author] as the completer; reopening
  /// clears both.
  void toggleDone(int index) {
    final todo = _file!.entries[index].item!.copy()
      ..changeStatus(
        _file!.entries[index].item!.isDone
            ? TomTodoStatus.notStarted
            : TomTodoStatus.completed,
        on: today,
        by: author(),
      );
    write(index, todo, 'Set status of `${todo.id}` to ${todo.status.wire}');
  }

  /// Retitles todo [index].
  void retitle(int index, String title) {
    final todo = _file!.entries[index].item!.copy()..headline = title.trim();
    write(index, todo, 'Retitle `${todo.id}`');
  }

  /// Appends [todo]. Its id must be new to the file.
  void add(TomItem todo) {
    final file = _file!;
    if (file.entryFor(todo.id) != null) {
      throw StateError('The id "${todo.id}" is already in this file.');
    }
    // Created today by [author] unless the todo says otherwise — a pasted or
    // moved todo keeps the facts it came with.
    final created = todo.copy()
      ..recordCreation(
        on: todo.created ?? today,
        author: todo.author ?? author(),
      );
    session.edit(file.withInserted(created), 'Add `${todo.id}`');
  }

  /// Inserts [todos] after the todo [after] (the end when null or absent),
  /// as one history entry labelled [label] — a paste or a drop.
  /// Their ids must be new to the file.
  void insertMany(List<TomItem> todos, String label, {String? after}) {
    var file = _file!;
    for (final todo in todos) {
      if (file.entryFor(todo.id) != null) {
        throw StateError('The id "${todo.id}" is already in this file.');
      }
    }
    var at = after == null ? null : file.entryFor(after)?.index;
    var text = file.text;
    for (final todo in todos) {
      text = file.withInserted(todo, at: at == null ? null : at + 1);
      file = TomTodoFile.parse(text);
      if (at != null) at++;
    }
    session.edit(text, label);
  }

  /// Removes the todos [ids] as one history entry labelled [label] — a cut,
  /// or a move's source side.
  void removeMany(Set<String> ids, String label) {
    var file = _file!;
    final indices = [
      for (final e in file.entries)
        if (ids.contains(e.id)) e.index,
    ]..sort((a, b) => b.compareTo(a));
    if (indices.isEmpty) return;
    var text = file.text;
    for (final i in indices) {
      text = file.withoutTodo(i);
      file = TomTodoFile.parse(text);
    }
    session.edit(text, label);
  }

  /// Moves todo [from] to position [to].
  void move(int from, int to) {
    final file = _file!;
    if (from == to) return;
    session.edit(file.withMoved(from, to),
        'Move `${file.entries[from].id}`');
  }

  /// Sets or clears a file-level key.
  void setFileKey(String key, Object? value) {
    final file = _file!;
    final text = file.withFileKey(key, value);
    if (text == session.text) return;
    session.edit(text, value == null ? 'Clear $key' : 'Set $key');
  }

  /// Why todo [index] cannot be relocated by [kind], or null.
  String? relocationRefusal(int index, TomTodoRelocationKind kind) =>
      TomTodoRelocator.refusal(_file!, fileName, index, kind);

  /// Archives or deletes todo [index]. The session must be clean.
  Future<void> relocate(int index, TomTodoRelocationKind kind) =>
      relocator.relocate(session, index, kind);

  /// The ids in every todo file of this file's folder — for the stem-reuse
  /// warning and the next base.
  Future<Set<String>> folderIds() async {
    final dir = p.posix.dirname(session.path);
    final fs = session.fileSystem;
    final listing = await fs.list(fs.uriOf(dir == '.' ? '' : dir));
    final ids = <String>{...?_file?.entries.map((e) => e.id)};
    for (final entry in listing) {
      if (entry.isDirectory || !entry.name.endsWith('.todo.yaml')) continue;
      if (entry.path == session.path) continue;
      try {
        final content = await fs.read(entry.uri);
        final file =
            TomTodoFile.parse(tomDecodeTextBytes(content.bytes).text);
        ids.addAll(file.entries.map((e) => e.id));
      } on Object {
        // A sibling that cannot be read names no ids.
      }
    }
    return ids;
  }

  /// The base a new todo is offered: the series of the file's last todo,
  /// numbered one past the folder's highest.
  String suggestedBase(Set<String> folderIds) {
    final last = _file?.entries.isEmpty ?? true ? '' : _file!.entries.last.id;
    return last.isEmpty ? 'todo1' : tomNextTodoBase(last, folderIds);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_onSession);
    super.dispose();
  }
}
