// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'callbacks.dart';
import 'detection/installation.dart';
import 'helper/helper_channel.dart';
import 'host.dart';
import 'office_editor_trail.dart';
import 'tiles/tile_cache.dart';

/// Where the editor is.
enum TomOfficeEditorState {
  /// Not started yet.
  idle,

  /// Detection did not answer `found`: the editor never starts a helper and
  /// the view shows detection's state.
  unavailable,

  /// The helper is starting or loading the document.
  opening,

  /// The document asks for a password ([TomOfficeEditorController.passwordRequest]).
  password,

  /// The document is shown.
  open,

  /// A save is running.
  saving,

  /// The helper crashed or hung; the document is gone (DPLH-2).
  stopped,

  /// The document could not be opened ([TomOfficeEditorController.error]).
  failed,

  /// Closed by [TomOfficeEditorController.close].
  closed,
}

/// Why a document is read-only.
enum TomOfficeReadOnlyReason {
  /// The host asked for it.
  host,

  /// The file cannot be written (permissions, a read-only volume).
  notWritable,

  /// Another LibreOffice holds its lock file.
  locked,

  /// The user cancelled the password to modify.
  passwordToModify,

  /// The file is password-protected (DPOE-3: read-only, *Save as copy*).
  passwordProtected,
}

/// A save that found the file on disk changed, or the file changed while it
/// was open.
@immutable
final class TomOfficeConflict {
  /// A conflict from its parts.
  const TomOfficeConflict({this.temporary, this.deleted = false});

  /// The temporary file the save wrote (kept for *keep mine* and *save as
  /// copy*); `null` when the conflict was found by
  /// [TomOfficeEditorController.checkExternal] before any save.
  final String? temporary;

  /// Whether the file is gone.
  final bool deleted;
}

/// The editor's current password question.
@immutable
final class TomOfficePasswordRequest {
  /// A request from its parts.
  const TomOfficePasswordRequest({required this.toModify, this.attempt = 1});

  /// The password to modify (the cancel choice opens read-only), or the
  /// password to open.
  final bool toModify;

  /// The how-many-th time it is asked (a wrong password asks again, up to
  /// three times).
  final int attempt;
}

/// How a save ended.
enum TomOfficeSaveOutcome {
  /// Written and the original replaced.
  saved,

  /// The original changed on disk; [TomOfficeEditorController.conflict] is
  /// set and the temporary file kept.
  conflict,

  /// The helper or the file access failed; the original is untouched.
  failed,

  /// Nothing to do: no document, read-only, or a save already running.
  refused,
}

/// A notice the editor wants shown; the view hands it to
/// [TomOfficeEditorHost.notice].
@immutable
final class TomOfficeNotice {
  /// A notice from its parts.
  const TomOfficeNotice(this.message, {this.kind = 'info'});

  /// The text.
  final String message;

  /// `info`, `warning` or `error`.
  final String kind;
}

/// Decodes a tile's pixels into an image.
typedef TomOfficeImageDecoder =
    Future<ui.Image> Function(
      Uint8List pixels,
      int width,
      int height,
      OfficePixelFormat format,
    );

/// [ui.decodeImageFromPixels] for a tile.
Future<ui.Image> decodeOfficeTile(
  Uint8List pixels,
  int width,
  int height,
  OfficePixelFormat format,
) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    format == OfficePixelFormat.bgra
        ? ui.PixelFormat.bgra8888
        : ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// The zoom steps in percent (*fit width* is computed by the view).
const kOfficeZoomSteps = [50, 75, 100, 125, 150, 200, 300];

/// The edge of a tile in logical pixels.
const kOfficeTileSize = 256;

/// Twips per logical pixel at 100 % (1440 twips per inch, 96 px per inch).
const kTwipsPerPixel = 15.0;

/// The import options a CSV file opens with: comma, double quote, UTF-8,
/// from line 1 (LibreOfficeKit shows no import dialog).
const kCsvImportOptions = '44,34,76,1';

/// The export options a CSV file is saved with: the same, and token 7
/// (*quote all text cells*) off, so a round trip keeps the file's quoting.
const kCsvExportOptions = '44,34,76,1,,0,false';

/// What a host drives: open, save, undo, redo, the dirty state, external
/// changes. The view ([TomOfficeEditor]) draws it and forwards input to it.
class TomOfficeEditorController extends ChangeNotifier {
  /// A controller for [host]'s document. [readOnly] opens it read-only
  /// (the host's request). [pingInterval] and [hangTimeout] detect a hung
  /// helper; [decoder] turns tiles into images (tests may pass their own).
  TomOfficeEditorController({
    required this.host,
    bool readOnly = false,
    this.language = 'en-US',
    this.pingInterval = const Duration(seconds: 5),
    this.hangTimeout = const Duration(seconds: 20),
    this.inputRepaintDelay = const Duration(milliseconds: 100),
    TomOfficeImageDecoder? decoder,
    TileCache? cache,
  }) : _hostReadOnly = readOnly,
       _decoder = decoder ?? decodeOfficeTile,
       tiles = cache ?? TileCache();

  /// The application.
  final TomOfficeEditorHost host;

  /// The load options' language.
  final String language;

  /// How often an open helper is pinged.
  final Duration pingInterval;

  /// How long a ping may go unanswered before the helper counts as hung.
  final Duration hangTimeout;

  /// How long after its own input the editor waits for a callback before it
  /// repaints the visible tiles anyway (LibreOffice 26.8.3.1 sends no
  /// `INVALIDATE_TILES` for edits; first spike, item 4).
  final Duration inputRepaintDelay;

  /// The cached tiles.
  final TileCache tiles;

  final TomOfficeImageDecoder _decoder;
  final bool _hostReadOnly;

  TomOfficeHelperChannel? _channel;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _closing = false;
  int _nextId = 1;

  // ---------------------------------------------------------------- state

  TomOfficeEditorState _state = TomOfficeEditorState.idle;

  /// Where the editor is.
  TomOfficeEditorState get state => _state;

  /// Detection's answer, once [open] ran.
  LibreOfficeInstallation? get installation => _installation;
  LibreOfficeInstallation? _installation;

  /// Why the document could not be opened ([TomOfficeEditorState.failed]).
  String? get error => _error;
  String? _error;

  /// Why the helper stopped ([TomOfficeEditorState.stopped]).
  String? get stopReason => _stopReason;
  String? _stopReason;

  /// The `hello` of the running helper.
  OfficeHello? get hello => _hello;
  OfficeHello? _hello;

  /// The document's type.
  OfficeDocType get docType => _docType;
  OfficeDocType _docType = OfficeDocType.other;

  /// The number of parts (sheets, slides, pages).
  int get parts => _parts;
  int _parts = 1;

  /// The parts' names.
  List<String> get partNames => _partNames;
  List<String> _partNames = const [];

  /// The part shown.
  int get currentPart => _currentPart;
  int _currentPart = 0;

  /// Whether the view offers a part switcher: spreadsheets and
  /// presentations with more than one part. A text document's parts are
  /// its pages, all on one surface.
  bool get hasPartSwitcher =>
      _parts > 1 &&
      (_docType == OfficeDocType.spreadsheet ||
          _docType == OfficeDocType.presentation ||
          _docType == OfficeDocType.drawing);

  /// The part tiles are rendered from: 0 for a text document, else
  /// [currentPart].
  int get tilePart => _docType == OfficeDocType.text ? 0 : _currentPart;

  /// The document's size in twips (the current part's).
  ({int width, int height}) get documentSize => _size;
  ({int width, int height}) _size = (width: 0, height: 0);

  /// Whether the document is read-only, and why.
  TomOfficeReadOnlyReason? get readOnlyReason => _readOnlyReason;
  TomOfficeReadOnlyReason? _readOnlyReason;

  /// Whether the document is read-only.
  bool get isReadOnly => _readOnlyReason != null;

  /// Who holds the lock file, when another LibreOffice does.
  String? get lockedBy => _lockedBy;
  String? _lockedBy;

  /// Whether the document was opened with a password.
  bool get isPasswordProtected => _openedWithPassword;
  bool _openedWithPassword = false;

  /// The current password question ([TomOfficeEditorState.password]).
  TomOfficePasswordRequest? get passwordRequest => _passwordRequest;
  TomOfficePasswordRequest? _passwordRequest;

  /// The open conflict with the file on disk.
  TomOfficeConflict? get conflict => _conflict;
  TomOfficeConflict? _conflict;

  /// Whether the file was deleted while open; the next save recreates it.
  bool get fileDeleted => _fileDeleted;
  bool _fileDeleted = false;

  /// The revision the document was read at, or last saved at.
  TomFileRevision? get revision => _revision;
  TomFileRevision? _revision;

  /// `.uno:ModifiedStatus`.
  bool get isDirty => _dirty;
  bool _dirty = false;

  /// `.uno:Undo` enabled.
  bool get canUndo => _canUndo;
  bool _canUndo = false;

  /// `.uno:Redo` enabled.
  bool get canRedo => _canRedo;
  bool _canRedo = false;

  /// The other `STATE_CHANGED` values by command (`.uno:Bold` → `true`).
  Map<String, String> get commandStates => Map.unmodifiable(_states);
  final _states = <String, String>{};

  /// Progress of a load or a long save, 0–100; `null` when none runs.
  int? get progress => _progress;
  int? _progress;

  /// The caret, in twips, or `null`.
  OfficeTwipRect? get cursor => _cursorVisible ? _cursor : null;
  OfficeTwipRect? _cursor;
  bool _cursorVisible = true;

  /// The text selection's rectangles.
  List<OfficeTwipRect> get selection => _selection;
  List<OfficeTwipRect> _selection = const [];

  /// The selection's start and end handles.
  OfficeTwipRect? get selectionStart => _selectionStart;
  OfficeTwipRect? _selectionStart;

  /// See [selectionStart].
  OfficeTwipRect? get selectionEnd => _selectionEnd;
  OfficeTwipRect? _selectionEnd;

  /// A selected shape's frame.
  OfficeTwipRect? get graphicSelection => _graphic;
  OfficeTwipRect? _graphic;

  /// The spreadsheet's cell cursor.
  OfficeCellCursor? get cellCursor => _cellCursor;
  OfficeCellCursor? _cellCursor;

  /// The spreadsheet cell's content (`CELL_FORMULA`).
  String get cellFormula => _cellFormula;
  String _cellFormula = '';

  /// The cell's address (`CELL_ADDRESS`).
  String get cellAddress => _cellAddress;
  String _cellAddress = '';

  /// LibreOffice's pointer name (`MOUSE_POINTER`): `text`, `hand`, ….
  String get mousePointer => _mousePointer;
  String _mousePointer = 'default';

  /// The context menu LibreOffice asks to show, or `null`.
  List<OfficeContextMenuEntry>? get contextMenu => _contextMenu;
  List<OfficeContextMenuEntry>? _contextMenu;

  /// Dismisses [contextMenu] (the view showed it).
  void contextMenuShown() => _contextMenu = null;

  final _notices = StreamController<TomOfficeNotice>.broadcast();

  /// Notices to show; the view hands them to the host.
  Stream<TomOfficeNotice> get notices => _notices.stream;

  /// Counts tile arrivals: the view repaints on it.
  final ValueNotifier<int> tileRevision = ValueNotifier(0);

  void _setState(TomOfficeEditorState next) {
    if (_state == next) return;
    officeTrail('state ${_state.name} -> ${next.name}');
    _state = next;
    notifyListeners();
  }

  void _notice(String message, {String kind = 'info'}) {
    officeTrail('notice $kind');
    if (!_notices.isClosed) _notices.add(TomOfficeNotice(message, kind: kind));
  }

  // -------------------------------------------------------------- opening

  /// Whether the file is a CSV file (opened and saved with explicit filter
  /// options, DPOE-2).
  bool get isCsv => host.filePath.toLowerCase().endsWith('.csv');

  int _reopenBudget = 1;

  /// Opens the document: detection must be `found`; the revision is taken,
  /// a helper started, `open` sent after its `hello`.
  Future<void> open() async {
    _installation = host.helper.installation;
    if (!_installation!.isUsable) {
      officeTrail('detection ${_installation!.state.name}: not starting');
      _setState(TomOfficeEditorState.unavailable);
      return;
    }
    _closing = false;
    _error = null;
    _stopReason = null;
    _hangReason = null;
    _conflict = null;
    _fileDeleted = false;
    _passwordRequest = null;
    _openedWithPassword = false;
    _readOnlyReason = null;
    _resetView();
    _setState(TomOfficeEditorState.opening);
    try {
      _revision = await host.files.revisionOf(host.filePath);
      if (_revision == null) {
        _fail('${host.name} does not exist');
        return;
      }
      final channel = await host.helper.start(documentPath: host.filePath);
      if (_closing) {
        unawaited(channel.close());
        return;
      }
      _channel = channel;
      _subscriptions
        ..add(channel.events.listen(_onEvent, onError: _onStreamError))
        ..add(channel.log.listen((line) => officeTrail('helper: $line')));
      unawaited(channel.exit.then(_onExit));
    } catch (e, s) {
      officeReport(e, s, 'starting the helper');
      _fail('LibreOffice could not be started: $e');
    }
  }

  void _resetView() {
    tiles.clear();
    _pendingTiles.clear();
    _tileIds.clear();
    _staleSince.clear();
    _askedAt.clear();
    _visible = const {};
    _cursor = null;
    _selection = const [];
    _selectionStart = _selectionEnd = null;
    _graphic = null;
    _cellCursor = null;
    _cellFormula = '';
    _cellAddress = '';
    _contextMenu = null;
    _progress = null;
    _states.clear();
    _fonts = null;
    _styleFamilies = null;
    _lastWindow = null;
    for (final w in _windows.values) {
      w.image?.dispose();
    }
    _windows.clear();
    _windowPaints.clear();
    _dirty = _canUndo = _canRedo = false;
  }

  void _fail(String message) {
    _error = message;
    _setState(TomOfficeEditorState.failed);
  }

  void _send(OfficeHelperCommand command) {
    final channel = _channel;
    if (channel == null) return;
    switch (command) {
      case OfficeRenderTile():
        _tilesRequested++;
      case OfficePassword():
        officeTrail('-> password <redacted>');
      case OfficeKey(:final type, :final keyCode):
        officeTrail('-> key ${type.name} $keyCode');
      case OfficeTextInput(:final type, :final text):
        officeTrail('-> textInput ${type.name} (${text.length} chars)');
      case OfficePaste(:final mimeType, :final data):
        officeTrail('-> paste $mimeType (${data.length} chars)');
      case OfficeUno(:final id, :final command, :final args):
        // The command, never its arguments (they may hold typed text).
        officeTrail('-> uno #$id $command (${args.length})');
      default:
        officeTrail(
          '-> ${command.messageType.name}'
          '${command is OfficeRequest ? ' #${(command as OfficeRequest).id}' : ''}',
        );
    }
    try {
      channel.send(command);
    } catch (e, s) {
      officeReport(e, s, 'sending ${command.messageType.name}');
    }
  }

  void _onEvent(OfficeHelperEvent event) {
    try {
      _handle(event);
    } catch (e, s) {
      officeReport(e, s, 'handling ${event.messageType.name}');
    }
  }

  void _onStreamError(Object error, StackTrace stack) {
    officeReport(error, stack, 'reading the helper');
    _channel?.kill();
  }

  void _handle(OfficeHelperEvent event) {
    switch (event) {
      case OfficeTile():
        _tilesReceived++;
      case OfficeCallback(:final type, :final payload):
        officeTrail('<- callback $type (${payload.length})');
      default:
        officeTrail('<- ${event.messageType.name}');
    }
    switch (event) {
      case OfficeHello():
        _onHello(event);
      case OfficeOpened():
        unawaited(_onOpened(event));
      case OfficePasswordNeeded(:final toModify):
        final previous = _passwordRequest;
        final attempt = previous == null || previous.toModify != toModify
            ? 1
            : previous.attempt + 1;
        if (attempt > 3) {
          _passwordRequest = null;
          _send(const OfficePassword(password: null));
          return;
        }
        _passwordRequest = TomOfficePasswordRequest(
          toModify: toModify,
          attempt: attempt,
        );
        _setState(TomOfficeEditorState.password);
        notifyListeners();
      case OfficeTile():
        unawaited(_onTile(event));
      case OfficeCallback():
        _onCallback(event);
      case OfficeClipboard(:final id, :final data):
        _clipboardWaiters.remove(id)?.complete(data);
      case OfficeSaved(:final id):
        _saveWaiters.remove(id)?.complete(event);
      case OfficeValues(:final id, :final json):
        _valueWaiters.remove(id)?.complete(json);
      case OfficePong(:final id):
        if (id == _pingId) _pingOpen = false;
      case OfficeWindowOpened():
        _onWindowOpened(event);
      case OfficeWindowChanged():
        _onWindowChanged(event);
      case OfficeWindowPixels():
        unawaited(_onWindowPixels(event));
      case OfficeJsDialog(:final json):
        // Only a LibreOffice with JSON dialogs sends it; this one shows
        // its dialogs as windows (no form builder: spike item 8).
        _jsDialogs++;
        officeTrail('jsDialog ${json.length} bytes not shown ($_jsDialogs)');
      case OfficeError(:final id, :final code, :final message):
        _onError(id, code, message);
      case OfficeClosed():
        break;
    }
  }

  void _onHello(OfficeHello hello) {
    try {
      OfficeProtocolCodec.checkHello(hello);
    } on OfficeProtocolVersionMismatch catch (e) {
      _fail('The helper speaks another protocol: $e');
      unawaited(_channel?.close());
      return;
    }
    _hello = hello;
    _send(
      OfficeOpen(
        path: host.filePath,
        readOnly: _hostReadOnly,
        language: language,
        filterOptions: isCsv ? kCsvImportOptions : '',
      ),
    );
  }

  Future<void> _onOpened(OfficeOpened opened) async {
    _docType = opened.docType;
    _parts = opened.parts < 1 ? 1 : opened.parts;
    _partNames = opened.partNames;
    _currentPart = opened.currentPart;
    _size = (width: opened.width, height: opened.height);
    _lockedBy = opened.lockedBy;
    _openedWithPassword = _passwordRequest != null;
    final askedToModify = _passwordRequest?.toModify ?? false;
    _passwordRequest = null;
    final writable = await host.files.isWritable(host.filePath);
    _readOnlyReason = switch (true) {
      _ when _hostReadOnly => TomOfficeReadOnlyReason.host,
      _ when opened.lockedBy != null => TomOfficeReadOnlyReason.locked,
      _ when askedToModify && opened.readOnly =>
        TomOfficeReadOnlyReason.passwordToModify,
      _ when _openedWithPassword => TomOfficeReadOnlyReason.passwordProtected,
      _ when !writable => TomOfficeReadOnlyReason.notWritable,
      _ when opened.readOnly => TomOfficeReadOnlyReason.locked,
      _ => null,
    };
    // The file changed during the load: read it again.
    final now = await host.files.revisionOf(host.filePath);
    final before = _revision;
    if (now != null &&
        before != null &&
        !now.sameContent(before) &&
        _reopenBudget > 0) {
      _reopenBudget--;
      officeTrail('file changed during the load: reopening');
      _revision = now;
      await _restart();
      return;
    }
    _revision = now ?? before;
    _setState(TomOfficeEditorState.open);
    _startPing();
    notifyListeners();
  }

  void _onError(int? id, String code, String message) {
    officeTrail('<- error $code');
    if (id != null) {
      _saveWaiters
          .remove(id)
          ?.complete(OfficeSaved(id: id, ok: false, error: '$code: $message'));
      _clipboardWaiters.remove(id)?.completeError(message);
      _valueWaiters.remove(id)?.completeError(message);
      final key = _tileIds.remove(id);
      if (key != null) _pendingTiles.remove(key);
    }
    switch (code) {
      case 'jsonDialogsUnavailable':
        _jsonDialogs = false;
        _dialogMode = TomOfficeDialogMode.window;
        officeTrail('JSON dialogs refused: windows');
        _notice(
          'This LibreOffice shows its dialogs only as windows.',
          kind: 'warning',
        );
        notifyListeners();
      case 'passwordCancelled':
        _fail('${host.name} could not be opened: no password was given.');
      case 'loadFailed':
        _fail('${host.name} could not be opened: $message');
      default:
        if (_state == TomOfficeEditorState.opening) {
          _fail('${host.name} could not be opened: $message');
        } else if (id == null) {
          _notice(message, kind: 'error');
        }
    }
  }

  /// Answers [passwordRequest] with [password] (never stored); `null`
  /// cancels: the open fails, or (a password to modify) the document opens
  /// read-only.
  void answerPassword(String? password) {
    if (_state != TomOfficeEditorState.password) return;
    _setState(TomOfficeEditorState.opening);
    _send(OfficePassword(password: password));
  }

  // ------------------------------------------------------- helper ending

  void _onExit(TomOfficeHelperExit exit) {
    officeTrail(
      'helper exit: $exit${exit.stderrTail.isEmpty ? '' : ' | ${exit.stderrTail}'}',
    );
    _stopPing();
    final wasClosing = _closing;
    _channel = null;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    final failedSave = OfficeSaved(
      id: -1,
      ok: false,
      error: 'LibreOffice stopped',
    );
    for (final w in _saveWaiters.values) {
      w.complete(failedSave);
    }
    _saveWaiters.clear();
    for (final w in _clipboardWaiters.values) {
      w.completeError('LibreOffice stopped');
    }
    _clipboardWaiters.clear();
    for (final w in _valueWaiters.values) {
      w.completeError('LibreOffice stopped');
    }
    _valueWaiters.clear();
    for (final w in _windows.values) {
      w.image?.dispose();
    }
    _windows.clear();
    _windowPaints.clear();
    _windowPainting.clear();
    _windowDirty.clear();
    windowRevision.value++;
    if (wasClosing) return;
    switch (_state) {
      case TomOfficeEditorState.failed:
      case TomOfficeEditorState.closed:
      case TomOfficeEditorState.unavailable:
        return;
      case TomOfficeEditorState.opening:
      case TomOfficeEditorState.password:
        _fail('LibreOffice stopped while opening ${host.name} ($exit).');
        return;
      default:
        _stopReason = exit.reason ?? 'exit ${exit.code}';
        final wasDirty = _dirty || _canUndo || _canRedo;
        _dirty = _canUndo = _canRedo = false;
        _setState(TomOfficeEditorState.stopped);
        if (wasDirty) host.historyChanged();
        host.historyChanged();
    }
  }

  // ---------------------------------------------------------- hang check

  Timer? _pingTimer;
  int _pingId = 0;
  bool _pingOpen = false;
  int _pingTicks = 0;

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) => _ping());
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pingOpen = false;
  }

  void _ping() {
    if (_channel == null) return;
    // A save may block the helper's loop as long as it takes; so may a
    // modal command. Only an idle document is checked.
    if (_state != TomOfficeEditorState.open) return;
    if (_pingOpen) {
      // Counted in ping intervals, not wall time (timers are what a test
      // drives).
      _pingTicks++;
      if (pingInterval * _pingTicks >= hangTimeout) {
        officeTrail('hang: no pong in ${hangTimeout.inSeconds} s');
        _hangReason = 'hang (no pong in ${hangTimeout.inSeconds} s)';
        _channel?.kill();
      }
      return;
    }
    _pingId = _nextId++;
    _pingOpen = true;
    _pingTicks = 0;
    _send(OfficePing(id: _pingId));
  }

  String? _hangReason;

  // ----------------------------------------------------------- callbacks

  bool _inputPending = false;
  Timer? _inputTimer;

  /// Records that the editor sent input: the visible tiles are repainted at
  /// the next cursor, state, cell or size callback, or after
  /// [inputRepaintDelay].
  void _markInput() {
    _inputPending = true;
    _inputTimer?.cancel();
    _inputTimer = Timer(inputRepaintDelay, _repaintAfterInput);
  }

  void _repaintAfterInput() {
    if (!_inputPending) return;
    _inputPending = false;
    _inputTimer?.cancel();
    _invalidate(tilePart, null);
  }

  void _invalidate(int? part, OfficeTwipRect? rect) {
    final marked = tiles.invalidate(
      part,
      rect == null ? null : (x: rect.x, y: rect.y, w: rect.w, h: rect.h),
      tileTwips,
    );
    if (marked.isEmpty) return;
    _invalidation++;
    for (final key in marked) {
      _staleSince[key] = _invalidation;
    }
    _requestTiles(_nearestCursorFirst(_visible.where(marked.contains)));
    tileRevision.value++;
  }

  /// [keys] ordered by their distance from the cursor's tile (rows first,
  /// then columns), so that the tile being typed into is rendered, sent and
  /// decoded first and does not wait behind the rest of a repaint. Without
  /// a cursor, in their own order.
  List<TileKey> _nearestCursorFirst(Iterable<TileKey> keys) {
    final list = keys.toList();
    final cursor = _cursor;
    if (cursor == null || list.length < 2) return list;
    int distance(TileKey k) {
      final size = tileTwips(k.zoom);
      final row = (cursor.y / size).floor();
      final column = (cursor.x / size).floor();
      return (k.row - row).abs() * 1000 + (k.column - column).abs();
    }

    list.sort((a, b) => distance(a).compareTo(distance(b)));
    return list;
  }

  void _onCallback(OfficeCallback callback) {
    final payload = callback.payload;
    var changed = true;
    switch (callback.type) {
      case 'INVALIDATE_TILES':
        final inv = parseTileInvalidation(payload);
        final part = _docType == OfficeDocType.text ? null : inv.part;
        _invalidate(part, inv.rect);
        changed = false;
      case 'INVALIDATE_VISIBLE_CURSOR':
        _cursor = parseOfficeRect(payload);
        if (_inputPending) _repaintAfterInput();
      case 'CURSOR_VISIBLE':
        _cursorVisible = payload.trim() == 'true';
      case 'TEXT_SELECTION':
        _selection = parseOfficeRects(payload);
        if (_selection.isEmpty) _selectionStart = _selectionEnd = null;
      case 'TEXT_SELECTION_START':
        _selectionStart = parseOfficeRect(payload);
      case 'TEXT_SELECTION_END':
        _selectionEnd = parseOfficeRect(payload);
      case 'GRAPHIC_SELECTION':
        _graphic = parseOfficeRect(payload);
      case 'CELL_CURSOR':
        _cellCursor = parseCellCursor(payload);
        if (_inputPending) _repaintAfterInput();
      case 'CELL_FORMULA':
        _cellFormula = payload;
      case 'CELL_ADDRESS':
        _cellAddress = payload;
      case 'MOUSE_POINTER':
        _mousePointer = payload.trim();
      case 'DOCUMENT_SIZE_CHANGED':
        final size = parseDocumentSize(payload);
        if (size != null) _size = size;
        if (_inputPending) _repaintAfterInput();
      case 'SET_PART':
        final part = int.tryParse(payload.trim());
        if (part != null && part != _currentPart) {
          _currentPart = part;
        }
      case 'STATE_CHANGED':
        _onState(payload);
        if (_inputPending) _repaintAfterInput();
      case 'CONTEXT_MENU':
        final menu = parseContextMenu(payload);
        _contextMenu = menu.isEmpty ? null : menu;
      case 'HYPERLINK_CLICKED':
        host.openLink(parseHyperlink(payload));
        changed = false;
      case 'STATUS_INDICATOR_START':
        _progress = 0;
      case 'STATUS_INDICATOR_SET_VALUE':
        _progress = int.tryParse(payload.trim()) ?? _progress;
      case 'STATUS_INDICATOR_FINISH':
        _progress = null;
      case 'UNO_COMMAND_RESULT':
        _onUnoResult(payload);
        changed = false;
      default:
        changed = false;
    }
    if (changed) notifyListeners();
  }

  void _onState(String payload) {
    final state = parseStateChanged(payload);
    if (state == null) return;
    final (:command, :value) = state;
    var history = false;
    switch (command) {
      case '.uno:ModifiedStatus':
        final dirty = value == 'true';
        history = dirty != _dirty;
        _dirty = dirty;
      case '.uno:Undo':
        final can = value != 'disabled';
        history = can != _canUndo;
        _canUndo = can;
      case '.uno:Redo':
        final can = value != 'disabled';
        history = can != _canRedo;
        _canRedo = can;
      default:
        _states[command] = value;
        final pending = _unoPending[command];
        if (pending != null) pending.stateSeen = true;
    }
    if (history) host.historyChanged();
  }

  // -------------------------------------------------------------- tiles

  /// A tile's edge in twips at [zoom] percent.
  double tileTwips(int zoom) => kOfficeTileSize * kTwipsPerPixel * 100 / zoom;

  /// The zoom in percent.
  int get zoom => _zoom;
  int _zoom = 100;

  /// The device pixel ratio tiles are rendered for.
  double get devicePixelRatio => _dpr;
  double _dpr = 1;

  Set<TileKey> _visible = const {};
  final _pendingTiles = <TileKey, int>{};
  final _tileIds = <int, TileKey>{};
  final _tileSent = <int, DateTime>{};

  /// Counts the invalidations; [_staleSince] holds the one a stale tile
  /// dates from, [_askedAt] the one its pending request was sent after. A
  /// request sent after a tile's last invalidation renders it as it is now,
  /// so asking again would only throw that answer away (the view asks for
  /// its tiles on every rebuild).
  int _invalidation = 0;
  final _staleSince = <TileKey, int>{};
  final _askedAt = <TileKey, int>{};
  int _tilesRequested = 0;
  int _tilesReceived = 0;
  Duration _tileLatency = Duration.zero;
  DateTime _tileSummaryAt = DateTime.now();

  /// The view's tiles: requests the missing and stale ones of [visible] and
  /// then of [ring] (one ring around the view), at [zoom] percent for
  /// [devicePixelRatio].
  void showTiles(
    Set<TileKey> visible, {
    Iterable<TileKey> ring = const [],
    required int zoom,
    required double devicePixelRatio,
  }) {
    if (zoom != _zoom || devicePixelRatio != _dpr) {
      _zoom = zoom;
      _dpr = devicePixelRatio;
      // Requests of another zoom are of no use any more.
      _pendingTiles.removeWhere((key, _) => key.zoom != zoom);
    }
    _visible = visible;
    _requestTiles(visible);
    _requestTiles(ring);
    if (visible.isNotEmpty &&
        visible.every((k) => tiles.peek(k) != null && !tiles.peek(k)!.stale)) {
      tiles.dropOtherZooms(zoom);
    }
  }

  void _requestTiles(Iterable<TileKey> keys) {
    if (_channel == null ||
        (_state != TomOfficeEditorState.open &&
            _state != TomOfficeEditorState.saving)) {
      return;
    }
    for (final key in keys) {
      final cached = tiles.peek(key);
      if (cached != null && !cached.stale) continue;
      final old = _pendingTiles[key];
      // A pending request answers a missing tile, and a stale one when it
      // was sent after the tile's last invalidation.
      if (old != null &&
          (cached == null ||
              (_askedAt[key] ?? -1) >= (_staleSince[key] ?? 0))) {
        continue;
      }
      // Invalidated again since: the newer request replaces the pending one.
      if (old != null) _tileIds.remove(old);
      final id = _nextId++;
      _pendingTiles[key] = id;
      _tileIds[id] = key;
      _askedAt[key] = _invalidation;
      _tileSent[id] = DateTime.now();
      final size = tileTwips(key.zoom);
      final px = (kOfficeTileSize * _dpr).round();
      _send(
        OfficeRenderTile(
          id: id,
          part: key.part,
          x: (key.column * size).round(),
          y: (key.row * size).round(),
          w: size.round(),
          h: size.round(),
          pxW: px,
          pxH: px,
        ),
      );
    }
  }

  Future<void> _onTile(OfficeTile tile) async {
    final key = _tileIds.remove(tile.id);
    final sent = _tileSent.remove(tile.id);
    if (sent != null) _tileLatency += DateTime.now().difference(sent);
    _summariseTiles();
    if (key == null) return; // superseded
    if (_pendingTiles[key] == tile.id) {
      _pendingTiles.remove(key);
      _askedAt.remove(key);
      _staleSince.remove(key);
    }
    try {
      final image = await _decoder(
        tile.pixels,
        tile.pxW,
        tile.pxH,
        tile.format,
      );
      if (_state == TomOfficeEditorState.closed) {
        image.dispose();
        return;
      }
      tiles.put(key, image, keep: _visible);
      tileRevision.value++;
    } catch (e, s) {
      officeReport(e, s, 'decoding tile ${tile.id}');
    }
  }

  void _summariseTiles() {
    final now = DateTime.now();
    if (now.difference(_tileSummaryAt) < const Duration(seconds: 1)) return;
    if (kOfficeEditorDebug && _tilesReceived > 0) {
      final avg = _tileLatency.inMicroseconds / _tilesReceived / 1000;
      officeTrail(
        'tiles: $_tilesRequested requested, $_tilesReceived received, '
        '${avg.toStringAsFixed(1)} ms average',
      );
    }
    _tilesRequested = _tilesReceived = 0;
    _tileLatency = Duration.zero;
    _tileSummaryAt = now;
  }

  /// The zoom key of a slide thumbnail in the tile cache: no zoom step uses
  /// it, so the view's zoom changes never drop thumbnails.
  static const thumbnailZoom = -1;

  /// The thumbnail of slide [part] (about [width] pixels wide), or `null`
  /// while it is rendered; requested on first use.
  ui.Image? thumbnail(int part, {int width = 160}) {
    final key = TileKey(part, thumbnailZoom, 0, 0);
    final cached = tiles.peek(key);
    if (cached != null && !cached.stale) return cached.image;
    if (_pendingTiles.containsKey(key) || _channel == null) {
      return cached?.image;
    }
    if (_size.width <= 0 || _size.height <= 0) return null;
    final id = _nextId++;
    _pendingTiles[key] = id;
    _tileIds[id] = key;
    _send(
      OfficeRenderTile(
        id: id,
        part: part,
        x: 0,
        y: 0,
        w: _size.width,
        h: _size.height,
        pxW: (width * _dpr).round(),
        pxH: (width * _dpr * _size.height / _size.width).round(),
      ),
    );
    return cached?.image;
  }

  /// The spreadsheet's row and column headers for the twip area
  /// [area] (`.uno:ViewRowColumnHeaders`), or `null` when LibreOffice gives
  /// none.
  Future<TomOfficeSheetHeaders?> sheetHeaders(OfficeTwipRect area) async {
    if (_docType != OfficeDocType.spreadsheet) return null;
    try {
      final json = await commandValues(
        '.uno:ViewRowColumnHeaders?x=${area.x}&y=${area.y}'
        '&width=${area.w}&height=${area.h}',
      );
      return TomOfficeSheetHeaders.parse(json, zoom: _zoom);
    } catch (_) {
      return null;
    }
  }

  /// Tells LibreOffice what the view shows (after a scroll or a zoom), so
  /// its invalidations and the spreadsheet's extent fit.
  void setView(OfficeTwipRect visibleArea, int zoom) {
    if (_state != TomOfficeEditorState.open) return;
    _send(
      OfficeView(
        part: tilePart,
        visibleArea: OfficeRect(
          visibleArea.x,
          visibleArea.y,
          visibleArea.w,
          visibleArea.h,
        ),
        zoom: zoom / 100,
      ),
    );
  }

  /// Shows part [part] (a sheet, a slide).
  void setPart(int part) {
    if (part == _currentPart || part < 0 || part >= _parts) return;
    _currentPart = part;
    _send(OfficeSetPart(part: part));
    _cellCursor = null;
    _cursor = null;
    _selection = const [];
    notifyListeners();
  }

  // --------------------------------------------------------------- input

  bool get _editable => _state == TomOfficeEditorState.open && !isReadOnly;

  bool get _live =>
      _state == TomOfficeEditorState.open ||
      _state == TomOfficeEditorState.saving;

  /// Whether input that changes the document is taken.
  bool get acceptsEdits => _editable;

  /// Sends a key without text ([keyCode] with its VCL modifier bits).
  /// Editing keys are dropped in a read-only document; navigation keys
  /// still go.
  void key(int keyCode) {
    if (!_live) return;
    if (isReadOnly && !_isNavigation(keyCode)) return;
    _send(
      OfficeKey(type: OfficeKeyEventType.down, charCode: 0, keyCode: keyCode),
    );
    _send(
      OfficeKey(type: OfficeKeyEventType.up, charCode: 0, keyCode: keyCode),
    );
    _markInput();
  }

  static bool _isNavigation(int keyCode) {
    final code = keyCode & 0xfff;
    return (code >= 1024 && code <= 1031) || code == 1281; // arrows … escape
  }

  /// Types [text] as key events, one per character.
  void typeText(String text) {
    if (!_editable || text.isEmpty) return;
    for (final rune in text.runes) {
      _send(
        OfficeKey(type: OfficeKeyEventType.down, charCode: rune, keyCode: 0),
      );
      _send(OfficeKey(type: OfficeKeyEventType.up, charCode: rune, keyCode: 0));
    }
    _markInput();
  }

  /// Composing text of an input method (shown inline by LibreOffice).
  void compose(String text) {
    if (!_editable) return;
    _send(OfficeTextInput(type: OfficeTextInputType.input, text: text));
    _markInput();
  }

  /// Commits an input method's [text]: as the composition, then its end.
  /// LibreOffice 26.8.3.1 inserts the composition at `end` and ignores the
  /// text sent with `end` itself, so text committed without a composition
  /// first would be lost.
  void commitText(String text) {
    if (!_editable) return;
    if (text.isNotEmpty) {
      _send(OfficeTextInput(type: OfficeTextInputType.input, text: text));
    }
    _send(OfficeTextInput(type: OfficeTextInputType.end, text: text));
    _markInput();
  }

  /// A mouse event at [x], [y] twips. A hover move is not input.
  void mouse(
    OfficeMouseEventType type,
    int x,
    int y, {
    int count = 1,
    int buttons = 1,
    int modifiers = 0,
  }) {
    if (!_live) return;
    _send(
      OfficeMouse(
        type: type,
        x: x,
        y: y,
        count: count,
        buttons: buttons,
        modifiers: modifiers,
      ),
    );
    if (type != OfficeMouseEventType.move || buttons != 0) _markInput();
  }

  /// Drags a text selection handle (`type` 0 start, 1 end) or a shape's
  /// frame to [x], [y] twips.
  void dragSelection(OfficeSelectionKind kind, int type, int x, int y) {
    if (!_live) return;
    if (kind == OfficeSelectionKind.graphic && isReadOnly) return;
    _send(OfficeSelection(kind: kind, type: type, x: x, y: y));
    _markInput();
  }

  final _unoPending = <String, _UnoPending>{};

  /// Runs a UNO command (`.uno:Bold`), with JSON [args].
  void uno(String command, [String args = '']) {
    if (!_live) return;
    if (isReadOnly && !_readOnlyCommands.contains(command)) return;
    _unoPending[command] = _UnoPending();
    _send(OfficeUno(id: _nextId++, command: command, args: args));
    _markInput();
  }

  static const _readOnlyCommands = {
    '.uno:SearchDialog',
    '.uno:WordCountDialog',
    '.uno:ControlCodes',
    '.uno:BrowseView',
    '.uno:PrintLayout',
    '.uno:ToggleSheetGrid',
    '.uno:ViewRowColumnHeaders',
    '.uno:Copy',
    '.uno:SelectAll',
    '.uno:ZoomPlus',
    '.uno:ZoomMinus',
  };

  void _onUnoResult(String payload) {
    final result = parseUnoCommandResult(payload);
    if (result == null) return;
    final command = result.command.startsWith('.uno:')
        ? result.command
        : '.uno:${result.command}';
    final pending = _unoPending.remove(command);
    if (result.success || pending == null) return;
    // Some commands report false although they take effect, as the
    // following STATE_CHANGED shows: the state decides (WD, the ribbon).
    Timer(const Duration(milliseconds: 300), () {
      if (pending.stateSeen) return;
      _notice(
        'LibreOffice could not run ${command.substring(5)}.',
        kind: 'warning',
      );
    });
  }

  final _clipboardWaiters = <int, Completer<Map<String, String>>>{};

  /// The selection as text and HTML (`copy` → `clipboard`).
  Future<Map<String, String>> copySelection() {
    if (!_live) return Future.value(const {});
    final id = _nextId++;
    final completer = Completer<Map<String, String>>();
    _clipboardWaiters[id] = completer;
    _send(
      OfficeCopy(
        id: id,
        mimeTypes: const ['text/plain;charset=utf-8', 'text/html'],
      ),
    );
    return completer.future;
  }

  /// Copies, then cuts the selection.
  Future<Map<String, String>> cutSelection() async {
    final data = await copySelection();
    if (_editable) uno('.uno:Cut');
    return data;
  }

  /// Pastes [data] of [mimeType].
  void paste(String mimeType, String data) {
    if (!_editable || data.isEmpty) return;
    _send(OfficePaste(mimeType: mimeType, data: data));
    _markInput();
  }

  final _valueWaiters = <int, Completer<String>>{};

  /// `getCommandValues(command)` as JSON.
  Future<String> commandValues(String command) {
    if (!_live) return Future.error('not open');
    final id = _nextId++;
    final completer = Completer<String>();
    _valueWaiters[id] = completer;
    _send(OfficeCommandValues(id: id, command: command));
    return completer.future;
  }

  // ------------------------------------------------------------- history

  // ------------------------------------------------------------ dialogs

  final _windows = <int, TomOfficeWindow>{};
  final _windowPaints = <int, int>{}; // paint id → window id
  final _windowPainting = <int>{};
  final _windowDirty = <int>{};
  int _jsDialogs = 0;

  /// LibreOffice's open windows (dialogs, a combo box's list, tooltips),
  /// in the order they opened.
  List<TomOfficeWindow> get windows => List.unmodifiable(_windows.values);

  /// Counts window changes and paints: the dialog layer repaints on it.
  final ValueNotifier<int> windowRevision = ValueNotifier(0);

  /// How dialogs are shown (DPLH-4); a tab starts with windows.
  TomOfficeDialogMode get dialogMode => _dialogMode;
  TomOfficeDialogMode _dialogMode = TomOfficeDialogMode.window;

  /// Whether this LibreOffice offers JSON dialogs: `null` until asked,
  /// `false` once the helper refused them (LibreOffice's desktop build has
  /// none, spike item 8).
  bool? get jsonDialogsAvailable => _jsonDialogs;
  bool? _jsonDialogs;

  /// The `JSDIALOG` messages received (none from the desktop build).
  int get jsDialogCount => _jsDialogs;

  /// *Dialogs: LibreOffice windows / Forge forms*: sends `dialogMode`. The
  /// helper refuses JSON where LibreOffice has none; the tab then stays with
  /// windows and says so.
  void setDialogMode(TomOfficeDialogMode mode) {
    if (mode == _dialogMode) return;
    officeTrail('dialog mode ${mode.name}');
    _dialogMode = mode;
    _send(
      OfficeDialogModeMessage(
        mode: mode == TomOfficeDialogMode.json
            ? OfficeDialogMode.json
            : OfficeDialogMode.window,
      ),
    );
    notifyListeners();
  }

  void _onWindowOpened(OfficeWindowOpened w) {
    _lastWindow = w;
    if (_dialogMode == TomOfficeDialogMode.json) {
      officeTrail('dialog ${w.windowId} came as a window in JSON mode');
    }
    officeTrail('window ${w.windowId} ${w.kind} ${w.width}x${w.height}');
    _windows[w.windowId] = TomOfficeWindow._(
      id: w.windowId,
      kind: w.kind,
      title: w.title,
      width: w.width,
      height: w.height,
      parentId: w.parentId,
      x: w.x ?? 0,
      y: w.y ?? 0,
    );
    _paintWindow(w.windowId);
    windowRevision.value++;
    notifyListeners();
  }

  void _onWindowChanged(OfficeWindowChanged c) {
    final w = _windows[c.windowId];
    if (w == null) return;
    w.changes++;
    switch (c.action) {
      case 'invalidate':
        _paintWindow(w.id);
      case 'size_changed':
        if (c.width != null && c.height != null) {
          w.width = c.width!;
          w.height = c.height!;
        }
        _paintWindow(w.id);
      case 'title_changed':
        w.title = c.title ?? w.title;
      case 'cursor_invalidate':
        final r = c.rectangle;
        w.cursor = r == null ? null : OfficeTwipRect(r.x, r.y, r.w, r.h);
      case 'cursor_visible':
        w.cursorVisible = c.visible ?? w.cursorVisible;
      case 'show':
        w.visible = true;
        _paintWindow(w.id);
      case 'hide':
        w.visible = false;
      case 'close':
        officeTrail('window ${w.id} closed');
        _windows.remove(w.id)?.image?.dispose();
        notifyListeners();
      default:
        break;
    }
    windowRevision.value++;
  }

  /// Asks for [windowId]'s pixels; a paint asked while one runs is made
  /// once that one has arrived.
  void _paintWindow(int windowId) {
    final w = _windows[windowId];
    if (w == null || w.width <= 0 || w.height <= 0) return;
    if (_windowPainting.contains(windowId)) {
      _windowDirty.add(windowId);
      return;
    }
    _windowPainting.add(windowId);
    final id = _nextId++;
    _windowPaints[id] = windowId;
    // At scale 1: the helper's buffer is width × height pixels.
    _send(
      OfficePaintWindow(
        id: id,
        windowId: windowId,
        x: 0,
        y: 0,
        w: w.width,
        h: w.height,
        dpiScale: 1,
      ),
    );
  }

  Future<void> _onWindowPixels(OfficeWindowPixels p) async {
    final windowId = _windowPaints.remove(p.id) ?? p.windowId;
    _windowPainting.remove(windowId);
    final w = _windows[windowId];
    if (w != null && p.pixels.length >= p.w * p.h * 4) {
      try {
        final image = await _decoder(p.pixels, p.w, p.h, p.format);
        final current = _windows[windowId];
        if (current == null) {
          image.dispose();
        } else {
          current.image?.dispose();
          current.image = image;
          windowRevision.value++;
        }
      } catch (e, s) {
        officeReport(e, s, 'decoding window $windowId');
      }
    }
    if (_windowDirty.remove(windowId)) _paintWindow(windowId);
  }

  /// A mouse event at [x], [y] pixels in window [windowId].
  void windowMouse(
    int windowId,
    OfficeMouseEventType type,
    int x,
    int y, {
    int count = 1,
    int buttons = 1,
    int modifiers = 0,
  }) {
    if (!_windows.containsKey(windowId)) return;
    _send(
      OfficeWindowMouse(
        windowId: windowId,
        type: type,
        x: x,
        y: y,
        count: count,
        buttons: buttons,
        modifiers: modifiers,
      ),
    );
  }

  /// A key without text ([keyCode] with its VCL modifier bits) in window
  /// [windowId], down and up.
  void windowKey(int windowId, int keyCode, {int charCode = 0}) {
    if (!_windows.containsKey(windowId)) return;
    for (final type in OfficeKeyEventType.values) {
      _send(
        OfficeWindowKey(
          windowId: windowId,
          type: type,
          charCode: charCode,
          keyCode: keyCode,
        ),
      );
    }
  }

  /// Text typed into window [windowId]: a key event per character, as
  /// the first spike typed into dialogs (a dialog's field takes no
  /// `windowTextInput` in LibreOffice 26.8.3.1).
  void windowText(int windowId, String text) {
    if (!_windows.containsKey(windowId) || text.isEmpty) return;
    for (final rune in text.runes) {
      windowKey(windowId, 0, charCode: rune);
    }
  }

  /// Closes window [windowId] (its title bar's close button).
  void closeWindow(int windowId) {
    if (!_windows.containsKey(windowId)) return;
    _send(OfficeWindowClose(windowId: windowId));
  }

  // ------------------------------------------------------------ ribbon

  /// The last window LibreOffice opened (a dialog), as the helper sent it.
  OfficeWindowOpened? get lastWindow => _lastWindow;
  OfficeWindowOpened? _lastWindow;

  /// The `STATE_CHANGED` value of [command], or `null` when none came.
  String? stateOf(String command) => _states[command];

  /// Whether [command] is enabled: anything but `disabled` (a command that
  /// never sends a state is always enabled).
  bool isEnabled(String command) => _states[command] != 'disabled';

  /// Whether a toggle [command] is on (`true`).
  bool isChecked(String command) => _states[command] == 'true';

  final _recent = <int>[];

  /// The colours chosen recently, newest first (at most ten).
  List<int> get recentColours => List.unmodifiable(_recent);

  final _lastColours = <String, int>{};

  /// The colour [command]'s split button applies, or [fallback].
  int lastColour(String command, int fallback) =>
      _lastColours[command] ?? fallback;

  /// Applies [colour] (RGB; −1 is *Automatic*) with [command] and its
  /// `long` [argument], and remembers it.
  void applyColour(String command, String argument, int colour) {
    _lastColours[command] = colour;
    if (colour >= 0) {
      _recent
        ..remove(colour)
        ..insert(0, colour);
      if (_recent.length > 10) _recent.removeLast();
    }
    uno(command, '{"$argument":{"type":"long","value":$colour}}');
    notifyListeners();
  }

  Map<String, List<String>>? _fonts;
  Map<String, List<String>>? _styleFamilies;

  /// The fonts and each font's sizes (`getCommandValues('.uno:CharFontName')`),
  /// asked once per document.
  Future<Map<String, List<String>>> fonts() async =>
      _fonts ??= await _valuesMap('.uno:CharFontName');

  /// The style families and their styles
  /// (`getCommandValues('.uno:StyleApply')`).
  Future<Map<String, List<String>>> styles() async =>
      _styleFamilies ??= await _valuesMap('.uno:StyleApply');

  Future<Map<String, List<String>>> _valuesMap(String command) async {
    try {
      final data = jsonDecode(await commandValues(command));
      final values = data is Map ? data['commandValues'] : null;
      if (values is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in values.entries)
          if (value is List) '$key': [for (final v in value) '$v'],
      };
    } catch (e) {
      officeTrail('values $command: $e');
      return const {};
    }
  }

  /// Opens LibreOffice's Find & Replace (Cmd+F).
  void find() => uno('.uno:SearchDialog');

  /// *Insert image*: the host's file picker, then `.uno:InsertGraphic`.
  Future<void> insertImage() async {
    if (!acceptsEdits) return;
    final path = await host.pickImage();
    if (path == null || path.isEmpty) return;
    uno(
      '.uno:InsertGraphic',
      '{"FileName":{"type":"string","value":"${Uri.file(path)}"}}',
    );
  }

  /// LibreOffice's undo.
  void undo() {
    if (_canUndo && _editable) uno('.uno:Undo');
  }

  /// LibreOffice's redo.
  void redo() {
    if (_canRedo && _editable) uno('.uno:Redo');
  }

  // -------------------------------------------------------------- saving

  final _saveWaiters = <int, Completer<OfficeSaved>>{};

  Future<OfficeSaved> _saveTo(String target) {
    final id = _nextId++;
    final completer = Completer<OfficeSaved>();
    _saveWaiters[id] = completer;
    officeTrail('save #$id: writing the temporary file');
    _send(
      OfficeSave(
        id: id,
        targetPath: target,
        format: '',
        filterOptions: isCsv ? kCsvExportOptions : '',
      ),
    );
    return completer.future;
  }

  /// Saves: LibreOffice writes a temporary file beside the original, which
  /// replaces it while the file on disk is the one read. A changed file is
  /// a [conflict] instead.
  Future<TomOfficeSaveOutcome> save() => _save(force: false);

  Future<TomOfficeSaveOutcome> _save({required bool force}) async {
    if (_state != TomOfficeEditorState.open) {
      return TomOfficeSaveOutcome.refused;
    }
    if (isReadOnly) {
      _notice('${host.name} is read-only. Use Save as copy.', kind: 'warning');
      return TomOfficeSaveOutcome.refused;
    }
    _setState(TomOfficeEditorState.saving);
    try {
      final leftovers = await host.files.removeTemporaryFiles(host.filePath);
      if (leftovers.isNotEmpty) {
        officeTrail(
          'save: removed ${leftovers.length} leftover temporary file(s)',
        );
      }
      final temporary = await host.files.temporaryTarget(host.filePath);
      final saved = await _saveTo(temporary);
      if (!saved.ok) {
        officeTrail('save failed');
        _backToOpen();
        _notice(
          '${host.name} could not be saved: ${saved.error ?? 'unknown error'}',
          kind: 'error',
        );
        return TomOfficeSaveOutcome.failed;
      }
      officeTrail('save: replacing the original${force ? ' (keep mine)' : ''}');
      final result = await host.files.replace(
        host.filePath,
        temporary,
        _fileDeleted ? null : _revision,
        force: force,
      );
      if (!result.replaced) {
        officeTrail('save: conflict');
        _conflict = TomOfficeConflict(
          temporary: temporary,
          deleted: result.revision == null,
        );
        _backToOpen();
        return TomOfficeSaveOutcome.conflict;
      }
      _revision = result.revision;
      _conflict = null;
      _fileDeleted = false;
      final wasDirty = _dirty;
      _dirty = false;
      _backToOpen();
      if (wasDirty) host.historyChanged();
      officeTrail('save: done');
      return TomOfficeSaveOutcome.saved;
    } catch (e, s) {
      officeReport(e, s, 'saving');
      _backToOpen();
      _notice('${host.name} could not be saved: $e', kind: 'error');
      return TomOfficeSaveOutcome.failed;
    }
  }

  void _backToOpen() {
    if (_state == TomOfficeEditorState.saving) {
      _setState(TomOfficeEditorState.open);
    } else {
      notifyListeners();
    }
  }

  /// *Keep mine*: replaces the file on disk with this document, whatever is
  /// there now.
  Future<TomOfficeSaveOutcome> keepMine() async {
    final c = _conflict;
    if (c == null) return TomOfficeSaveOutcome.refused;
    final temporary = c.temporary;
    if (temporary == null) return _save(force: true);
    try {
      final result = await host.files.replace(
        host.filePath,
        temporary,
        null,
        force: true,
      );
      _revision = result.revision;
      _conflict = null;
      _fileDeleted = false;
      _dirty = false;
      notifyListeners();
      host.historyChanged();
      return TomOfficeSaveOutcome.saved;
    } catch (e, s) {
      officeReport(e, s, 'keep mine');
      _notice('${host.name} could not be saved: $e', kind: 'error');
      return TomOfficeSaveOutcome.failed;
    }
  }

  /// *Take theirs*: reopens the file from disk; the edits are lost.
  Future<void> takeTheirs() async {
    final temporary = _conflict?.temporary;
    _conflict = null;
    if (temporary != null) {
      await host.files.removeTemporaryFiles(host.filePath);
    }
    await _restart();
  }

  /// *Save as copy*: writes the document to `<name> (copy).<ext>` beside
  /// the file and returns the copy's path (`null` when it failed). After a
  /// conflict the kept temporary file becomes the copy. A password-protected
  /// document's copy is written by LibreOffice with its password.
  Future<String?> saveAsCopy() async {
    if (!_live) return null;
    try {
      var temporary = _conflict?.temporary;
      if (temporary == null) {
        temporary = await host.files.temporaryTarget(host.filePath);
        final saved = await _saveTo(temporary);
        if (!saved.ok) {
          _notice(
            'The copy could not be written: ${saved.error ?? 'unknown error'}',
            kind: 'error',
          );
          return null;
        }
      }
      final copy = await host.files.keepAsCopy(temporary, host.filePath);
      officeTrail('save as copy: written');
      if (_conflict != null) {
        _conflict = TomOfficeConflict(deleted: _conflict!.deleted);
      }
      notifyListeners();
      _notice('Saved a copy as ${copy.split('/').last}.');
      return copy;
    } catch (e, s) {
      officeReport(e, s, 'save as copy');
      _notice('The copy could not be written: $e', kind: 'error');
      return null;
    }
  }

  // ---------------------------------------------------- external changes

  /// Compares the file on disk with the revision read (the host calls it
  /// when the window regains focus). A clean document is reopened; a dirty
  /// one shows the conflict at once; a deleted file is marked, and the next
  /// save recreates it.
  Future<void> checkExternal() async {
    if (_state != TomOfficeEditorState.open) return;
    final now = await host.files.revisionOf(host.filePath);
    final read = _revision;
    if (now == null) {
      if (!_fileDeleted) {
        officeTrail('external: deleted');
        _fileDeleted = true;
        notifyListeners();
      }
      return;
    }
    if (_fileDeleted) {
      _fileDeleted = false;
      notifyListeners();
    }
    if (read != null && now.sameContent(read)) return;
    if (_dirty) {
      officeTrail('external: changed, document dirty');
      _conflict = const TomOfficeConflict();
      notifyListeners();
      return;
    }
    officeTrail('external: changed, reopening');
    _notice('${host.name} changed on disk and was reloaded.');
    await _restart();
  }

  // ----------------------------------------------------------- lifecycle

  Future<void> _restart() async {
    final channel = _channel;
    _closing = true;
    _stopPing();
    if (channel != null) await channel.close();
    _channel = null;
    _closing = false;
    await open();
  }

  /// Reopens after the helper stopped, or after a failure.
  Future<void> reopen() => _restart();

  /// Ends the helper and the document.
  Future<void> close() async {
    _closing = true;
    _stopPing();
    _inputTimer?.cancel();
    final channel = _channel;
    _channel = null;
    _setState(TomOfficeEditorState.closed);
    if (channel != null) await channel.close();
    tiles.clear();
    for (final w in _windows.values) {
      w.image?.dispose();
    }
    _windows.clear();
  }

  @override
  void dispose() {
    if (_state != TomOfficeEditorState.closed) unawaited(close());
    _inputTimer?.cancel();
    _stopPing();
    unawaited(_notices.close());
    tileRevision.dispose();
    windowRevision.dispose();
    super.dispose();
  }

  /// The reason the helper stopped as the view words it.
  String get stopDescription {
    final hang = _hangReason;
    if (hang != null) return hang;
    return _stopReason ?? 'unknown';
  }
}

final class _UnoPending {
  bool stateSeen = false;
}

/// One header of a spreadsheet's rows or columns: its label and where it
/// ends, in document twips.
@immutable
final class TomOfficeSheetHeader {
  /// A header from its parts.
  const TomOfficeSheetHeader(this.text, this.endTwips);

  /// `1`, `A`.
  final String text;

  /// Where the row or column ends.
  final double endTwips;
}

/// The headers `.uno:ViewRowColumnHeaders` gives for an area.
@immutable
final class TomOfficeSheetHeaders {
  /// Headers from their parts. [rowStart] and [columnStart] are where the
  /// first row and column begin.
  const TomOfficeSheetHeaders({
    required this.rows,
    required this.columns,
    this.rowStart = 0,
    this.columnStart = 0,
  });

  /// The rows, top to bottom.
  final List<TomOfficeSheetHeader> rows;

  /// The columns, left to right.
  final List<TomOfficeSheetHeader> columns;

  /// Where the first row begins, in twips.
  final double rowStart;

  /// Where the first column begins, in twips.
  final double columnStart;

  /// Twips per header pixel at 100 %, as LibreOffice 26.8.3.1 reports the
  /// sizes: Calc's screen scale (`nScreenPPTX` / `nScreenPPTY`), measured on
  /// `sheet.xlsx` (column A 2547 twips = 165 px, a row 284 twips = 19 px).
  static const columnTwipsPerPixel = 15.4375;

  /// See [columnTwipsPerPixel].
  static const rowTwipsPerPixel = 15.0;

  /// Parses the JSON: `rows` and `columns`, each a list of `{text, size}`
  /// whose `size` is where the entry ends, in pixels at the view's [zoom];
  /// the first entry is the start.
  static TomOfficeSheetHeaders? parse(String json, {required int zoom}) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (data is! Map || data['rows'] is! List || data['columns'] is! List) {
      return null;
    }
    final factor = 100 / zoom;
    List<TomOfficeSheetHeader> read(List<Object?> list, double twips) => [
      for (final e in list.skip(1))
        if (e is Map)
          TomOfficeSheetHeader(
            '${e['text']}',
            (num.tryParse('${e['size']}') ?? 0) * twips * factor,
          ),
    ];
    double start(List<Object?> list, double twips) {
      final first = list.isEmpty ? null : list.first;
      if (first is! Map) return 0;
      return (num.tryParse('${first['size']}') ?? 0) * twips * factor;
    }

    final rows = data['rows'] as List;
    final columns = data['columns'] as List;
    return TomOfficeSheetHeaders(
      rows: read(rows, rowTwipsPerPixel),
      columns: read(columns, columnTwipsPerPixel),
      rowStart: start(rows, rowTwipsPerPixel),
      columnStart: start(columns, columnTwipsPerPixel),
    );
  }
}

/// How the editor shows LibreOffice's dialogs (DPLH-4).
enum TomOfficeDialogMode {
  /// LibreOffice's own windows, painted (`paintWindow`).
  window,

  /// Flutter forms built from `JSDIALOG` (where LibreOffice offers them).
  json,
}

/// One LibreOffice window: a dialog, a combo box's list (`child`), a
/// tooltip.
final class TomOfficeWindow {
  TomOfficeWindow._({
    required this.id,
    required this.kind,
    required this.title,
    required this.width,
    required this.height,
    required this.parentId,
    required this.x,
    required this.y,
  });

  /// Its id.
  final int id;

  /// `dialog`, `child`, `tooltip`, ….
  final String kind;

  /// Its title.
  String title;

  /// Its width in pixels.
  int width;

  /// Its height in pixels.
  int height;

  /// The window it belongs to (a child's parent).
  final int? parentId;

  /// A child's position in its parent.
  final int x;

  /// See [x].
  final int y;

  /// The last painted pixels.
  ui.Image? image;

  /// Whether it is shown (`hide` / `show`).
  bool visible = true;

  /// The text cursor in it, in pixels (`cursor_invalidate`).
  OfficeTwipRect? cursor;

  /// Whether the cursor shows (`cursor_visible`).
  bool cursorVisible = false;

  /// How many `windowChanged` messages it had: LibreOffice's answers to
  /// the input it took.
  int changes = 0;

  /// Whether it is a dialog (modal: the document waits behind it).
  bool get isDialog => kind == 'dialog';
}
