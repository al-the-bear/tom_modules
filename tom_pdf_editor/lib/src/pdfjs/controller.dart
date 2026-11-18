// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tom_file_session/io.dart';

import '../host.dart';
import '../pdf_editor_trail.dart';
import 'channel.dart';

/// The pinned pdf.js release under `third_party/pdfjs/` (DPPJ-1).
const kPdfJsVersion = '6.5.438';

/// Where the vendored pdf.js is in the asset bundle.
const kPdfJsAssets = 'packages/tom_pdf_editor/third_party/pdfjs/$kPdfJsVersion';

/// Where Forge's host files (bridge, options, stylesheet, components page)
/// are in the asset bundle.
const kPdfJsForgeAssets = 'packages/tom_pdf_editor/assets/pdfjs_forge';

/// Where a [TomPdfJsController] is.
enum TomPdfJsState {
  /// Not started.
  idle,

  /// The page is loading in the webview.
  starting,

  /// The document is opening.
  opening,

  /// Open.
  open,

  /// Saving.
  saving,

  /// It could not open or could not go on (see
  /// [TomPdfJsController.failure]).
  failed,

  /// Closed.
  closed,
}

/// A conflict with the file on disk (as the PDFium editor's).
@immutable
final class TomPdfJsConflict {
  const TomPdfJsConflict({required this.deleted, this.temporary});

  /// Whether the file was deleted (else changed).
  final bool deleted;

  /// The saved copy waiting for the choice, when the conflict came at a
  /// save.
  final String? temporary;
}

/// The pdf.js view's controller: the local content site (pdf.js, Forge's
/// host page, the document, the save receiver), the bridge to the page, and
/// the same shape as `TomPdfEditorController` — open, save, undo, redo,
/// find, the dirty state, external changes, conflicts — so a host treats
/// both PDF views alike.
///
/// pdf.js keeps its own history; [canUndo] / [canRedo] follow what the page
/// reports, and [isDirty] follows pdf.js's annotation storage (which has no
/// saved marker: undoing back to the saved state can still read dirty).
class TomPdfJsController extends ChangeNotifier {
  /// A controller over [host] in [mode]; [server] defaults to the process's
  /// shared server, [bundle] to the root asset bundle.
  TomPdfJsController(
    this.host, {
    this.mode = TomPdfJsMode.components,
    this.hostReadOnly = false,
    TomLocalContentServer? server,
    AssetBundle? bundle,
    this.testBaseUri,
  }) : _server = server ?? TomLocalContentServer.shared,
       _bundle = bundle ?? rootBundle;

  /// Offline for widget tests under a fake clock, where no server can bind:
  /// no content site is opened, the page and document URIs are made below
  /// this base, and saving is not available. Tests that save start the
  /// controller in the real zone instead (`tester.runAsync(start)`).
  final Uri? testBaseUri;

  bool _offlineStarted = false;

  Uri _uriOf(String path) => _site?.uriOf(path) ?? testBaseUri!.resolve(path);

  /// The host.
  final TomPdfViewHost host;

  /// How much of pdf.js's interface shows.
  final TomPdfJsMode mode;

  /// Whether the host asked for a read-only document.
  final bool hostReadOnly;

  final TomLocalContentServer _server;
  final AssetBundle _bundle;

  TomContentSite? _site;
  TomPdfJsChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _messages;
  TomPdfJsState _state = TomPdfJsState.idle;
  TomFileRevision? _revision;
  bool _readOnly = false;
  String? _failure;
  int _pageCount = 0;
  bool _dirty = false;
  bool _canUndo = false;
  bool _canRedo = false;
  bool? _hasTextLayer;
  TomPdfJsConflict? _conflict;
  bool _deleted = false;
  int _generation = 0;
  ({int current, int total})? _findCount;
  Completer<void>? _saving;
  Future<void> Function(List<int> bytes)? _receive;
  final _notices = StreamController<(String, String)>.broadcast();
  final _shortcuts = StreamController<String>.broadcast();
  final _openWatch = Stopwatch();

  /// The state.
  TomPdfJsState get state => _state;

  /// Why it failed.
  String? get failure => _failure;

  /// The pages of the open document.
  int get pageCount => _pageCount;

  /// Whether pdf.js's annotation storage holds unsaved changes.
  bool get isDirty => _dirty;

  /// Whether pdf.js's history can undo.
  bool get canUndo => _canUndo;

  /// Whether it can redo.
  bool get canRedo => _canRedo;

  /// Whether the document is read-only (the host asked, or the file cannot
  /// be written): the tools are hidden, *Save as copy* is offered.
  bool get isReadOnly => _readOnly;

  /// Whether the first pages carry text (`null` until checked).
  bool? get hasTextLayer => _hasTextLayer;

  /// A pending conflict with the file on disk.
  TomPdfJsConflict? get conflict => _conflict;

  /// Whether the file was deleted on disk.
  bool get isDeleted => _deleted;

  /// The last search's match count.
  ({int current, int total})? get findCount => _findCount;

  /// Counts the opens of the document (the first and each reopen).
  int get generation => _generation;

  /// `(kind, message)` notices for the view to show through the host.
  Stream<(String, String)> get notices => _notices.stream;

  /// Shortcuts typed inside the webview that belong to the shell: `save`,
  /// `find`.
  Stream<String> get shortcuts => _shortcuts.stream;

  /// The content site while it is open: the view lets the webview navigate
  /// only inside it; tests post to it.
  TomContentSite? get site => _site;

  /// The page the webview loads for [mode].
  Uri get pageUri {
    final page = switch (mode) {
      TomPdfJsMode.integrated => 'pdfjs/web/forge-integrated.html',
      TomPdfJsMode.full => 'pdfjs/web/forge-full.html',
      TomPdfJsMode.components => 'pdfjs/web/forge/components.html',
    };
    return _uriOf(
      page,
    ).replace(queryParameters: {'readonly': _readOnly ? '1' : '0'});
  }

  /// Where the page fetches the document (a new path per open, so nothing
  /// cached is reused).
  Uri get documentUri =>
      _uriOf('doc/$_generation/${host.filePath.split('/').last}');

  /// Where the page posts the saved bytes.
  Uri get saveUri => _uriOf('save');

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _set(TomPdfJsState s) {
    if (_state == s) return;
    pdfJsTrail('state ${_state.name} → ${s.name}');
    _state = s;
    notifyListeners();
  }

  void _notice(String kind, String message) {
    if (!_notices.isClosed) _notices.add((kind, message));
  }

  void _fail(String message) {
    _failure = message;
    _set(TomPdfJsState.failed);
  }

  // ----------------------------------------------------------------- start

  /// Opens the content site: pdf.js and Forge's host files from the asset
  /// bundle, the document read from disk with `Range` support, the save
  /// receiver. Then [attach] a channel to load [pageUri].
  Future<void> start() async {
    if (_site != null || _offlineStarted) return;
    _set(TomPdfJsState.starting);
    try {
      _revision = await host.files.revisionOf(host.filePath);
      if (_revision == null) {
        _fail('could not open: ${host.name} does not exist');
        return;
      }
      _readOnly = hostReadOnly || !await host.files.isWritable(host.filePath);
      if (testBaseUri != null) {
        _offlineStarted = true;
        pdfJsTrail('offline (test) start, ${mode.name}');
        return;
      }
      final site = await _server.openSite();
      site.onRequest = (r) => pdfJsTrail('server: ${_kind(r)}');
      site.mount('pdfjs', TomContentMount.assets(_asset));
      site.mount('doc', TomContentMount.file(host.filePath));
      site.mount(
        'save',
        TomContentMount.receiver((content) async {
          final receive = _receive;
          if (receive == null) throw StateError('no save is waiting');
          await receive(content.bytes);
        }, maxBytes: 4 << 30),
      );
      _site = site;
      pdfJsTrail('site open (${mode.name}, readOnly $_readOnly)');
      if (_readOnly) {
        _notice('info', '${host.name} is read-only: use Save as copy.');
      }
    } catch (e, s) {
      pdfReport(e, s, 'starting the pdf.js view');
      _fail('could not start the pdf.js view: $e');
    }
  }

  /// The trail line of a request: its kind and size, never the token or the
  /// document's name.
  static String _kind(TomContentRequest r) {
    final first = r.path.split('/').first;
    final kind = switch (first) {
      'pdfjs' => r.path.contains('/forge') ? 'host' : 'pdfjs',
      _ => first,
    };
    return '${r.method} $kind ${r.status} ${r.bytes} B';
  }

  /// The vendored pdf.js, Forge's files under `web/forge/`, and the host
  /// pages `web/forge-integrated.html` / `web/forge-full.html`, made from
  /// pdf.js's `web/viewer.html` (served beside it, so its relative paths
  /// and its CSP stay as they are).
  Future<List<int>?> _asset(String path) async {
    try {
      if (path == 'web/forge-integrated.html' ||
          path == 'web/forge-full.html') {
        return utf8.encode(
          hostPage(
            utf8.decode(_bytes(await _load('$kPdfJsAssets/web/viewer.html'))),
            integrated: path == 'web/forge-integrated.html',
          ),
        );
      }
      final key = path.startsWith('web/forge/')
          ? '$kPdfJsForgeAssets/${path.substring('web/forge/'.length)}'
          : '$kPdfJsAssets/$path';
      return _bytes(await _load(key));
    } catch (_) {
      return null; // 404
    }
  }

  static Uint8List _bytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  /// An asset by its key as an application sees it (`packages/...`); in
  /// the package's own tests the bundle has it without the prefix.
  Future<ByteData> _load(String key) async {
    try {
      return await _bundle.load(key);
    } catch (_) {
      const own = 'packages/tom_pdf_editor/';
      if (!key.startsWith(own)) rethrow;
      return _bundle.load(key.substring(own.length));
    }
  }

  /// Forge's host page from pdf.js's `viewer.html`: the options script
  /// before the viewer starts, the bridge after it, and in `integrated`
  /// mode the stylesheet hiding what the shell does.
  @visibleForTesting
  static String hostPage(String viewerHtml, {required bool integrated}) {
    const viewer = '<script src="viewer.mjs" type="module"></script>';
    const css = '<link rel="stylesheet" href="viewer.css" />';
    if (!viewerHtml.contains(viewer) || !viewerHtml.contains(css)) {
      throw StateError('viewer.html is not the one the host page expects');
    }
    var page = viewerHtml.replaceFirst(
      viewer,
      '<script src="forge/options.js"></script>\n  $viewer\n'
      '  <script src="forge/generic.mjs" type="module"></script>',
    );
    if (integrated) {
      page = page.replaceFirst(
        css,
        '$css\n    <link rel="stylesheet" href="forge/integrated.css" />',
      );
    }
    return page;
  }

  /// Connects the webview: listens to the page and loads [pageUri].
  Future<void> attach(TomPdfJsChannel channel) async {
    await _messages?.cancel();
    _channel = channel;
    _messages = channel.messages.listen(_onMessage);
    if (_site == null && !_offlineStarted) await start();
    if (_site == null && !_offlineStarted) return;
    pdfJsTrail('load the ${mode.name} page');
    await channel.load(pageUri);
  }

  /// Lets go of the webview (another controller takes it over): the page's
  /// messages no longer reach this one.
  Future<void> detach() async {
    await _messages?.cancel();
    _messages = null;
    _channel = null;
  }

  Future<void> _call(String function, [List<Object?> args = const []]) async {
    final channel = _channel;
    if (channel == null) return;
    pdfJsTrail('→ $function');
    try {
      await channel.call(function, args);
    } catch (e, s) {
      pdfReport(e, s, 'calling the pdf.js bridge ($function)');
    }
  }

  // --------------------------------------------------------------- messages

  void _onMessage(Map<String, Object?> m) {
    final type = m['type'];
    if (type != 'trail') pdfJsTrail('← $type');
    try {
      switch (type) {
        case 'ready':
          unawaited(_openDocument());
        case 'loaded':
          _pageCount = (m['pageCount'] as num?)?.toInt() ?? 0;
          pdfJsTrail(
            'opened in ${_openWatch.elapsedMilliseconds} ms '
            '(page: ${m['ms']} ms)',
          );
          _dirty = false;
          _set(TomPdfJsState.open);
          notifyListeners();
        case 'textLayer':
          _hasTextLayer = m['value'] == true;
          if (_hasTextLayer == false) {
            _notice(
              'info',
              'This PDF has no text layer (scanned) — highlighting text, '
                  'selection and search find nothing.',
            );
          }
          notifyListeners();
        case 'modified':
          final dirty = m['value'] == true;
          if (dirty != _dirty) {
            _dirty = dirty;
            host.historyChanged();
            notifyListeners();
          }
        case 'history':
          _canUndo = m['canUndo'] == true;
          _canRedo = m['canRedo'] == true;
          host.historyChanged();
          notifyListeners();
        case 'tool':
          // pdf.js changed its tool itself (Escape, a highlight from the
          // selection): the toolbar follows.
          final mode = (m['mode'] as num?)?.toInt();
          if (mode != null && mode >= 0 && mode != _tool) {
            _tool = mode;
            notifyListeners();
          }
        case 'findCount':
          _findCount = (
            current: (m['current'] as num?)?.toInt() ?? 0,
            total: (m['total'] as num?)?.toInt() ?? 0,
          );
          notifyListeners();
        case 'saved':
          pdfJsTrail(
            'saved ${m['size']} bytes in ${m['ms']} ms (status ${m['status']})',
          );
          if (m['ok'] != true) {
            _endSave(StateError('the save was refused (${m['status']})'));
          }
        case 'error':
          final kind = m['kind'];
          final message = '${m['message']}';
          if (kind == 'save') {
            _endSave(StateError(message));
          } else {
            _fail(
              kind == 'password'
                  ? 'could not open: no password given'
                  : 'could not open: $message',
            );
          }
        case 'openLink':
          final url = m['url'];
          if (url is String) host.openLink(url);
        case 'passwordRequested':
          pdfJsTrail('password requested (answered in the page)');
        case 'shortcut':
          final key = m['key'];
          if (key == 'save') {
            unawaited(save());
          } else if (key is String && !_shortcuts.isClosed) {
            _shortcuts.add(key);
          }
        case 'trail':
          pdfJsTrail('page: ${m['text']}');
          if ('${m['text']}'.startsWith('console.error')) {
            // Always reported, with the trail off too.
            debugPrint('[PE:js] ${m['text']}');
          }
      }
    } catch (e, s) {
      pdfReport(e, s, 'a pdf.js bridge message ($type)');
    }
  }

  Future<void> _openDocument() async {
    _set(TomPdfJsState.opening);
    _openWatch
      ..reset()
      ..start();
    _canUndo = _canRedo = false;
    _findCount = null;
    await _call('open', ['$documentUri']);
  }

  /// Opens the document from disk again (after a save, *take theirs*, an
  /// external change); pdf.js closes the one it had first.
  Future<void> reopen() async {
    _generation++;
    _conflict = null;
    _deleted = false;
    _revision = await host.files.revisionOf(host.filePath);
    await _openDocument();
  }

  // ----------------------------------------------------------------- saving

  /// Saves: the page's `saveDocument()` bytes are POSTed to the content
  /// site and written through the host's [TomBinaryFiles] — a temporary
  /// target, then a replace over an unchanged original, else a [conflict].
  Future<void> save() async {
    if (_state != TomPdfJsState.open) return;
    if (_readOnly) {
      _notice('warning', 'This document is read-only: use Save as copy.');
      return;
    }
    TomBinaryReplaceResult? result;
    final ok = await _collect((bytes) async {
      pdfJsTrail('write ${bytes.length} bytes');
      result = await host.files.save(
        host.filePath,
        bytes,
        _deleted ? null : _revision,
      );
    });
    final r = result;
    if (!ok || r == null) return;
    if (!r.replaced) {
      pdfJsTrail('save: conflict');
      _conflict = TomPdfJsConflict(
        deleted: r.revision == null,
        temporary: r.temporary,
      );
      notifyListeners();
      return;
    }
    pdfJsTrail('save: replaced, reopen');
    await _saved();
  }

  /// Asks the page for its bytes and hands them to [receive]; answers
  /// whether that worked.
  Future<bool> _collect(Future<void> Function(List<int> bytes) receive) async {
    if (_saving != null) return false;
    final saving = _saving = Completer<void>();
    _receive = (bytes) async {
      try {
        await receive(bytes);
        _endSave(null);
      } catch (e) {
        _endSave(e);
        rethrow;
      }
    };
    _set(TomPdfJsState.saving);
    await _call('save', ['$saveUri']);
    try {
      await saving.future;
      _set(TomPdfJsState.open);
      return true;
    } catch (e) {
      pdfJsTrail('save failed: $e');
      _notice('error', 'Could not save: $e');
      _set(TomPdfJsState.open);
      return false;
    } finally {
      _saving = null;
      _receive = null;
    }
  }

  void _endSave(Object? error) {
    final saving = _saving;
    if (saving == null || saving.isCompleted) return;
    if (error == null) {
      saving.complete();
    } else {
      saving.completeError(error);
    }
  }

  /// After the file was written: pdf.js's storage is clean, and the
  /// document is reopened from the new file.
  Future<void> _saved() async {
    await _call('resetModified');
    _dirty = false;
    host.historyChanged();
    await reopen();
  }

  /// The conflict choice *Keep mine*: replace the file on disk anyway.
  Future<void> keepMine() async {
    final c = _conflict;
    if (c == null) return;
    final temp = c.temporary;
    if (temp != null) {
      await host.files.replace(host.filePath, temp, null, force: true);
      await _saved();
      return;
    }
    // A conflict found by checkExternal: the page's bytes now, over
    // whatever is on disk.
    TomBinaryReplaceResult? result;
    final ok = await _collect((bytes) async {
      result = await host.files.save(
        host.filePath,
        bytes,
        await host.files.revisionOf(host.filePath),
      );
    });
    if (ok && (result?.replaced ?? false)) await _saved();
  }

  /// The conflict choice *Take theirs*: reopen from disk; the edits are lost.
  Future<void> takeTheirs() async {
    _dirty = false;
    host.historyChanged();
    await reopen();
  }

  /// *Save as copy*: `<name> (copy).pdf` beside the file (a conflict's
  /// saved bytes, or the page's bytes now). Also for a read-only document.
  Future<String?> saveAsCopy() async {
    String? copy;
    final temp = _conflict?.temporary;
    if (temp != null) {
      copy = await host.files.keepAsCopy(temp, host.filePath);
    } else {
      final ok = await _collect((bytes) async {
        // TomBinaryFiles writes bytes only by its save rules: into a fresh
        // (empty) temporary file, which then becomes the copy.
        final t = await host.files.temporaryTarget(host.filePath);
        await host.files.save(t, bytes, await host.files.revisionOf(t));
        copy = await host.files.keepAsCopy(t, host.filePath);
      });
      if (!ok) return null;
    }
    _conflict = null;
    if (copy != null) _notice('info', 'Saved as ${copy!.split('/').last}');
    notifyListeners();
    return copy;
  }

  // -------------------------------------------------------- external changes

  /// Compares the file on disk with the one opened (the host calls it when
  /// the window regains focus): a clean document reopens with a notice, a
  /// dirty one shows the conflict banner, a deleted file is marked.
  Future<void> checkExternal() async {
    if (_state != TomPdfJsState.open || _revision == null) return;
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
    if (_dirty) {
      _conflict = const TomPdfJsConflict(deleted: false);
      notifyListeners();
    } else {
      await reopen();
      _notice('info', '${host.name} changed on disk and was reloaded.');
    }
  }

  // ------------------------------------------------------- editing, finding

  /// pdf.js's undo.
  Future<void> undo() => _call('undo');

  /// pdf.js's redo.
  Future<void> redo() => _call('redo');

  /// Chooses an annotation tool ([TomPdfJsTool]); ignored when read-only.
  Future<void> setTool(int tool) async {
    if (_readOnly && tool != TomPdfJsTool.none) return;
    _tool = tool;
    notifyListeners();
    await _call('setTool', [tool]);
  }

  int _tool = TomPdfJsTool.none;

  /// The tool last chosen through [setTool].
  int get tool => _tool;

  /// Zooms (`in`, `out`, `page-width`, `page-fit`).
  Future<void> zoom(String how) => _call('zoom', [how]);

  /// Searches pdf.js for [term] (an empty term clears it).
  Future<void> find(
    String term, {
    bool caseSensitive = false,
    bool entireWord = false,
    bool again = false,
    bool previous = false,
  }) {
    pdfJsTrail('find ${term.length} chars');
    return _call('find', [
      term,
      {
        'caseSensitive': caseSensitive,
        'entireWord': entireWord,
        'again': again,
        'previous': previous,
      },
    ]);
  }

  /// Asks the page for the modified state again.
  Future<void> checkModified() => _call('checkModified');

  /// The webview's content process ended (memory pressure): the view is
  /// gone, the tab says so; [reload] starts it again.
  void contentProcessTerminated() {
    pdfJsTrail('content process terminated');
    _endSave(StateError('the web content process ended'));
    _fail('the pdf.js view stopped: its web content process ended');
  }

  /// Loads the page again (after the content process ended).
  Future<void> reload() async {
    final channel = _channel;
    if (channel == null || _site == null) return;
    _failure = null;
    _set(TomPdfJsState.starting);
    await channel.load(pageUri);
  }

  // ------------------------------------------------------------------ close

  /// Closes the document and the content site.
  Future<void> close() async {
    _endSave(StateError('closed'));
    await _call('close');
    await _messages?.cancel();
    _messages = null;
    _channel = null;
    final site = _site;
    _site = null;
    await site?.close();
    _set(TomPdfJsState.closed);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    unawaited(_notices.close());
    unawaited(_shortcuts.close());
    super.dispose();
  }
}
