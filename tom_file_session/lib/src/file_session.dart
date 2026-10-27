/// The editing contract every file editor keeps, implemented once.
///
/// A [ForgeFileSession] is one open file: its decoded text, the encoding a
/// save writes back, the revision it was read at, its own undo history, and
/// what happened to it on disk since. Every editor edits through it, so byte
/// preservation, explicit save, the external-change choice and undo per file
/// are one implementation rather than one per kind of file.
library;

import 'package:tom_basics/utilities.dart';

import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_undo/tom_undo.dart';

/// Larger than this opens read-only.
const int forgeReadOnlyAbove = 2 * 1024 * 1024;

/// Larger than this is not opened.
const int forgeRefuseAbove = 50 * 1024 * 1024;

/// How long a pause ends one burst of typing and starts the next entry.
const Duration forgeFileTypingPause = Duration(milliseconds: 1500);

/// A file's history keeps this many entries, oldest dropped first.
const int forgeFileHistoryDepth = 1000;

/// Where a session is.
enum ForgeFileSessionState {
  loading,
  ready,

  /// The file is not there — removed before it was opened.
  missing,

  /// Larger than [forgeRefuseAbove], binary, or unreadable: [refusal] says.
  refused,
}

/// One entry of a file's history.
sealed class ForgeFileHistoryEntry {
  const ForgeFileHistoryEntry(this.label);

  /// What the entry did, as the history and the undo tooltip show it.
  final String label;
}

/// A text edit: [removed] at [start] was replaced by [inserted].
/// One structured edit is one of these however many lines it touched.
class ForgeFileTextEdit extends ForgeFileHistoryEntry {
  const ForgeFileTextEdit(super.label, this.start, this.removed, this.inserted);

  final int start;
  final String removed;
  final String inserted;
}

/// An act that wrote to disk when it was made — an archive, a delete — whose
/// undo and redo write to disk too. Each answers the file's text
/// and revision as the act left it.
class ForgeFileDiskAct extends ForgeFileHistoryEntry {
  const ForgeFileDiskAct(super.label, {required this.undo, required this.redo});

  final Future<TomFileContent> Function() undo;
  final Future<TomFileContent> Function() redo;
}

/// The file changed on disk while the session held unsaved edits.
class ForgeFileExternalChange {
  const ForgeFileExternalChange.modified(this.theirs, this.revision)
    : deleted = false;
  const ForgeFileExternalChange.deleted()
    : theirs = null,
      revision = null,
      deleted = true;

  final bool deleted;

  /// The file's text now, when it was modified.
  final String? theirs;
  final TomFileRevision? revision;
}

/// How a save ended.
enum ForgeFileSaveOutcome {
  saved,

  /// Nothing to save.
  clean,

  /// The file changed on disk: [ForgeFileSession.external] says how, and
  /// the user chooses before anything is written.
  conflict,

  /// The session is read-only, or its editor refused.
  refused,
}

/// One open file.
class ForgeFileSession {
  final List<void Function()> _listeners = [];
  var _disposed = false;

  /// Calls [listener] on every change of the session, without saying what.
  void addListener(void Function() listener) {
    if (_disposed) throw StateError('ForgeFileSession was used after dispose');
    _listeners.add(listener);
  }

  /// Stops calling [listener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Calls every listener, in the order they were added.
  void _notifyListeners() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Drops every listener; adding one afterwards is an error.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }

  /// [isBinary] decides, from the file's name and bytes, that a file is not
  /// text and is not opened; by default a file is binary when its first
  /// bytes do not read as text ([tomLooksLikeText]). A host that knows file
  /// kinds by name answers for the names it claims.
  ForgeFileSession({
    required this.fileSystem,
    required this.path,
    bool Function(String name, List<int> bytes)? isBinary,
  }) : _isBinary = isBinary ?? _bytesAreBinary;

  final TomFileSystem fileSystem;

  /// The path relative to [fileSystem]'s root.
  final String path;

  /// The file's URI.
  Uri get uri => fileSystem.uriOf(path);

  final bool Function(String name, List<int> bytes) _isBinary;

  static bool _bytesAreBinary(String name, List<int> bytes) =>
      !tomLooksLikeText(bytes);

  ForgeFileSessionState _state = ForgeFileSessionState.loading;
  ForgeFileSessionState get state => _state;

  String? _refusal;

  /// Why the file was not opened, when [state] is `refused`.
  String? get refusal => _refusal;

  String _text = '';
  String _saved = '';
  TomTextEncoding _encoding = TomTextEncoding.utf8;
  TomFileRevision? _revision;
  String? _readOnly;
  ForgeFileExternalChange? _external;
  bool _deletedOnDisk = false;
  String? _notice;

  final TomUndoStack<ForgeFileHistoryEntry> _history = TomUndoStack(
    maxEntries: forgeFileHistoryDepth,
  );

  /// The text as edited.
  String get text => _text;

  TomTextEncoding get encoding => _encoding;

  /// The revision the session last read or wrote.
  TomFileRevision? get revision => _revision;

  /// Why the file cannot be edited, or null when it can.
  String? get readOnlyReason => _readOnly;

  /// Unsaved edits.
  bool get dirty => _state == ForgeFileSessionState.ready && _text != _saved;

  /// The external change waiting for the user's choice, or null.
  ForgeFileExternalChange? get external => _external;

  /// The file was deleted on disk; Save recreates it.
  bool get deletedOnDisk => _deletedOnDisk;

  /// A one-off message for the editor ("Reloaded: changed on disk"); the
  /// reader takes it.
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  /// Consulted before a save writes — an editor that validates refuses while
  /// the file is invalid unless the user insists.
  Future<bool> Function()? beforeSave;

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  /// The history, oldest first — for tests and the history view.
  List<ForgeFileHistoryEntry> get history => _history.undoEntries;

  /// Reads the file. Opening never writes.
  ///
  /// A new session is already loading, and is created while a tab builds, so
  /// nothing is announced until the read has answered.
  Future<void> load() async {
    try {
      final entry = await fileSystem.stat(uri);
      if (entry == null) {
        _state = ForgeFileSessionState.missing;
        _notifyListeners();
        return;
      }
      if (entry.size > forgeRefuseAbove) {
        _refuse(
          'This file is ${(entry.size / (1024 * 1024)).toStringAsFixed(1)}'
          ' MiB; files larger than 50 MiB are not opened.',
        );
        return;
      }
      final content = await fileSystem.read(uri);
      if (_isBinary(path.split('/').last, content.bytes)) {
        _refuse('This is not a text file, and there is no editor for it.');
        return;
      }
      _adopt(content);
      _state = ForgeFileSessionState.ready;
    } on Object catch (e) {
      _refuse('This file could not be read: $e');
      return;
    }
    _notifyListeners();
  }

  void _refuse(String reason) {
    _refusal = reason;
    _state = ForgeFileSessionState.refused;
    _notifyListeners();
  }

  void _adopt(TomFileContent content) {
    _lastGroup = null;
    final decoded = tomDecodeTextBytes(content.bytes);
    _text = decoded.text;
    _saved = decoded.text;
    _encoding = decoded.encoding;
    _revision = content.revision;
    _deletedOnDisk = false;
    _readOnly = content.bytes.length > forgeReadOnlyAbove
        ? 'This file is larger than 2 MiB and is shown read-only.'
        : !decoded.encoding.writable
        ? 'This file is not UTF-8 or UTF-16 and is shown read-only, as '
              'Latin-1.'
        : null;
  }

  /// Replaces the text with [newText] as one history entry labelled [label].
  ///
  /// Typing is many edits and one gesture: edits that name the same [group]
  /// and follow each other within [forgeFileTypingPause] merge into one
  /// entry, so one Undo takes back a burst of typing rather than a letter.
  void edit(String newText, String label, {String? group}) {
    if (_readOnly != null) throw StateError(_readOnly!);
    if (newText == _text) return;
    final now = DateTime.now();
    final last = _history.nextUndo;
    if (group != null &&
        group == _lastGroup &&
        last is ForgeFileTextEdit &&
        !_history.canRedo &&
        _lastEditAt != null &&
        now.difference(_lastEditAt!) <= forgeFileTypingPause) {
      // The text before the last entry, and one replacement from it.
      final before = _text.replaceRange(
        last.start,
        last.start + last.inserted.length,
        last.removed,
      );
      _history.popNewest();
      final change = _diff(before, newText);
      if (change.$2.isNotEmpty || change.$3.isNotEmpty) {
        _history.push(
          ForgeFileTextEdit(last.label, change.$1, change.$2, change.$3),
        );
      }
    } else {
      final change = _diff(_text, newText);
      _history.push(ForgeFileTextEdit(label, change.$1, change.$2, change.$3));
    }
    _lastGroup = group;
    _lastEditAt = now;
    _text = newText;
    _notifyListeners();
  }

  String? _lastGroup;
  DateTime? _lastEditAt;

  /// The smallest single replacement turning [a] into [b].
  static (int, String, String) _diff(String a, String b) {
    var start = 0;
    final limit = a.length < b.length ? a.length : b.length;
    while (start < limit && a.codeUnitAt(start) == b.codeUnitAt(start)) {
      start++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > start &&
        endB > start &&
        a.codeUnitAt(endA - 1) == b.codeUnitAt(endB - 1)) {
      endA--;
      endB--;
    }
    return (start, a.substring(start, endA), b.substring(start, endB));
  }

  /// Undoes the newest entry. An act that wrote to disk is undone on disk,
  /// and only while the tab has no other unsaved edits — otherwise the write
  /// would carry them too.
  Future<void> undo() async {
    if (await _history.undoAsync((e) => _apply(e, reverse: true)) != null) {
      _stepped();
    }
  }

  Future<void> redo() async {
    if (await _history.redoAsync((e) => _apply(e, reverse: false)) != null) {
      _stepped();
    }
  }

  Future<void> _apply(
    ForgeFileHistoryEntry entry, {
    required bool reverse,
  }) async {
    switch (entry) {
      case ForgeFileTextEdit():
        final (find, put) = reverse
            ? (entry.inserted, entry.removed)
            : (entry.removed, entry.inserted);
        _text = _text.replaceRange(entry.start, entry.start + find.length, put);
      case ForgeFileDiskAct():
        if (_text != _saved) {
          throw StateError(
            'Save or discard the unsaved edits before '
            '${reverse ? 'undoing' : 'redoing'} "${entry.label}".',
          );
        }
        final result = await (reverse ? entry.undo() : entry.redo());
        final decoded = tomDecodeTextBytes(result.bytes);
        _text = decoded.text;
        _saved = decoded.text;
        _revision = result.revision;
    }
  }

  void _stepped() {
    _lastGroup = null;
    _notifyListeners();
  }

  /// Records an act that has already written to disk, leaving the file at
  /// [result]. It joins the history like an edit.
  void recordDiskAct(ForgeFileDiskAct act, TomFileContent result) {
    final decoded = tomDecodeTextBytes(result.bytes);
    _text = decoded.text;
    _saved = decoded.text;
    _revision = result.revision;
    _history.push(act);
    _notifyListeners();
  }

  /// Writes the text. Checks the disk first and never writes over a file
  /// that changed since it was read.
  Future<ForgeFileSaveOutcome> save() async {
    if (_readOnly != null || _state != ForgeFileSessionState.ready) {
      return ForgeFileSaveOutcome.refused;
    }
    if (!dirty && !_deletedOnDisk) return ForgeFileSaveOutcome.clean;
    if (_external != null) return ForgeFileSaveOutcome.conflict;
    if (!_deletedOnDisk) {
      await checkExternal();
      if (_external != null) return ForgeFileSaveOutcome.conflict;
    }
    final guard = beforeSave;
    if (guard != null && !await guard()) return ForgeFileSaveOutcome.refused;
    try {
      _revision = await fileSystem.write(
        uri,
        tomEncodeText(_text, _encoding),
        expected: _deletedOnDisk ? null : _revision,
      );
    } on TomFileConflict {
      await checkExternal();
      return ForgeFileSaveOutcome.conflict;
    }
    _saved = _text;
    _deletedOnDisk = false;
    _notifyListeners();
    return ForgeFileSaveOutcome.saved;
  }

  /// Compares the disk with what the session read: on a watch event, on
  /// focus, before a save.
  Future<void> checkExternal() async {
    if (_state != ForgeFileSessionState.ready) return;
    final entry = await fileSystem.stat(uri);
    if (entry == null) {
      if (!_deletedOnDisk) {
        _deletedOnDisk = true;
        _external = null;
        _notifyListeners();
      }
      return;
    }
    final TomFileContent content;
    try {
      content = await fileSystem.read(uri);
    } on Object {
      return;
    }
    if (!_deletedOnDisk && content.revision == _revision) return;
    if (_text == _saved && !_deletedOnDisk) {
      // Clean: reload, and the history goes with the text it described.
      _adopt(content);
      _history.clear();
      _external = null;
      _notice = 'Reloaded: changed on disk';
      _notifyListeners();
      return;
    }
    final theirs = tomDecodeTextBytes(content.bytes).text;
    _deletedOnDisk = false;
    _external = ForgeFileExternalChange.modified(theirs, content.revision);
    _notifyListeners();
  }

  /// Keep mine: the next save overwrites the changed file.
  void keepMine() {
    final change = _external;
    if (change == null) return;
    _revision = change.revision;
    _external = null;
    _notifyListeners();
  }

  /// Take theirs: reload, dropping the unsaved edits and the history.
  void takeTheirs() {
    final change = _external;
    if (change == null) return;
    _lastGroup = null;
    _text = change.theirs!;
    _saved = change.theirs!;
    _revision = change.revision;
    _history.clear();
    _external = null;
    _notifyListeners();
  }

  /// Saves [merged] — mine, theirs, or a hand merge — over the changed file.
  Future<ForgeFileSaveOutcome> saveMerged(String merged) async {
    final change = _external;
    if (change == null) return save();
    if (merged != _text) edit(merged, 'Merge with the file on disk');
    keepMine();
    return save();
  }

  /// Discards the unsaved edits.
  void discard() {
    _lastGroup = null;
    if (_text == _saved) return;
    _text = _saved;
    _history.clear();
    _notifyListeners();
  }
}
