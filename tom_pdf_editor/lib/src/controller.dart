// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_undo/tom_undo.dart';
import 'package:uuid/uuid.dart';

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

/// One edit of the document (annotations; form fields): it applies and
/// reverts itself on the engine's pages.
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

  /// The history: annotation and form edits; search and selection are not
  /// history.
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

  /// The label of the edit [undo] reverts.
  String? get undoLabel => history.canUndo ? _topEdit?.label : null;

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
    _clearAnnotations();
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

  /// Undoes the newest edit (a focused field's text is committed first, so
  /// it is what is undone).
  Future<void> undo() async {
    await releaseFormFocus();
    if (!canUndo) return;
    await history.undoAsync((e) => e.revert(this));
    _topEdit = history.nextUndo;
    _historyChanged();
  }

  /// Redoes the newest undone edit.
  Future<void> redo() async {
    await releaseFormFocus();
    if (!canRedo) return;
    final e = await history.redoAsync((e) => e.apply(this));
    _topEdit = e;
    _historyChanged();
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
    // The focused field's text is committed (and recorded) before saving.
    await releaseFormFocus();
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

  // ------------------------------------------------------------- annotations

  PdfAnnotationTool _tool = PdfAnnotationTool.select;
  final _toolColors = <PdfAnnotationTool, int>{
    PdfAnnotationTool.highlight: 0xFFFFEB3B,
    PdfAnnotationTool.note: 0xFFFFC107,
    PdfAnnotationTool.ink: 0xFFE53935,
  };
  final _annotations = <int, List<PdfAnnotation>>{};
  final _annotationLoads = <int, Future<List<PdfAnnotation>>>{};
  final _pageVersions = <int, int>{};
  ({int page, String id})? _selectedAnnotation;

  /// The annotation tool: [PdfAnnotationTool.select] unless [canAnnotate].
  PdfAnnotationTool get tool => canAnnotate ? _tool : PdfAnnotationTool.select;

  /// Chooses the annotation tool (ignored while annotating is not possible).
  void setTool(PdfAnnotationTool tool) {
    if (!canAnnotate && tool != PdfAnnotationTool.select) return;
    if (_tool == tool) return;
    pdfTrail('tool ${tool.name}');
    _tool = tool;
    if (tool != PdfAnnotationTool.select) {
      _selectedAnnotation = null;
      unawaited(releaseFormFocus());
    }
    notifyListeners();
  }

  /// The colour (ARGB) new annotations of [tool] get.
  int toolColor(PdfAnnotationTool tool) => _toolColors[tool] ?? 0xFFFFEB3B;

  /// Sets the colour of [tool]'s new annotations.
  void setToolColor(PdfAnnotationTool tool, int color) {
    _toolColors[tool] = color;
    notifyListeners();
  }

  /// Counts the edits of [page] since it was opened: a rendered image of an
  /// older version is shown until the new one has arrived.
  int pageVersion(int page) => _pageVersions[page] ?? 0;

  /// The annotations of [page] as loaded (empty until [loadAnnotations] has
  /// read them).
  List<PdfAnnotation> annotationsOn(int page) =>
      List.unmodifiable(_annotations[page] ?? const <PdfAnnotation>[]);

  /// Reads the annotations of [page] once (again after an edit or a reopen).
  Future<List<PdfAnnotation>> loadAnnotations(int page) {
    final loaded = _annotations[page];
    if (loaded != null) return Future.value(loaded);
    return _annotationLoads[page] ??= () async {
      final info = _info;
      final engine = _engine;
      if (info == null || engine == null) return const <PdfAnnotation>[];
      final generation = _reopened;
      try {
        final list = await engine.annotations(info.handle, page);
        if (generation == _reopened && identical(info, _info)) {
          _annotations[page] = list;
          notifyListeners();
        }
        return list;
      } finally {
        _annotationLoads.remove(page)?.ignore();
      }
    }();
  }

  /// The editable annotation at ([x], [y]) view points of [page], the
  /// topmost first; `null` when none is there (or not loaded yet).
  PdfAnnotation? annotationAt(int page, double x, double y) {
    final list = _annotations[page];
    if (list == null) return null;
    for (final a in list.reversed) {
      if (a.editable && annotationContains(a, x, y)) return a;
    }
    return null;
  }

  /// The selected annotation.
  PdfAnnotation? get selectedAnnotation {
    final s = _selectedAnnotation;
    if (s == null) return null;
    for (final a in _annotations[s.page] ?? const <PdfAnnotation>[]) {
      if (a.id == s.id) return a;
    }
    return null;
  }

  /// The page of the selected annotation.
  int? get selectedAnnotationPage => _selectedAnnotation?.page;

  /// Selects the annotation [id] of [page] (`null`: none).
  void selectAnnotation(int page, String? id) {
    final next = id == null ? null : (page: page, id: id);
    if (_selectedAnnotation == next) return;
    _selectedAnnotation = next;
    if (next != null) clearSelection();
    notifyListeners();
  }

  /// Highlights the text selection: one highlight per page, one history
  /// entry. Returns whether anything was highlighted.
  Future<bool> highlightSelection() async {
    if (!canAnnotate || _selection.isEmpty) return false;
    final changes = <_AnnotationChange>[];
    for (final s in _selection) {
      if (s.rects.isEmpty) continue;
      changes.add(
        _AnnotationChange(
          s.page,
          null,
          _stamp(
            PdfAnnotation(
              id: '',
              kind: PdfAnnotationKind.highlight,
              rect: _union(s.rects),
              quads: s.rects,
              color: toolColor(PdfAnnotationTool.highlight),
            ),
          ),
        ),
      );
    }
    if (changes.isEmpty) return false;
    clearSelection();
    await _perform(_AnnotationEdit('Highlight', changes));
    return true;
  }

  /// Adds a note with [text] whose icon's top left is at ([x], [y]).
  Future<PdfAnnotation?> addNote(
    int page,
    double x,
    double y,
    String text,
  ) async {
    if (!canAnnotate) return null;
    final note = _stamp(
      PdfAnnotation(
        id: '',
        kind: PdfAnnotationKind.note,
        rect: PdfRect(x, y, x + kPdfNoteSize, y + kPdfNoteSize),
        color: toolColor(PdfAnnotationTool.note),
        contents: text,
      ),
    );
    await _perform(
      _AnnotationEdit('Note', [_AnnotationChange(page, null, note)]),
    );
    selectAnnotation(page, note.id);
    return note;
  }

  /// Adds an ink annotation from [strokes] (view points; thinned).
  Future<PdfAnnotation?> addInk(
    int page,
    List<List<PdfPoint>> strokes, {
    double width = 2,
  }) async {
    if (!canAnnotate) return null;
    final thinned = [
      for (final s in strokes)
        if (s.isNotEmpty) thinStroke(s),
    ];
    if (thinned.isEmpty) return null;
    final points = thinned.expand((s) => s);
    final pad = width / 2 + 1;
    final ink = _stamp(
      PdfAnnotation(
        id: '',
        kind: PdfAnnotationKind.ink,
        rect: PdfRect(
          points.map((p) => p.x).reduce(_min) - pad,
          points.map((p) => p.y).reduce(_min) - pad,
          points.map((p) => p.x).reduce(_max) + pad,
          points.map((p) => p.y).reduce(_max) + pad,
        ),
        color: toolColor(PdfAnnotationTool.ink),
        strokes: thinned,
        width: width,
      ),
    );
    await _perform(
      _AnnotationEdit('Ink', [_AnnotationChange(page, null, ink)]),
    );
    return ink;
  }

  /// Replaces the annotation [id] of [page] by [next] (moved, resized,
  /// recoloured, its text changed) as one history entry labelled [label].
  Future<void> changeAnnotation(
    int page,
    String id,
    PdfAnnotation Function(PdfAnnotation current) next, {
    required String label,
  }) async {
    if (!canAnnotate) return;
    final current = (await loadAnnotations(page)).where((a) => a.id == id);
    if (current.isEmpty || !current.first.editable) return;
    final before = current.first;
    // An annotation of the file without NM gets one now.
    final after = _stamp(next(before), id: before.unnamed ? null : before.id);
    if (after == before) return;
    await _perform(
      _AnnotationEdit(label, [_AnnotationChange(page, before, after)]),
    );
    if (_selectedAnnotation?.id == id) selectAnnotation(page, after.id);
  }

  /// Moves the annotation by ([dx], [dy]) points.
  Future<void> moveAnnotation(int page, String id, double dx, double dy) =>
      changeAnnotation(page, id, (a) => a.moved(dx, dy), label: 'Move');

  /// Resizes an ink annotation into [rect].
  Future<void> resizeAnnotation(int page, String id, PdfRect rect) =>
      changeAnnotation(page, id, (a) => a.resized(rect), label: 'Resize');

  /// Recolours the annotation.
  Future<void> recolorAnnotation(int page, String id, int color) =>
      changeAnnotation(
        page,
        id,
        (a) => a.copyWith(color: color),
        label: 'Color',
      );

  /// Sets a note's text.
  Future<void> setNoteText(int page, String id, String text) =>
      changeAnnotation(
        page,
        id,
        (a) => a.copyWith(contents: text),
        label: 'Note text',
      );

  /// Removes the annotation [id] of [page].
  Future<void> deleteAnnotation(int page, String id) async {
    if (!canAnnotate) return;
    final current = (await loadAnnotations(page)).where((a) => a.id == id);
    if (current.isEmpty || !current.first.editable) return;
    if (_selectedAnnotation?.id == id) _selectedAnnotation = null;
    await _perform(
      _AnnotationEdit('Delete', [_AnnotationChange(page, current.first, null)]),
    );
  }

  /// [a] with the author, the modification date and its NM ([id], else a
  /// new one).
  PdfAnnotation _stamp(PdfAnnotation a, {String? id}) => a.copyWith(
    id: id ?? (a.id.isEmpty || a.unnamed ? _uuid.v4() : a.id),
    author: host.authorName,
    modified: pdfDate(DateTime.now()),
  );

  static const _uuid = Uuid();

  Future<void> _perform(_AnnotationEdit edit) async {
    await edit.apply(this);
    pushEdit(edit);
  }

  /// After an annotation edit of [page]: read its annotations again and
  /// mark its images old.
  Future<void> _annotationsChanged(int page) async {
    _annotations.remove(page);
    _pageVersions[page] = pageVersion(page) + 1;
    await loadAnnotations(page);
    notifyListeners();
  }

  void _clearAnnotations() {
    _annotations.clear();
    _annotationLoads.clear();
    _pageVersions.clear();
    _selectedAnnotation = null;
    _formFocus = null;
  }

  // ------------------------------------------------------------------ forms

  PdfFormField? _formFocus;

  /// Whether form fields can be filled in: an AcroForm document that is not
  /// read-only, not encrypted (DPPF-3) and allows filling.
  bool get canFill {
    final info = _info;
    return info != null &&
        !isReadOnly &&
        !info.encrypted &&
        info.canFillForms &&
        info.formType == PdfFormType.acroForm;
  }

  /// The field that has the focus (its typing goes to it), or `null`.
  PdfFormField? get formFocus => _formFocus;

  /// A click at ([x], [y]) view points of [page] for the form: answers
  /// whether a fillable field took it (else the click is the view's).
  Future<bool> formClick(int page, double x, double y) async {
    if (!canFill) return false;
    final r = await _engine!.formClick(_info!.handle, page, x, y);
    _applyForm(r);
    return r.handled;
  }

  /// The form field at ([x], [y]) view points of [page], or `null`.
  Future<PdfFormField?> formFieldAt(int page, double x, double y) async {
    if (!canFill) return null;
    return _engine!.formFieldAt(_info!.handle, page, x, y);
  }

  /// Typed text for the focused field.
  Future<void> formText(String text) async {
    if (_formFocus == null || !canFill) return;
    _applyForm(await _engine!.formText(_info!.handle, text));
  }

  /// A key for the focused field.
  Future<void> formKey(PdfFormKey key, {bool shift = false}) async {
    if (_formFocus == null || !canFill) return;
    _applyForm(await _engine!.formKey(_info!.handle, key, shift: shift));
  }

  /// The focused field's own undo (or [redo]) of its typing; answers whether
  /// it had one.
  Future<bool> formUndo({bool redo = false}) async {
    if (_formFocus == null || !canFill) return false;
    final r = await _engine!.formUndo(_info!.handle, redo: redo);
    _applyForm(r);
    return r.handled;
  }

  /// Takes the focus from the focused field, committing its text (one
  /// history entry when it changed). Called when the view loses the focus,
  /// an annotation tool is chosen, before undo, redo and saving.
  Future<void> releaseFormFocus() async {
    if (_formFocus == null) return;
    final info = _info;
    final engine = _engine;
    if (info == null || engine == null) {
      _formFocus = null;
      return;
    }
    _applyForm(await engine.formKillFocus(info.handle));
  }

  /// The pages to render again, the focus, the committed changes as history
  /// entries.
  void _applyForm(PdfFormResult r) {
    _formFocus = r.focused;
    for (final page in r.dirtyPages) {
      _pageVersions[page] = pageVersion(page) + 1;
    }
    for (final change in r.changes) {
      pdfTrail('form: ${change.type.name} committed');
      pushEdit(_FormEdit(change));
    }
    if (r.focused != null) {
      _selectedAnnotation = null;
      clearSelection();
    }
    notifyListeners();
  }

  /// Saves an unencrypted copy of an encrypted document (DPPF-3: the host
  /// asks first, see `TomPdfEditor`): `<name> (copy).pdf` beside the file.
  Future<String?> saveUnencryptedCopy() async {
    final info = _info;
    if (info == null) return null;
    final temp = await host.files.temporaryTarget(host.filePath);
    pdfTrail('save unencrypted copy');
    final error = await _engine!.saveCopy(
      info.handle,
      temp,
      removeSecurity: true,
    );
    if (error != null) {
      _notice('error', 'Could not save a copy: $error');
      return null;
    }
    final copy = await host.files.keepAsCopy(temp, host.filePath);
    _notice('info', 'Saved an unencrypted copy as ${copy.split('/').last}');
    notifyListeners();
    return copy;
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

/// The annotation tools.
enum PdfAnnotationTool {
  /// Select text, follow links, select annotations.
  select,

  /// Highlight text: a drag over text highlights it.
  highlight,

  /// A click places a note.
  note,

  /// A drag draws ink.
  ink,
}

/// A note icon's size in points.
const kPdfNoteSize = 20.0;

/// Whether ([x], [y]) view points is on [a]: a highlight's areas, an ink
/// stroke (within its width and 4 points), else the rectangle.
bool annotationContains(PdfAnnotation a, double x, double y) {
  bool inRect(PdfRect r, double pad) =>
      x >= r.left - pad &&
      x <= r.right + pad &&
      y >= r.top - pad &&
      y <= r.bottom + pad;
  switch (a.kind) {
    case PdfAnnotationKind.highlight when a.quads.isNotEmpty:
      return a.quads.any((q) => inRect(q, 1));
    case PdfAnnotationKind.ink when a.strokes.isNotEmpty:
      final reach = a.width / 2 + 4;
      for (final s in a.strokes) {
        for (var i = 0; i < s.length; i++) {
          final p = s[i];
          final q = i + 1 < s.length ? s[i + 1] : p;
          if (_segmentDistance(x, y, p, q) <= reach) return true;
        }
      }
      return false;
    default:
      return inRect(a.rect, 2);
  }
}

double _segmentDistance(double x, double y, PdfPoint p, PdfPoint q) {
  final dx = q.x - p.x;
  final dy = q.y - p.y;
  final len = dx * dx + dy * dy;
  var t = len == 0 ? 0.0 : ((x - p.x) * dx + (y - p.y) * dy) / len;
  t = t.clamp(0.0, 1.0);
  final cx = p.x + t * dx - x;
  final cy = p.y + t * dy - y;
  return math.sqrt(cx * cx + cy * cy);
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

PdfRect _union(List<PdfRect> rects) => PdfRect(
  rects.map((r) => r.left).reduce(_min),
  rects.map((r) => r.top).reduce(_min),
  rects.map((r) => r.right).reduce(_max),
  rects.map((r) => r.bottom).reduce(_max),
);

/// One annotation of one page changing: added ([before] `null`), removed
/// ([after] `null`) or replaced.
final class _AnnotationChange {
  _AnnotationChange(this.page, PdfAnnotation? before, this.after)
    : _match = before?.id,
      // A removed annotation of the file without NM comes back with one, so
      // the redo finds it again.
      before = before != null && before.unnamed
          ? before.copyWith(id: after?.id ?? const Uuid().v4())
          : before;

  final int page;
  final PdfAnnotation? before;
  final PdfAnnotation? after;

  /// How the engine finds the annotation [before] stands for: its first
  /// apply may need the `#index` of an annotation without NM.
  String? _match;
}

/// One history entry: annotation changes on one or more pages.
final class _AnnotationEdit implements TomPdfEdit {
  _AnnotationEdit(this.label, this.changes);

  @override
  final String label;

  final List<_AnnotationChange> changes;

  @override
  Future<void> apply(TomPdfEditorController c) async {
    final engine = c._engine!;
    final doc = c._info!.handle;
    for (final ch in changes) {
      final before = ch.before;
      final after = ch.after;
      if (before == null) {
        await engine.addAnnotation(doc, ch.page, after!);
      } else if (after == null) {
        await engine.removeAnnotation(doc, ch.page, ch._match ?? before.id);
      } else {
        await engine.updateAnnotation(
          doc,
          ch.page,
          ch._match ?? before.id,
          after,
        );
      }
      ch._match = null;
    }
    pdfTrail('edit: $label');
    for (final page in {for (final ch in changes) ch.page}) {
      await c._annotationsChanged(page);
    }
  }

  @override
  Future<void> revert(TomPdfEditorController c) async {
    final engine = c._engine!;
    final doc = c._info!.handle;
    for (final ch in changes.reversed) {
      final before = ch.before;
      final after = ch.after;
      if (after == null) {
        await engine.addAnnotation(doc, ch.page, before!);
      } else if (before == null) {
        await engine.removeAnnotation(doc, ch.page, after.id);
      } else {
        // The NM it got stays: [before]'s values under [after]'s name.
        await engine.updateAnnotation(
          doc,
          ch.page,
          after.id,
          before.copyWith(id: after.id),
        );
      }
    }
    pdfTrail('undo: $label');
    for (final page in {for (final ch in changes) ch.page}) {
      await c._annotationsChanged(page);
    }
  }
}

/// One committed form field change as a history entry.
final class _FormEdit implements TomPdfEdit {
  _FormEdit(this.change);

  final PdfFormChange change;

  @override
  String get label => switch (change.type) {
    PdfFieldType.checkbox => 'Checkbox',
    PdfFieldType.radio => 'Radio button',
    _ => 'Text field',
  };

  Future<void> _set(TomPdfEditorController c, String value) async {
    final r = await c._engine!.formSetValue(
      c._info!.handle,
      change.page,
      change.name,
      change.type,
      value,
    );
    c._applyForm(r);
  }

  @override
  Future<void> apply(TomPdfEditorController c) => _set(c, change.after);

  @override
  Future<void> revert(TomPdfEditorController c) async {
    await _set(c, change.before);
    if (change.type == PdfFieldType.radio && change.before.isEmpty) {
      // PDFium turns a radio button on only by a click, so a group cannot
      // go back to no button on.
      c._notice(
        'info',
        'The radio group stays on its choice: a PDF form cannot go back to no '
            'choice.',
      );
    }
  }
}
