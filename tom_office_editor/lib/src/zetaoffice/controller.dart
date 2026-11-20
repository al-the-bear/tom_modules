// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tom_file_session/tom_file_session.dart';

import '../controller.dart' show TomOfficeNotice, TomOfficeSaveOutcome;
import '../host.dart';
import 'files.dart';
import 'trail.dart';

/// ZetaOffice's error [message] in words a user understands: the known
/// failures named, anything else as ZetaOffice said it.
String zetaOfficeReason(String message) {
  if (message.contains('Maximum call stack size exceeded')) {
    return 'ZetaOffice ran out of stack space on this document, a limit of '
        'the web engine it runs in. The LibreOffice editor (Open With) '
        'handles it.';
  }
  final text = message.trim();
  return text.isEmpty
      ? 'ZetaOffice gave no reason.'
      : 'ZetaOffice reported: ${text.endsWith('.') ? text : '$text.'}';
}

/// Where a ZetaOffice tab is.
enum TomZetaOfficeState {
  /// The cache is being checked.
  checking,

  /// The files are not cached (or damaged): the tab offers the download.
  needsDownload,

  /// The files are downloading.
  downloading,

  /// ZetaOffice is starting in the webview (up to three minutes).
  starting,

  /// The document is shown.
  open,

  /// A save runs.
  saving,

  /// Another ZetaOffice tab is open: one at a time.
  busy,

  /// The webview's content process was killed: the document is gone.
  processGone,

  /// Something failed ([TomZetaOfficeController.error]).
  failed,

  /// Closed.
  closed,
}

/// What a ZetaOffice tab drives: the download, the start, saving, undo,
/// redo and the dirty state, through the same host as the native editor
/// (`TomOfficeEditorHost`: the file, its access, notices, history changes).
class TomZetaOfficeController extends ChangeNotifier {
  /// A controller for [host]'s document, with the cached [files], served by
  /// [serving]. [startTimeout] is how long the start may take (WebKit's
  /// WebAssembly compilation stalled for about a minute in the spike);
  /// [saveTimeout] how long a save may.
  TomZetaOfficeController({
    required this.host,
    required this.files,
    required this.serving,
    this.startTimeout = const Duration(minutes: 3),
    this.saveTimeout = const Duration(minutes: 2),
  });

  /// The application.
  final TomOfficeEditorHost host;

  /// The cached ZetaOffice files.
  final TomZetaOfficeFiles files;

  /// The tab's local server.
  final TomZetaOfficeServing serving;

  /// How long ZetaOffice may take to show the document.
  final Duration startTimeout;

  /// How long a save may take.
  final Duration saveTimeout;

  /// The open ZetaOffice tab of the process: one at a time.
  static TomZetaOfficeController? _active;

  TomZetaOfficeState _state = TomZetaOfficeState.checking;

  /// Where the tab is.
  TomZetaOfficeState get state => _state;

  /// The cache's state when checked.
  TomZetaOfficeCacheStatus? get cacheStatus => _cache;
  TomZetaOfficeCacheStatus? _cache;

  /// Whether the cache was ready without a download (a second open).
  bool get cacheReused => _cacheReused;
  bool _cacheReused = false;

  /// The bytes the download fetches.
  int get downloadSize => _downloadSize;
  int _downloadSize = kZetaOfficeDownloadBytes;

  /// Bytes received while downloading.
  int get downloadReceived => _received;
  int _received = 0;

  /// The page's last status line (Emscripten's progress, the start's steps).
  String get statusText => _status;
  String _status = '';

  /// When the start began.
  DateTime? get startedAt => _startedAt;
  DateTime? _startedAt;

  /// What went wrong ([TomZetaOfficeState.failed]).
  String? get error => _error;
  String? _error;

  /// `text`, `spreadsheet` or `presentation`, once loaded.
  String? get kind => _kind;
  String? _kind;

  /// ZetaOffice's product name and version, once loaded.
  String? get product => _product;
  String? _product;

  /// Whether the document has changes not saved to the file: the
  /// document's modified flag, kept set after a save that did not reach the
  /// file.
  bool get isDirty => _dirty || _unsaved;
  bool _dirty = false;
  bool _unsaved = false;

  /// ZetaOffice's undo is possible.
  bool get canUndo => _canUndo;
  bool _canUndo = false;

  /// ZetaOffice's redo is possible.
  bool get canRedo => _canRedo;
  bool _canRedo = false;

  /// The file changed on disk: a save did not overwrite it.
  bool get conflict => _conflict;
  bool _conflict = false;

  /// The page's address, once serving.
  Uri? get pageUri => _page;
  Uri? _page;

  final _notices = StreamController<TomOfficeNotice>.broadcast();

  /// Notices to show; the view hands them to the host.
  Stream<TomOfficeNotice> get notices => _notices.stream;

  TomZetaOfficeChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _sub;
  TomFileRevision? _revision;
  Timer? _startTimer;
  Completer<TomOfficeSaveOutcome>? _saving;
  Completer<String?>? _copying;
  Completer<String>? _reading;
  TomOfficeSaveOutcome? _written;
  String? _copyPath;

  void _set(TomZetaOfficeState next) {
    if (_state == next) return;
    zetaTrail('state ${_state.name} -> ${next.name}');
    _state = next;
    notifyListeners();
  }

  void _notice(String message, {String kind = 'info'}) {
    if (!_notices.isClosed) _notices.add(TomOfficeNotice(message, kind: kind));
  }

  void _fail(String message) {
    _error = message;
    _startTimer?.cancel();
    _set(TomZetaOfficeState.failed);
  }

  // ---------------------------------------------------------- the files

  /// Checks the cache: ready starts ZetaOffice, otherwise the tab offers the
  /// download with its size.
  Future<void> prepare() async {
    final other = _active;
    if (other != null &&
        other != this &&
        other._state != TomZetaOfficeState.closed) {
      _set(TomZetaOfficeState.busy);
      return;
    }
    _set(TomZetaOfficeState.checking);
    try {
      _cache = await files.status();
      zetaTrail('cache ${_cache!.state.name} ${_cache!.reason ?? ''}');
      if (_cache!.state == TomZetaOfficeCacheState.ready) {
        _cacheReused = true;
        await start();
        return;
      }
      _downloadSize = await files.downloadSize();
      _set(TomZetaOfficeState.needsDownload);
    } catch (e, s) {
      zetaReport(e, s, 'checking the ZetaOffice cache');
      _fail('The ZetaOffice files could not be checked: $e');
    }
  }

  /// Downloads the files after the user confirmed, then starts.
  Future<void> download() async {
    if (_state != TomZetaOfficeState.needsDownload) return;
    _received = 0;
    _set(TomZetaOfficeState.downloading);
    try {
      await files.download(
        progress: (received, total) {
          _received = received;
          _downloadSize = total;
          notifyListeners();
        },
      );
      _cache = await files.status();
      if (_cache!.state != TomZetaOfficeCacheState.ready) {
        _fail('The download is incomplete: ${_cache!.reason}');
        return;
      }
      await start();
    } catch (e, s) {
      zetaReport(e, s, 'downloading ZetaOffice');
      _fail('ZetaOffice could not be downloaded: $e');
    }
  }

  // ---------------------------------------------------------- the start

  /// Serves the page and the document and loads the page into the webview
  /// once it is attached.
  Future<void> start() async {
    final other = _active;
    if (other != null &&
        other != this &&
        other._state != TomZetaOfficeState.closed) {
      _set(TomZetaOfficeState.busy);
      return;
    }
    _active = this;
    _error = null;
    _status = '';
    _conflict = false;
    _unsaved = false;
    _dirty = _canUndo = _canRedo = false;
    try {
      _revision = await host.files.revisionOf(host.filePath);
      if (_revision == null) {
        _fail('${host.name} does not exist.');
        return;
      }
      _page = await serving.start(
        documentPath: host.filePath,
        name: host.name,
        files: files,
        onSave: _receiveSave,
        onSaveCopy: _receiveCopy,
      );
      _startedAt = DateTime.now();
      _startTimer?.cancel();
      _startTimer = Timer(startTimeout, () {
        if (_state == TomZetaOfficeState.starting) {
          _fail(
            'ZetaOffice did not show the document in '
            '${startTimeout.inMinutes} minutes.',
          );
        }
      });
      _set(TomZetaOfficeState.starting);
      final channel = _channel;
      if (channel != null) await channel.load(_page!);
    } catch (e, s) {
      zetaReport(e, s, 'starting ZetaOffice');
      _fail('ZetaOffice could not be started: $e');
    }
  }

  /// Attaches the webview's channel; loads the page when it is served.
  Future<void> attach(TomZetaOfficeChannel channel) async {
    unawaited(_sub?.cancel());
    _channel = channel;
    _sub = channel.messages.listen(_onMessage);
    final page = _page;
    if (page != null && _state == TomZetaOfficeState.starting) {
      await channel.load(page);
    }
  }

  /// Lets go of [channel] when it is the attached one (its webview left the
  /// tree): nothing is sent to it again, and the next start waits for the
  /// channel [attach] gives.
  void detach(TomZetaOfficeChannel channel) {
    if (!identical(_channel, channel)) return;
    unawaited(_sub?.cancel());
    _sub = null;
    _channel = null;
  }

  void _onMessage(Map<String, Object?> m) {
    if (!_pageMessages.isClosed) _pageMessages.add(m);
    final type = m['type'];
    if (type != 'trail' && type != 'status') zetaTrail('<- $type');
    switch (type) {
      case 'status':
        _status = '${m['text'] ?? ''}';
        notifyListeners();
      case 'trail':
        zetaTrail('page: ${m['text']}');
      case 'ready':
        _status = 'ZetaOffice is running';
        notifyListeners();
      case 'loaded':
        _kind = m['kind'] as String?;
        _product = m['product'] as String?;
        _startTimer?.cancel();
        final elapsed = DateTime.now().difference(_startedAt ?? DateTime.now());
        zetaTrail('loaded $_kind in ${elapsed.inMilliseconds} ms ($_product)');
        if (_product != null && _product!.trim().isNotEmpty) {
          unawaited(files.recordProduct(_product!.trim()));
        }
        _set(TomZetaOfficeState.open);
      case 'modified':
        final dirty = m['value'] == true;
        if (dirty) _unsaved = false;
        if (dirty != _dirty) {
          _dirty = dirty;
          notifyListeners();
          host.historyChanged();
        }
      case 'history':
        final undo = m['canUndo'] == true;
        final redo = m['canRedo'] == true;
        if (undo != _canUndo || redo != _canRedo) {
          _canUndo = undo;
          _canRedo = redo;
          notifyListeners();
          host.historyChanged();
        }
      case 'saved':
        _onSaved(m);
      case 'text':
        _reading?.complete('${m['text'] ?? ''}');
        _reading = null;
      case 'processGone':
        // Not the page's: the channel says the webview's content process
        // ended (the system killed it, or it crashed).
        contentProcessGone();
      case 'error':
        final code = '${m['code'] ?? ''}';
        final message = '${m['message'] ?? ''}';
        zetaTrail('page error $code');
        if (_state == TomZetaOfficeState.starting) {
          _fail(switch (code) {
            'notIsolated' =>
              'ZetaOffice needs a cross-origin isolated page: $message',
            // The document itself: as the LibreOfficeKit route says it.
            // The page's own reasons are readable; ZetaOffice's stack
            // failure is put in words.
            'loadFailed' =>
              '${host.name} could not be opened: '
                  '${message.contains('Maximum call stack size exceeded') ? zetaOfficeReason(message) : message}',
            _ => 'ZetaOffice could not start: $message',
          });
        } else {
          _notice(message, kind: 'error');
        }
    }
  }

  // ------------------------------------------------------------- saving

  /// Saves: ZetaOffice stores the document in place in its own format
  /// (`store()`, which clears the modified flag), the page posts the bytes,
  /// and they replace the file while it is the one read. A failed or
  /// timed-out save is reported and leaves the document dirty.
  Future<TomOfficeSaveOutcome> save() async {
    if (_state != TomZetaOfficeState.open) return TomOfficeSaveOutcome.refused;
    final channel = _channel;
    if (channel == null) return TomOfficeSaveOutcome.refused;
    _set(TomZetaOfficeState.saving);
    final done = _saving = Completer<TomOfficeSaveOutcome>();
    _written = null;
    zetaTrail('save: store()');
    await channel.call('save');
    final outcome = await done.future.timeout(
      saveTimeout,
      onTimeout: () {
        zetaTrail('save timed out');
        _notice(
          '${host.name} could not be saved: ZetaOffice did not answer in '
          '${saveTimeout.inSeconds} s.',
          kind: 'error',
        );
        return TomOfficeSaveOutcome.failed;
      },
    );
    _saving = null;
    if (outcome != TomOfficeSaveOutcome.saved) {
      // store() may have cleared the flag: the file does not have it.
      _unsaved = true;
      host.historyChanged();
    }
    if (_state == TomZetaOfficeState.saving) _set(TomZetaOfficeState.open);
    notifyListeners();
    return outcome;
  }

  Future<void> _receiveSave(Uint8List bytes) async {
    zetaTrail('save: ${bytes.length} bytes received');
    try {
      final result = await host.files.save(host.filePath, bytes, _revision);
      if (result.replaced) {
        _revision = result.revision;
        _conflict = false;
        _written = TomOfficeSaveOutcome.saved;
      } else {
        _conflict = true;
        _written = TomOfficeSaveOutcome.conflict;
      }
    } catch (e, s) {
      zetaReport(e, s, 'writing the saved bytes');
      _written = TomOfficeSaveOutcome.failed;
      rethrow;
    }
  }

  void _onSaved(Map<String, Object?> m) {
    final copy = m['copy'] == true;
    final ok = m['ok'] == true;
    if (copy) {
      final exporting = _exporting;
      if (exporting != null && !ok) {
        _exporting = null;
        _exportErrorForTest = '${m['error'] ?? 'no reason given'}';
        exporting.complete(null);
        return;
      }
      if (exporting != null) return; // the bytes complete it
      final waiting = _copying;
      _copying = null;
      if (!ok) {
        _notice(
          'The copy could not be written: '
          '${zetaOfficeReason('${m['error']}')}',
          kind: 'error',
        );
      }
      waiting?.complete(ok ? _copyPath : null);
      return;
    }
    final waiting = _saving;
    if (waiting == null || waiting.isCompleted) return;
    if (!ok) {
      zetaTrail('save failed in ZetaOffice');
      _notice(
        '${host.name} could not be saved: '
        '${zetaOfficeReason('${m['error']}')} The file on disk is unchanged '
        'and your changes are still in this tab.',
        kind: 'error',
      );
      waiting.complete(TomOfficeSaveOutcome.failed);
      return;
    }
    final written = _written ?? TomOfficeSaveOutcome.failed;
    if (written == TomOfficeSaveOutcome.saved) {
      _unsaved = false;
      zetaTrail('save: written');
    } else if (written == TomOfficeSaveOutcome.conflict) {
      _notice(
        '${host.name} changed on disk since it was opened; it was not '
        'overwritten.',
        kind: 'warning',
      );
    }
    waiting.complete(written);
  }

  /// *Keep mine* after a conflict: saves again over whatever is on disk.
  Future<TomOfficeSaveOutcome> keepMine() async {
    if (!_conflict) return TomOfficeSaveOutcome.refused;
    _revision = await host.files.revisionOf(host.filePath);
    return save();
  }

  /// *Save as copy*: `storeToURL` in the file's own format (the modified
  /// flag stays set) to `<name> (copy).<ext>` beside the file; returns its
  /// path, or `null` when it failed.
  Future<String?> saveAsCopy() async {
    final channel = _channel;
    if (channel == null ||
        (_state != TomZetaOfficeState.open &&
            _state != TomZetaOfficeState.saving)) {
      return null;
    }
    final done = _copying = Completer<String?>();
    _copyPath = null;
    await channel.call('saveCopy');
    return done.future.timeout(
      saveTimeout,
      onTimeout: () {
        _notice('The copy could not be written: no answer.', kind: 'error');
        return null;
      },
    );
  }

  Future<void> _receiveCopy(Uint8List bytes) async {
    final exporting = _exporting;
    if (exporting != null) {
      _exporting = null;
      exporting.complete(bytes);
      return;
    }
    final temporary = await host.files.temporaryTarget(host.filePath);
    final written = await host.files.save(
      temporary,
      bytes,
      await host.files.revisionOf(temporary),
    );
    if (!written.replaced) throw StateError('the copy could not be written');
    _copyPath = await host.files.keepAsCopy(temporary, host.filePath);
    zetaTrail('save as copy: written');
  }

  // ------------------------------------------------------------ history

  /// ZetaOffice's undo (`.uno:Undo`).
  Future<void> undo() async {
    if (_state == TomZetaOfficeState.open) await _channel?.call('undo');
  }

  /// ZetaOffice's redo (`.uno:Redo`).
  Future<void> redo() async {
    if (_state == TomZetaOfficeState.open) await _channel?.call('redo');
  }

  // ---------------------------------------------------- external changes

  /// Compares the file on disk with the revision read (the host calls it
  /// when the window regains focus): a clean document reloads, a dirty one
  /// is marked in conflict.
  Future<void> checkExternal() async {
    if (_state != TomZetaOfficeState.open) return;
    final now = await host.files.revisionOf(host.filePath);
    final read = _revision;
    if (now == null || read == null || now.sameContent(read)) return;
    if (isDirty) {
      _conflict = true;
      notifyListeners();
      return;
    }
    _notice('${host.name} changed on disk and was reloaded.');
    await reload();
  }

  /// Starts again from the file on disk.
  Future<void> reload() async {
    await serving.stop();
    _page = null;
    await start();
  }

  // ------------------------------------------------- the content process

  /// The webview's content process was killed (memory pressure): the
  /// document is gone; the tab says so.
  void contentProcessGone() {
    if (_state == TomZetaOfficeState.closed) return;
    zetaTrail('content process terminated');
    _startTimer?.cancel();
    final wasDirty = isDirty || _canUndo;
    _dirty = _unsaved = _canUndo = _canRedo = false;
    _set(TomZetaOfficeState.processGone);
    _notice(
      'The web content process showing ${host.name} was ended by the '
      'system; unsaved changes are lost.',
      kind: 'warning',
    );
    if (wasDirty) host.historyChanged();
  }

  // --------------------------------------------------------- test hooks

  /// Test hook: inserts [text] at the start of the document through UNO.
  Future<void> editForTest(String text) async => _channel?.call('edit', [text]);

  /// Test hook: the document as a PDF exported by ZetaOffice (`storeToURL`
  /// with the kind's PDF filter); null when it failed or did not answer in
  /// [saveTimeout]. The evaluation compares ZetaOffice's rendering with it.
  Future<Uint8List?> exportPdfForTest() async {
    final channel = _channel;
    if (channel == null || _state != TomZetaOfficeState.open) return null;
    _exportErrorForTest = null;
    final done = _exporting = Completer<Uint8List?>();
    await channel.call('exportPdf');
    return done.future.timeout(
      saveTimeout,
      onTimeout: () {
        _exporting = null;
        _exportErrorForTest = 'no answer in ${saveTimeout.inSeconds} s';
        return null;
      },
    );
  }

  Completer<Uint8List?>? _exporting;
  String? _exportErrorForTest;

  /// Test hook: why the last [exportPdfForTest] gave null (ZetaOffice's
  /// error, or that it did not answer), or null after one that exported.
  String? get exportErrorForTest => _exportErrorForTest;

  final _pageMessages = StreamController<Map<String, Object?>>.broadcast();

  /// Test hook: every message the page sends, as it arrives (the
  /// evaluation's measuring scripts answer through it).
  Stream<Map<String, Object?>> get pageMessagesForTest => _pageMessages.stream;

  /// Test hook: the page as the webview shows it (PNG), or null.
  Future<Uint8List?> snapshotForTest() async => _channel?.snapshot();

  /// Test hook: runs [source] in the page.
  Future<void> runInPageForTest(String source) async =>
      _channel?.call('run', [source]);

  /// Test hook: the document's text (a text document's body, a sheet's A1,
  /// a slide's first shape).
  Future<String> readForTest() async {
    final done = _reading = Completer<String>();
    await _channel?.call('read');
    return done.future.timeout(const Duration(seconds: 30));
  }

  /// Ends the tab.
  Future<void> close() async {
    _startTimer?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    _channel = null;
    await serving.stop();
    if (_active == this) _active = null;
    _set(TomZetaOfficeState.closed);
  }

  @override
  void dispose() {
    if (_state != TomZetaOfficeState.closed) unawaited(close());
    unawaited(_notices.close());
    unawaited(_pageMessages.close());
    super.dispose();
  }
}
