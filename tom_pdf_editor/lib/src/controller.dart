// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_undo/tom_undo.dart';

import 'engine/engine.dart';
import 'host.dart';
import 'pdf_editor_trail.dart';

/// Where a [TomPdfEditorController] is.
enum TomPdfEditorState {
  /// Not opened yet.
  idle,

  /// The engine is starting or the file is loading.
  opening,

  /// The file needs a password (see [TomPdfEditorController.passwordAttempt]).
  password,

  /// Open.
  open,

  /// Saving.
  saving,

  /// It could not open, or could not continue (see
  /// [TomPdfEditorController.failure]).
  failed,

  /// Closed.
  closed,
}

/// Why the document is read-only.
enum TomPdfReadOnlyReason {
  /// The file is not writable, or on a read-only volume.
  notWritable,

  /// The host asked for it.
  hostAsked,
}

/// One edit of the document (an annotation or a form field, todos
/// officeproto15 and officeproto16): it applies and reverts itself on the
/// engine's page.
abstract interface class TomPdfEdit {
  /// The history label.
  String get label;

  /// Applies the edit.
  Future<void> apply(TomPdfEditorController controller);

  /// Reverts it.
  Future<void> revert(TomPdfEditorController controller);
}

/// A conflict with the file on disk.
@immutable
final class TomPdfConflict {
  const TomPdfConflict({required this.deleted, this.temporary});

  /// Whether the file was deleted (else changed).
  final bool deleted;

  /// The saved copy waiting for the choice, when the conflict came at a
  /// save.
  final String? temporary;
}

/// A selection on one page: [count] characters from [start].
@immutable
final class PdfPageSelection {
  const PdfPageSelection(this.page, this.start, this.count, this.rects);

  /// The page.
  final int page;

  /// The first character.
  final int start;

  /// The number of characters.
  final int count;

  /// Its rectangles, in view points.
  final List<PdfRect> rects;
}

/// What a host drives: open, save, undo, redo, find, the dirty state. It has
/// the shape of `TomOfficeEditorController`.
class TomPdfEditorController extends ChangeNotifier {
  /// A controller over [host]; [readOnly] is the host asking for a
  /// read-only document.
  TomPdfEditorController(this.host, {this.hostReadOnly = false});

  /// The host.
  final TomPdfEditorHost host;

  /// Whether the host asked for a read-only document.
  final bool hostReadOnly;

  TomPdfEditorState _state = TomPdfEditorState.idle;
  TomPdfEngine? _engine;
  PdfDocumentInfo? _info;
  TomFileRevision? _revision;
  String? _password; // only while the document is open; never logged
  String? _failure;
  int _passwordAttempt = 0;
  bool _passwordWrong = false;
  TomPdfReadOnlyReason? _readOnly;
  bool? _hasTextLayer;
  TomPdfConflict? _conflict;
  bool _deleted = false;
  final _notices = StreamController<(String, String)>.broadcast();

  /// The history: annotation and form edits (later todos); search and
  /// selection are not history.
  final history = TomUndoStack<TomPdfEdit>();
  TomPdfEdit? _savedTop;
  bool _savedEmpty = true;

  /// The state.
  TomPdfEditorState get state => _state;

  /// The engine, once started.
  TomPdfEngine? get engine => _engine;

  /// The open document.
  PdfDocumentInfo? get info => _info;

  /// Why it could not open, or could not continue.
  String? get failure => _failure;

  /// The password attempt asked for (1 to 3), while [state] is `password`.
  int get passwordAttempt => _passwordAttempt;

  /// Whether the last password was wrong.
  bool get passwordWrong => _passwordWrong;

  /// Why the document is read-only, or `null`.
  TomPdfReadOnlyReason? get readOnlyReason => _readOnly;

  /// Whether the document is read-only.
  bool get isReadOnly => _readOnly != null;

  /// Whether the annotation tools may be used: writable, not encrypted
  /// (DPPF-3), and the annotate permission set.
  bool get canAnnotate =>
      _info != null && !isReadOnly && !_info!.encrypted && _info!.canAnnotate;

  /// Whether text may be copied (the copy permission).
  bool get canCopy => _info?.canCopy ?? false;

  /// Whether the document has a text layer: `null` until known; false for a
  /// scanned PDF (search and selection then unavailable).
  bool? get hasTextLayer => _hasTextLayer;

  /// A pending conflict with the file on disk.
  TomPdfConflict? get conflict => _conflict;

  /// Whether the file was deleted on disk.
  bool get isDeleted => _deleted;

  /// `(kind, message)` notices for the widget to show through the host.
  Stream<(String, String)> get notices => _notices.stream;

  /// Whether there are unsaved edits (against the saved marker).
  bool get isDirty {
    if (history.canUndo) {
      return _savedEmpty || !identical(_topEdit, _savedTop);
    }
    return !_savedEmpty;
  }

  TomPdfEdit? _topEdit;

  /// Whether undo is possible.
  bool get canUndo => history.canUndo && !history.isApplying;

  /// Whether redo is possible.
  bool get canRedo => history.canRedo && !history.isApplying;

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _set(TomPdfEditorState s) {
    if (_state == s) return;
    pdfTrail('state ${_state.name} → ${s.name}');
    _state = s;
    notifyListeners();
  }

  void _notice(String kind, String message) {
    if (!_notices.isClosed) _notices.add((kind, message));
  }

  // ----------------------------------------------------------------- opening

  /// Opens the host's file: the library must be usable, then the engine
  /// loads it (lazily from disk). A changed revision during the load reopens.
  Future<void> open() async {
    final library = host.pdfium;
    pdfTrail('library: ${library.message}');
    if (!library.isUsable) {
      _failure = library.message;
      _set(TomPdfEditorState.failed);
      return;
    }
    _passwordAttempt = 0;
    _passwordWrong = false;
    _failure = null;
    _set(TomPdfEditorState.opening);
    try {
      _engine ??= await host.startEngine(library);
    } catch (e, s) {
      pdfReport(e, s, 'starting the engine');
      _failure = 'PDFium did not start: $e';
      _set(TomPdfEditorState.failed);
      return;
    }
    await _load(null);
  }

  Future<void> _load(String? password, {int reopens = 0}) async {
    final engine = _engine!;
    _revision = await host.files.revisionOf(host.filePath);
    if (_revision == null) {
      _failure = 'the file does not exist';
      _set(TomPdfEditorState.failed);
      return;
    }
    final watch = Stopwatch()..start();
    final result = await engine.open(host.filePath, password: password);
    pdfTrail(
      'open ${result.info != null ? 'ok' : result.error!.name} in '
      '${watch.elapsedMilliseconds} ms${password == null ? '' : ' (password <redacted>)'}',
    );
    final info = result.info;
    if (info == null) {
      if (result.error == PdfOpenError.password) {
        _passwordWrong = password != null;
        if (_passwordAttempt >= 3) {
          _failure = 'could not open: the password was wrong three times';
          _set(TomPdfEditorState.failed);
          return;
        }
        _passwordAttempt++;
        _set(TomPdfEditorState.password);
        notifyListeners();
        return;
      }
      _failure = 'could not open: ${result.message}';
      _set(TomPdfEditorState.failed);
      return;
    }
    final after = await host.files.revisionOf(host.filePath);
    if (after == null || !after.sameContent(_revision!)) {
      await engine.close(info.handle);
      if (reopens < 2) return _load(password, reopens: reopens + 1);
      _failure = 'the file keeps changing while it opens';
      _set(TomPdfEditorState.failed);
      return;
    }
    _password = password;
    _info = info;
    _readOnly = hostReadOnly
        ? TomPdfReadOnlyReason.hostAsked
        : (await host.files.isWritable(host.filePath)
              ? null
              : TomPdfReadOnlyReason.notWritable);
    _set(TomPdfEditorState.open);
    _afterOpen();
  }

  void _afterOpen() {
    final info = _info!;
    if (info.formType == PdfFormType.xfaFull ||
        info.formType == PdfFormType.xfaForeground) {
      _notice('info', 'This PDF uses XFA forms, which are not shown.');
    }
    if (info.encrypted && info.canAnnotate && !isReadOnly) {
      _notice(
        'info',
        'This PDF is encrypted: annotations and form filling are not '
            'available.',
      );
    } else if (!info.canAnnotate && !isReadOnly) {
      _notice('info', 'This PDF does not allow annotations.');
    }
    if (!info.canCopy) {
      _notice('info', 'This PDF does not allow copying its text.');
    }
    unawaited(_checkTextLayer());
  }

  /// A scanned PDF has no characters on its pages: the first three pages
  /// decide.
  Future<void> _checkTextLayer() async {
    final info = _info!;
    try {
      var chars = 0;
      for (var p = 0; p < info.pageCount && p < 3 && chars == 0; p++) {
        chars += await _engine!.charCount(info.handle, p);
      }
      _hasTextLayer = chars > 0;
      if (!_hasTextLayer!) {
        _notice(
          'info',
          'This PDF has no text layer (scanned) — search and selection are '
              'not available.',
        );
      }
      notifyListeners();
    } catch (e, s) {
      pdfReport(e, s, 'checking the text layer');
    }
  }

  /// Answers the password dialog; `null` cancels (*could not open*).
  Future<void> answerPassword(String? password) async {
    if (_state != TomPdfEditorState.password) return;
    pdfTrail(password == null ? 'password cancelled' : 'password <redacted>');
    if (password == null) {
      _failure = 'could not open: no password given';
      _set(TomPdfEditorState.failed);
      return;
    }
    _set(TomPdfEditorState.opening);
    await _load(password);
  }

  /// Reopens the document from disk (after a save, *take theirs*, an
  /// external change); the view keeps its position.
  Future<void> reopen() async {
    final engine = _engine;
    final old = _info;
    if (engine == null) return open();
    if (old != null) await engine.close(old.handle);
    _info = null;
    _conflict = null;
    _deleted = false;
    _hasTextLayer = null;
    _clearFind();
    clearSelection();
    _set(TomPdfEditorState.opening);
    await _load(_password);
    _reopened++;
  }

  int _reopened = 0;

  /// Counts reopens, so the view knows to drop its rendered images.
  int get generation => _reopened;

  // ----------------------------------------------------------------- history

  /// Records an edit already applied (annotations, form fields).
  void pushEdit(TomPdfEdit edit) {
    history.push(edit);
    _topEdit = edit;
    _historyChanged();
  }

  /// Undoes the newest edit.
  Future<void> undo() async {
    if (!canUndo) return;
    await history.undoAsync((e) => e.revert(this));
    _topEdit = _peekTop();
    _historyChanged();
  }

  /// Redoes the newest undone edit.
  Future<void> redo() async {
    if (!canRedo) return;
    final e = await history.redoAsync((e) => e.apply(this));
    _topEdit = e;
    _historyChanged();
  }

  TomPdfEdit? _peekTop() {
    final top = history.popNewest();
    if (top != null) history.push(top);
    return top;
  }

  void _markSaved() {
    _savedTop = _topEdit;
    _savedEmpty = !history.canUndo;
    _historyChanged();
  }

  void _historyChanged() {
    host.historyChanged();
    notifyListeners();
  }

  // ------------------------------------------------------------------ saving

  /// Saves incrementally to a temporary target and replaces the original
  /// when it is unchanged; otherwise a [conflict]. After a replace the
  /// document is reopened from the new file.
  Future<void> save() async {
    if (_state != TomPdfEditorState.open || _info == null) return;
    if (isReadOnly) {
      _notice('warning', 'This document is read-only: use Save as copy.');
      return;
    }
    _set(TomPdfEditorState.saving);
    try {
      await host.files.removeTemporaryFiles(host.filePath);
      final temp = await host.files.temporaryTarget(host.filePath);
      pdfTrail('save → temporary target');
      final error = await _engine!.saveIncremental(_info!.handle, temp);
      if (error != null) {
        _notice('error', 'Could not save: $error');
        _set(TomPdfEditorState.open);
        return;
      }
      final result = await host.files.replace(
        host.filePath,
        temp,
        _deleted ? null : _revision,
      );
      if (!result.replaced) {
        pdfTrail('save: conflict');
        _conflict = TomPdfConflict(
          deleted: result.revision == null,
          temporary: temp,
        );
        _set(TomPdfEditorState.open);
        notifyListeners();
        return;
      }
      pdfTrail('save: replaced');
      _markSaved();
      await reopen();
    } catch (e, s) {
      pdfReport(e, s, 'saving');
      _notice('error', 'Could not save: $e');
      _set(TomPdfEditorState.open);
    }
  }

  /// The conflict choice *Keep mine*: replace the file on disk anyway.
  Future<void> keepMine() async {
    final c = _conflict;
    if (c == null) return;
    var temp = c.temporary;
    if (temp == null) {
      temp = await host.files.temporaryTarget(host.filePath);
      final error = await _engine!.saveIncremental(_info!.handle, temp);
      if (error != null) {
        _notice('error', 'Could not save: $error');
        return;
      }
    }
    await host.files.replace(host.filePath, temp, null, force: true);
    _markSaved();
    await reopen();
  }

  /// The conflict choice *Take theirs*: reopen from disk; the edits are
  /// lost.
  Future<void> takeTheirs() async {
    history.clear();
    _topEdit = null;
    _markSaved();
    await reopen();
  }

  /// The conflict choice *Save as copy*: the saved bytes become
  /// `<name> (copy).pdf` beside the original. Also offered for a read-only
  /// document.
  Future<String?> saveAsCopy() async {
    if (_info == null) return null;
    var temp = _conflict?.temporary;
    if (temp == null) {
      temp = await host.files.temporaryTarget(host.filePath);
      final error = await _engine!.saveIncremental(_info!.handle, temp);
      if (error != null) {
        _notice('error', 'Could not save a copy: $error');
        return null;
      }
    }
    final copy = await host.files.keepAsCopy(temp, host.filePath);
    _conflict = null;
    _notice('info', 'Saved as ${copy.split('/').last}');
    notifyListeners();
    return copy;
  }

  // -------------------------------------------------------- external changes

  /// Compares the file on disk with the one opened (the host calls it when
  /// the window regains focus): a clean document reopens with a notice, a
  /// dirty one shows the conflict banner, a deleted file is marked.
  Future<void> checkExternal() async {
    if (_state != TomPdfEditorState.open || _revision == null) return;
    final now = await host.files.revisionOf(host.filePath);
    if (now == null) {
      if (!_deleted) {
        _deleted = true;
        _notice('warning', '${host.name} was deleted on disk.');
        notifyListeners();
      }
      return;
    }
    if (now.sameContent(_revision!)) return;
    if (isDirty) {
      _conflict = const TomPdfConflict(deleted: false);
      notifyListeners();
    } else {
      await reopen();
      _notice('info', '${host.name} changed on disk and was reloaded.');
    }
  }

  // ------------------------------------------------------------------ search

  String _findTerm = '';
  bool _findCase = false;
  bool _findWord = false;
  final _hits = <PdfSearchHit>[];
  int _currentHit = -1;
  bool _searching = false;
  StreamSubscription<PdfSearchHit>? _findSub;
  bool _findVisible = false;

  /// Whether the find bar shows.
  bool get findVisible => _findVisible;

  /// The hits found so far.
  List<PdfSearchHit> get hits => List.unmodifiable(_hits);

  /// The current hit, or -1.
  int get currentHit => _currentHit;

  /// Whether a search is still running.
  bool get searching => _searching;

  /// The term searched for.
  String get findTerm => _findTerm;

  /// Shows the find bar (the shell's Cmd+F through the host).
  void showFind() {
    if (_hasTextLayer == false) {
      _notice(
        'info',
        'This PDF has no text layer (scanned) — search is not available.',
      );
      return;
    }
    _findVisible = true;
    notifyListeners();
  }

  /// Hides the find bar and its highlights.
  void hideFind() {
    _findVisible = false;
    _clearFind();
    notifyListeners();
  }

  void _clearFind() {
    unawaited(_findSub?.cancel());
    _findSub = null;
    _hits.clear();
    _currentHit = -1;
    _searching = false;
  }

  /// A page the view should scroll to (and the rectangle to show), set by
  /// search, links and the page list.
  final scrollRequest = ValueNotifier<(int, PdfRect?)?>(null);

  /// Searches the document from [fromPage]; hits stream in, and the view
  /// jumps to the first while later pages are still searched.
  void find(
    String term, {
    bool matchCase = false,
    bool wholeWord = false,
    int fromPage = 0,
  }) {
    final info = _info;
    if (info == null) return;
    _clearFind();
    _findTerm = term;
    _findCase = matchCase;
    _findWord = wholeWord;
    if (term.isEmpty) {
      notifyListeners();
      return;
    }
    pdfTrail('search start (${term.length} chars)');
    _searching = true;
    final watch = Stopwatch()..start();
    _findSub = _engine!
        .find(
          info.handle,
          term,
          matchCase: matchCase,
          wholeWord: wholeWord,
          fromPage: fromPage,
        )
        .listen(
          (hit) {
            _hits.add(hit);
            if (_currentHit < 0) {
              _currentHit = 0;
              scrollRequest.value = (hit.page, hit.rects.firstOrNull);
            }
            notifyListeners();
          },
          onDone: () {
            _searching = false;
            pdfTrail(
              'search end: ${_hits.length} hits in ${watch.elapsedMilliseconds} ms',
            );
            notifyListeners();
          },
          onError: (Object e, StackTrace s) {
            _searching = false;
            pdfReport(e, s, 'search');
            notifyListeners();
          },
        );
    notifyListeners();
  }

  /// Whether the last search matched case / whole words.
  (bool, bool) get findOptions => (_findCase, _findWord);

  /// Moves to the next hit (wrapping).
  void nextHit() => _moveHit(1);

  /// Moves to the previous hit (wrapping).
  void previousHit() => _moveHit(-1);

  void _moveHit(int delta) {
    if (_hits.isEmpty) return;
    _currentHit = (_currentHit + delta) % _hits.length;
    final hit = _hits[_currentHit];
    scrollRequest.value = (hit.page, hit.rects.firstOrNull);
    notifyListeners();
  }

  // --------------------------------------------------------------- selection

  final _selection = <PdfPageSelection>[];

  /// The selection, one range per page (it can run over pages).
  List<PdfPageSelection> get selection => List.unmodifiable(_selection);

  /// Selects from the character at ([fromPage], [from]) to the one at
  /// ([toPage], [to]), in view points; across pages each page between is
  /// selected whole.
  Future<void> selectBetween(
    int fromPage,
    ({double x, double y}) from,
    int toPage,
    ({double x, double y}) to,
  ) async {
    final info = _info;
    if (info == null || _hasTextLayer == false) return;
    final engine = _engine!;
    var (p0, a, p1, b) = (fromPage, from, toPage, to);
    if (p1 < p0 || (p1 == p0 && (b.y < a.y || (b.y == a.y && b.x < a.x)))) {
      (p0, a, p1, b) = (p1, b, p0, a);
    }
    final start = await _nearestChar(
      engine,
      info.handle,
      p0,
      a.x,
      a.y,
      first: true,
    );
    final end = await _nearestChar(
      engine,
      info.handle,
      p1,
      b.x,
      b.y,
      first: false,
    );
    final ranges = <PdfPageSelection>[];
    for (var page = p0; page <= p1; page++) {
      final count = await engine.charCount(info.handle, page);
      if (count == 0) continue;
      final s = page == p0 ? start : 0;
      final e = page == p1 ? end : count - 1;
      if (s < 0 || e < 0 || e < s) continue;
      ranges.add(
        PdfPageSelection(
          page,
          s,
          e - s + 1,
          await engine.rangeRects(info.handle, page, s, e - s + 1),
        ),
      );
    }
    _selection
      ..clear()
      ..addAll(ranges);
    notifyListeners();
  }

  /// The character at a point, or the nearest on the page when the point is
  /// between characters: the first one for a selection's start, the last one
  /// for its end.
  Future<int> _nearestChar(
    TomPdfEngine engine,
    int doc,
    int page,
    double x,
    double y, {
    required bool first,
  }) async {
    final at = await engine.charIndexAt(doc, page, x, y);
    if (at >= 0) return at;
    final count = await engine.charCount(doc, page);
    if (count == 0) return -1;
    return first ? 0 : count - 1;
  }

  /// Selects the word (`line: false`) or line around the character at
  /// ([x], [y]) on [page]: double- and triple-click.
  Future<void> selectAround(
    int page,
    double x,
    double y, {
    required bool line,
  }) async {
    final info = _info;
    if (info == null || _hasTextLayer == false) return;
    final engine = _engine!;
    final at = await engine.charIndexAt(info.handle, page, x, y);
    if (at < 0) return;
    final count = await engine.charCount(info.handle, page);
    final text = (await engine.text(info.handle, page, 0, count)).text;
    // The text skips unmapped characters, so it is matched to indices only
    // when nothing was skipped; otherwise the word is the character alone.
    if (text.length != count) {
      _selection
        ..clear()
        ..add(
          PdfPageSelection(
            page,
            at,
            1,
            await engine.rangeRects(info.handle, page, at, 1),
          ),
        );
      notifyListeners();
      return;
    }
    bool inside(int i) {
      final c = text[i];
      if (line) return c != '\n' && c != '\r';
      return RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(c);
    }

    var s = at;
    var e = at;
    if (inside(at)) {
      while (s > 0 && inside(s - 1)) {
        s--;
      }
      while (e < count - 1 && inside(e + 1)) {
        e++;
      }
    }
    _selection
      ..clear()
      ..add(
        PdfPageSelection(
          page,
          s,
          e - s + 1,
          await engine.rangeRects(info.handle, page, s, e - s + 1),
        ),
      );
    notifyListeners();
  }

  /// Clears the selection.
  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  /// The selected text, pages joined with newlines; `null` (with a notice)
  /// when copying is not allowed. A notice says when characters without a
  /// Unicode mapping were left out.
  Future<String?> selectedText() async {
    final info = _info;
    if (info == null || _selection.isEmpty) return null;
    if (!info.canCopy) {
      _notice('warning', 'This PDF does not allow copying its text.');
      return null;
    }
    final parts = <String>[];
    var skipped = 0;
    for (final s in _selection) {
      final t = await _engine!.text(info.handle, s.page, s.start, s.count);
      parts.add(t.text);
      skipped += t.skipped;
    }
    if (skipped > 0) {
      _notice(
        'warning',
        'Some text could not be copied ($skipped characters without a text mapping).',
      );
    }
    pdfTrail('copy ${_selection.length} range(s)');
    return parts.join('\n');
  }

  // ------------------------------------------------------------------- links

  /// The link at a point, or `null`.
  Future<PdfLink?> linkAt(int page, double x, double y) async {
    final info = _info;
    if (info == null) return null;
    return _engine!.linkAt(info.handle, page, x, y);
  }

  /// Follows a link: a URI goes to the host, an internal destination
  /// scrolls to its page.
  void followLink(PdfLink link) {
    if (link.uri != null) {
      pdfTrail('link: external');
      host.openLink(link.uri!);
    } else if (link.page != null) {
      pdfTrail('link: page ${link.page}');
      scrollRequest.value = (link.page!, null);
    }
  }

  // ------------------------------------------------------------------- close

  /// Closes the document and gives the engine share up.
  Future<void> close() async {
    _clearFind();
    final engine = _engine;
    final info = _info;
    _info = null;
    _engine = null;
    _password = null;
    if (engine != null) {
      if (info != null) await engine.close(info.handle);
      await engine.release();
    }
    _set(TomPdfEditorState.closed);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    unawaited(_notices.close());
    scrollRequest.dispose();
    super.dispose();
  }
}
