// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The helper's frame loop and message dispatch: protocol 1 over a byte
/// stream in and a byte sink out, against a [LokRuntime].
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'lok/lok_api.dart';
import 'version.dart';

/// `setOptionalFeatures`: password callbacks (to open and to modify) and
/// comments as callbacks instead of painted into tiles
/// (`LOK_FEATURE_DOCUMENT_PASSWORD | _TO_MODIFY | NO_TILED_ANNOTATIONS`).
const kLokFeatures = 1 | 2 | 8;

/// The filter names `.uno:SaveAs` takes, by document type and format: used
/// to save a document opened with a password, because `saveAs` drops its
/// encryption.
const kSaveFilters = <String, String>{
  'docx': 'MS Word 2007 XML',
  'doc': 'MS Word 97',
  'odt': 'writer8',
  'rtf': 'Rich Text Format',
  'xlsx': 'Calc MS Excel 2007 XML',
  'xls': 'MS Excel 97',
  'ods': 'calc8',
  'pptx': 'Impress MS PowerPoint 2007 XML',
  'ppt': 'MS PowerPoint 97',
  'odp': 'impress8',
  'odg': 'draw8',
};

/// The formats a save exports to instead of storing the document in: the
/// document stays the file it was opened from.
const kExportFormats = {'pdf'};

/// The PDF export filter of each document type.
const kPdfFilters = <int, String>{
  0: 'writer_pdf_Export',
  1: 'calc_pdf_Export',
  2: 'impress_pdf_Export',
  3: 'draw_pdf_Export',
};

/// One helper session: the office, at most one document, protocol 1 on
/// [output].
///
/// [serve] reads frames from the input until `close` or the end of the
/// input, answers each, forwards LibreOfficeKit's callbacks, and returns the
/// exit code. Every failure of a request becomes an `error` message; the log
/// ([log], stderr in the command) never holds a password.
class OfficeHost {
  /// A session over [runtime], with LibreOffice's [program] folder and the
  /// profile [profileUrl] (`file://`).
  ///
  /// [deleteProfile] removes the profile folder after a clean close (the
  /// helper's profile is private: one per helper). [lockOwnerOf] reads who
  /// holds a document's lock file; the default reads
  /// `.~lock.<name>#` beside it.
  OfficeHost({
    required this.runtime,
    required this.program,
    required this.profileUrl,
    required this.output,
    required this.log,
    int? pid,
    this.deleteProfile = true,
    this.editStateWait = const Duration(milliseconds: 500),
    String? Function(String path)? lockOwnerOf,
  }) : pid = pid ?? 0,
       _lockOwnerOf = lockOwnerOf ?? readLockOwner;

  /// LibreOfficeKit.
  final LokRuntime runtime;

  /// LibreOffice's program folder (`Contents/Frameworks` on macOS).
  final String program;

  /// The helper's private profile as a `file://` URL.
  final String profileUrl;

  /// Where frames go (stdout).
  final void Function(List<int> frame) output;

  /// The helper's log (stderr).
  final void Function(String line) log;

  /// The process id sent in `hello`.
  final int pid;

  /// Whether a clean close deletes the profile folder.
  final bool deleteProfile;

  /// How long after opening the helper waits for `.uno:EditDoc` to say the
  /// document is read-only.
  final Duration editStateWait;

  final String? Function(String path) _lockOwnerOf;

  static const _codec = OfficeProtocolCodec();

  LokOffice? _office;
  LokDocument? _doc;
  LokDocument? _held; // opened read-only while the password to modify is asked
  StreamSubscription<LokCallback>? _callbacks;

  // The open in progress.
  OfficeOpen? _opening;
  bool _toModifyAsked = false;
  String? _password; // only while a document opened with one is open
  bool _readOnly = false;
  bool _editDocFalse = false;
  String _path = '';
  String? _lockedBy;

  final _queue = Queue<OfficeHelperCommand>();
  bool _draining = false;
  final _done = Completer<int>();

  /// The exit code once the session ends.
  Future<int> get done => _done.future;

  /// Whether the session has ended.
  bool get isDone => _done.isCompleted;

  /// Whether a document is open.
  bool get hasDocument => _doc != null;

  /// Starts LibreOfficeKit, sends `hello`, then serves [input] until `close`
  /// or its end. Returns the exit code: 0 after a clean close, 3 when
  /// LibreOfficeKit does not load.
  Future<int> serve(Stream<List<int>> input) async {
    final watch = Stopwatch()..start();
    final office = runtime.init(program, profileUrl);
    if (office == null) {
      log('lok_init_2 failed: program=$program profile=$profileUrl');
      _send(
        OfficeError(
          code: 'initFailed',
          message: 'LibreOfficeKit did not load from $program',
        ),
      );
      _done.complete(3);
      return 3;
    }
    _office = office;
    office.setOptionalFeatures(kLokFeatures);
    _callbacks = runtime.callbacks.listen(_onCallback);
    log('lok_init_2 ok in ${watch.elapsedMilliseconds} ms');
    _send(
      OfficeHello(
        helperVersion: kOfficeHostVersion,
        lokVersion: office.versionInfo,
        pid: pid,
      ),
    );
    final reader = OfficeFrameReader(_codec);
    final sub = input.listen(
      (chunk) {
        try {
          for (final message in reader.add(chunk)) {
            if (message is OfficeHelperCommand) {
              _queue.add(message);
            } else {
              _send(
                OfficeError(
                  code: 'wrongDirection',
                  message:
                      '${message.messageType.tableName} is sent by the '
                      'helper, not to it',
                ),
              );
            }
          }
        } on OfficeProtocolException catch (e) {
          log('refused input: $e');
          _send(OfficeError(code: 'protocol', message: e.message));
          _finish(sendClosed: true, code: 2);
          return;
        }
        unawaited(_drain());
      },
      onDone: () {
        log('end of stdin');
        _queue.add(const OfficeClose());
        unawaited(_drain());
      },
      onError: (Object e) {
        log('stdin error: $e');
        _queue.add(const OfficeClose());
        unawaited(_drain());
      },
    );
    final code = await done;
    await sub.cancel();
    return code;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_done.isCompleted) {
        final message = _queue.removeFirst();
        if (message is OfficeRenderTile && _superseded(message)) {
          log('renderTile ${message.id} coalesced into a newer request');
          continue;
        }
        await _handle(message);
      }
    } finally {
      _draining = false;
    }
  }

  /// Whether a newer request for the same area and size is waiting.
  bool _superseded(OfficeRenderTile tile) => _queue.any(
    (m) =>
        m is OfficeRenderTile &&
        m.part == tile.part &&
        m.x == tile.x &&
        m.y == tile.y &&
        m.w == tile.w &&
        m.h == tile.h &&
        m.pxW == tile.pxW &&
        m.pxH == tile.pxH,
  );

  void _send(OfficeMessage message) {
    try {
      output(_codec.encode(message));
    } catch (e) {
      log('could not send ${message.messageType.tableName}: $e');
    }
  }

  static String _describe(OfficeHelperCommand m) => switch (m) {
    OfficePassword() => m.toString(), // redacted
    OfficeKey() || OfficeWindowKey() || OfficeTextInput() =>
      m.messageType.tableName, // typed text stays out of the log
    OfficeWindowTextInput() || OfficePaste() => m.messageType.tableName,
    OfficeRenderTile(:final id) ||
    OfficePaintWindow(:final id) => '${m.messageType.tableName} $id',
    _ => m.toString(),
  };

  Future<void> _handle(OfficeHelperCommand message) async {
    log('<- ${_describe(message)}');
    final id = message is OfficeRequest ? (message as OfficeRequest).id : null;
    try {
      await _dispatch(message);
    } on _Refused catch (e) {
      _send(OfficeError(id: id, code: e.code, message: e.message));
    } catch (e, s) {
      log('${message.messageType.tableName} failed: $e\n$s');
      _send(
        OfficeError(
          id: id,
          code: 'failed',
          message: '${message.messageType.tableName}: $e',
        ),
      );
    }
  }

  LokDocument get _document {
    final doc = _doc;
    if (doc == null) throw const _Refused('notOpen', 'no document is open');
    return doc;
  }

  Future<void> _dispatch(OfficeHelperCommand message) async {
    switch (message) {
      case OfficeOpen():
        await _open(message);
      case OfficePassword(:final password):
        await _answerPassword(password);
      case OfficeRenderTile():
        final m = message;
        final pixels = _document.paintTile(
          m.part,
          m.pxW,
          m.pxH,
          m.x,
          m.y,
          m.w,
          m.h,
        );
        _send(
          OfficeTile(
            id: m.id,
            part: m.part,
            x: m.x,
            y: m.y,
            w: m.w,
            h: m.h,
            pxW: m.pxW,
            pxH: m.pxH,
            format: _format,
            pixels: pixels,
          ),
        );
      case OfficeKey(:final type, :final charCode, :final keyCode):
        _document.postKeyEvent(_keyType(type), charCode, keyCode);
      case OfficeTextInput(:final type, :final text):
        final doc = _document;
        if (!doc.postExtTextInput(_textInputType(type), text) &&
            type == OfficeTextInputType.end) {
          // An older LibreOffice without the call: type the text as keys.
          for (final rune in text.runes) {
            doc.postKeyEvent(0, rune, 0);
            doc.postKeyEvent(1, rune, 0);
          }
        }
      case OfficeMouse():
        final m = message;
        _document.postMouseEvent(
          _mouseType(m.type),
          m.x,
          m.y,
          m.count,
          m.buttons,
          m.modifiers,
        );
      case OfficeSelection(:final kind, :final type, :final x, :final y):
        final doc = _document;
        switch (kind) {
          case OfficeSelectionKind.text:
            doc.setTextSelection(type, x, y);
          case OfficeSelectionKind.graphic:
            doc.setGraphicSelection(type, x, y);
          case OfficeSelectionKind.reset:
            doc.resetSelection();
        }
      case OfficeUno(:final id, :final command, :final args):
        final doc = _document;
        // Not awaited: a modal dialog blocks this call until it closes, and
        // the loop must stay free to serve the dialog's window.
        unawaited(
          doc.postUnoCommand(command, args).catchError((Object e) {
            _send(OfficeError(id: id, code: 'unoFailed', message: '$e'));
          }),
        );
      case OfficeCommandValues(:final id, :final command):
        _send(
          OfficeValues(id: id, json: _document.commandValues(command) ?? ''),
        );
      case OfficeView(:final part, :final visibleArea, :final zoom):
        final doc = _document;
        if (part != doc.part) doc.part = part;
        if (zoom <= 0) throw const _Refused('badZoom', 'zoom must be > 0');
        // Tile pixels per twip: tell LibreOffice what one 256-pixel tile
        // covers.
        doc.setClientZoom(256, 256, (256 / zoom).round(), (256 / zoom).round());
        doc.setClientVisibleArea(
          visibleArea.x,
          visibleArea.y,
          visibleArea.w,
          visibleArea.h,
        );
      case OfficeSetPart(:final part):
        _document.part = part;
      case OfficeSave():
        await _save(message);
      case OfficePaintWindow():
        final m = message;
        _send(
          OfficeWindowPixels(
            id: m.id,
            windowId: m.windowId,
            x: m.x,
            y: m.y,
            w: m.w,
            h: m.h,
            format: _format,
            pixels: _document.paintWindow(
              m.windowId,
              m.x,
              m.y,
              m.w,
              m.h,
              m.dpiScale,
            ),
          ),
        );
      case OfficeWindowMouse():
        final m = message;
        _document.postWindowMouseEvent(
          m.windowId,
          _mouseType(m.type),
          m.x,
          m.y,
          m.count,
          m.buttons,
          m.modifiers,
        );
      case OfficeWindowKey():
        final m = message;
        _document.postWindowKeyEvent(
          m.windowId,
          _keyType(m.type),
          m.charCode,
          m.keyCode,
        );
      case OfficeWindowTextInput(:final windowId, :final type, :final text):
        _document.postWindowExtTextInput(windowId, _textInputType(type), text);
      case OfficeWindowClose(:final windowId):
        _document.postWindow(windowId, 0); // LOK_WINDOW_CLOSE
      case OfficeDialogEvent():
        throw const _Refused(
          'jsonDialogsUnavailable',
          'this LibreOffice has no JSON dialogs (no sendDialogEvent)',
        );
      case OfficeDialogModeMessage(:final mode):
        if (mode == OfficeDialogMode.json) {
          throw const _Refused(
            'jsonDialogsUnavailable',
            'this LibreOffice has no JSON dialogs: dialogs stay windows',
          );
        }
      case OfficePing(:final id):
        _send(OfficePong(id: id));
      case OfficeClose():
        _finish(sendClosed: true, code: 0);
      case OfficeCopy(:final id, :final mimeTypes):
        final doc = _document;
        final data = <String, String>{};
        for (final mime in mimeTypes) {
          final text = doc.textSelection(mime);
          if (text != null) data[mime] = text;
        }
        _send(OfficeClipboard(id: id, data: data));
      case OfficePaste(:final mimeType, :final data):
        if (!_document.paste(mimeType, data)) {
          throw _Refused('pasteFailed', 'LibreOffice refused $mimeType');
        }
    }
  }

  OfficePixelFormat get _format =>
      _document.tileMode == 1 ? OfficePixelFormat.bgra : OfficePixelFormat.rgba;

  static int _keyType(OfficeKeyEventType t) =>
      t == OfficeKeyEventType.down ? 0 : 1;

  static int _textInputType(OfficeTextInputType t) =>
      t == OfficeTextInputType.input ? 0 : 2; // LOK_EXT_TEXTINPUT(_END)

  static int _mouseType(OfficeMouseEventType t) => switch (t) {
    OfficeMouseEventType.down => 0,
    OfficeMouseEventType.up => 1,
    OfficeMouseEventType.move => 2,
  };

  // -------------------------------------------------------------------------
  // Opening and passwords

  Future<void> _open(OfficeOpen open) async {
    if (_doc != null || _opening != null) {
      throw const _Refused('alreadyOpen', 'this helper holds a document');
    }
    _opening = open;
    _path = open.path;
    // Read before the load: LibreOffice writes its own lock file while it
    // opens the document.
    _lockedBy = _lockOwnerOf(open.path);
    await _load(null);
  }

  /// Loads the document being opened, the trampoline armed with [password]
  /// (never logged).
  Future<void> _load(String? password) async {
    final open = _opening!;
    final office = _office!;
    _editDocFalse = false;
    office.armPasswordAnswer(password);
    final watch = Stopwatch()..start();
    final doc = office.load(open.path, loadOptions(open));
    final asked = runtime.passwordAsked;
    if (doc == null) {
      if (asked & 1 != 0) {
        log(
          'load needs a password (${asked & 4 != 0 ? 'wrong one given' : 'none given'})',
        );
        _send(const OfficePasswordNeeded(toModify: false));
        return; // _opening stays: the next `password` loads again
      }
      _opening = null;
      final error = office.lastError() ?? 'unknown error';
      throw _Refused('loadFailed', error);
    }
    if (asked & 2 != 0 && (password == null || asked & 4 != 0)) {
      // Opened read-only for want of the (right) password to modify: ask,
      // and keep the read-only document for a cancel.
      _toModifyAsked = true;
      _held = doc;
      log(
        password == null
            ? 'the document has a password to modify'
            : 'wrong password to modify',
      );
      _send(const OfficePasswordNeeded(toModify: true));
      return;
    }
    log('loaded in ${watch.elapsedMilliseconds} ms');
    _password = password;
    await _finishOpen(doc, readOnly: open.readOnly);
  }

  Future<void> _answerPassword(String? password) async {
    final open = _opening;
    if (open == null) {
      throw const _Refused('noPasswordAsked', 'no password was asked for');
    }
    final held = _held;
    if (_toModifyAsked && held != null) {
      _held = null;
      if (password == null) {
        await _finishOpen(held, readOnly: true);
        return;
      }
      held.destroy();
      await _load(password);
      return;
    }
    if (password == null) {
      _opening = null;
      _toModifyAsked = false;
      throw const _Refused('passwordCancelled', 'the password was cancelled');
    }
    await _load(password);
  }

  Future<void> _finishOpen(LokDocument doc, {required bool readOnly}) async {
    _doc = doc;
    _opening = null;
    _toModifyAsked = false;
    doc.initializeForRendering('{}');
    final lockedBy = _lockedBy;
    // LibreOffice reports a document it opened read-only (a stale lock file,
    // say) only as `.uno:EditDoc=false`, a moment after the load.
    if (editStateWait > Duration.zero) {
      await Future<void>.delayed(editStateWait);
    }
    _readOnly = readOnly || lockedBy != null || _editDocFalse;
    final (w, h) = doc.size;
    final parts = doc.parts;
    _send(
      OfficeOpened(
        docType: switch (doc.documentType) {
          0 => OfficeDocType.text,
          1 => OfficeDocType.spreadsheet,
          2 => OfficeDocType.presentation,
          3 => OfficeDocType.drawing,
          _ => OfficeDocType.other,
        },
        parts: parts,
        partNames: [for (var i = 0; i < parts; i++) doc.partName(i)],
        currentPart: doc.part,
        width: w,
        height: h,
        tileMode: _format,
        readOnly: _readOnly,
        lockedBy: lockedBy,
      ),
    );
    log(
      'opened: type ${doc.documentType}, $parts part(s), ${w}x$h twips'
      '${_readOnly ? ', read-only' : ''}',
    );
  }

  /// Who holds the lock file LibreOffice leaves beside a document it has
  /// open (`.~lock.<name>#`, a CSV line naming the user first), or `null`.
  static String? readLockOwner(String path) {
    final file = File(path);
    final name = file.uri.pathSegments.last;
    final lock = File('${file.parent.path}/.~lock.$name#');
    if (!lock.existsSync()) return null;
    try {
      final first = lock.readAsStringSync().split(',').first.trim();
      return first.isEmpty ? 'another LibreOffice' : first;
    } on FileSystemException {
      return 'another LibreOffice';
    }
  }

  // -------------------------------------------------------------------------
  // Saving

  Future<void> _save(OfficeSave save) async {
    final doc = _document;
    final format = save.format.isNotEmpty
        ? save.format
        : _extensionOf(_path); // the target has no extension of its own
    if (format.isEmpty) {
      throw _Refused('noFormat', 'no format given and $_path has no extension');
    }
    // A document opened with a password is saved with it unless the user
    // chose an unencrypted copy (keepPassword false).
    final password = save.keepPassword ? _password : null;
    bool ok;
    String? error;
    if (password == null) {
      final options = [
        if (save.filterOptions.isNotEmpty) save.filterOptions,
        // Without it the modified flag stays set. An export (PDF) keeps the
        // document where it is: LibreOffice refuses TakeOwnership for it
        // (0x81a, invalid parameter).
        if (!kExportFormats.contains(format)) 'TakeOwnership',
      ].join(',');
      ok = doc.saveAs(save.targetPath, format, options);
      if (!ok) error = _office!.lastError() ?? 'saveAs failed';
    } else {
      // saveAs drops a password's encryption; .uno:SaveAs keeps it.
      final filter = format == 'pdf'
          ? kPdfFilters[doc.documentType]
          : kSaveFilters[format];
      if (filter == null) {
        throw _Refused('noFilter', 'no filter to save $format with a password');
      }
      final result = _nextUnoResult('.uno:SaveAs');
      await doc.postUnoCommand(
        '.uno:SaveAs',
        jsonEncode({
          'URL': {
            'type': 'string',
            'value': Uri.file(save.targetPath).toString(),
          },
          'FilterName': {'type': 'string', 'value': filter},
          'Password': {'type': 'string', 'value': password},
        }),
      );
      final payload = await result.timeout(
        const Duration(seconds: 60),
        onTimeout: () => '{"success":false}',
      );
      ok = _unoSucceeded(payload);
      if (!ok) error = '.uno:SaveAs failed: $payload';
    }
    final encryption = _password == null
        ? ''
        : password == null
        ? ', without the password'
        : ', with the password';
    log('save ${save.id}: ${ok ? 'written' : 'failed'} ($format$encryption)');
    _send(OfficeSaved(id: save.id, ok: ok, error: error));
  }

  static String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  final _unoWaiters = <(String, Completer<String>)>[];

  Future<String> _nextUnoResult(String command) {
    final completer = Completer<String>();
    _unoWaiters.add((command, completer));
    return completer.future;
  }

  static bool _unoSucceeded(String payload) {
    try {
      final json = jsonDecode(payload);
      return json is Map && json['success'] == true;
    } on FormatException {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Callbacks

  void _onCallback(LokCallback callback) {
    if (_done.isCompleted) return;
    switch (callback.type) {
      case LokCallbackType.documentPassword:
      case LokCallbackType.documentPasswordToModify:
        return; // answered by the trampoline, reported as passwordNeeded
      case LokCallbackType.window:
        _forwardWindow(callback.payload);
        return;
      case LokCallbackType.jsDialog:
        _send(OfficeJsDialog(json: callback.payload));
        return;
      case LokCallbackType.stateChanged:
        if (callback.payload.startsWith('.uno:EditDoc=false')) {
          _editDocFalse = true;
        }
      case LokCallbackType.unoCommandResult:
        _resolveUno(callback.payload);
    }
    _send(
      OfficeCallback(
        type: LokCallbackType.nameOf(callback.type),
        payload: callback.payload,
      ),
    );
  }

  void _resolveUno(String payload) {
    String? command;
    try {
      final json = jsonDecode(payload);
      if (json is Map) command = json['commandName'] as String?;
    } on FormatException {
      return;
    }
    for (final waiter in _unoWaiters) {
      if (waiter.$1 == command && !waiter.$2.isCompleted) {
        waiter.$2.complete(payload);
        _unoWaiters.remove(waiter);
        return;
      }
    }
  }

  /// A `WINDOW` callback as `windowOpened` (`created`) or `windowChanged`.
  void _forwardWindow(String payload) {
    final Map<String, Object?> json;
    try {
      json = (jsonDecode(payload) as Map).cast<String, Object?>();
    } on Object {
      log('WINDOW payload not JSON: $payload');
      return;
    }
    final id = int.tryParse('${json['id']}') ?? 0;
    final action = '${json['action'] ?? ''}';
    final size = _ints(json['size']);
    if (action == 'created') {
      final position = _ints(json['position']);
      _send(
        OfficeWindowOpened(
          windowId: id,
          kind: '${json['type'] ?? 'dialog'}',
          title: '${json['title'] ?? ''}',
          width: size.isNotEmpty ? size[0] : 0,
          height: size.length > 1 ? size[1] : 0,
          parentId: int.tryParse('${json['parentId'] ?? ''}'),
          x: position.length == 2 ? position[0] : null,
          y: position.length == 2 ? position[1] : null,
        ),
      );
      return;
    }
    final r = _ints(json['rectangle']);
    final visible = json['visible'];
    _send(
      OfficeWindowChanged(
        windowId: id,
        action: action,
        rectangle: r.length == 4 ? OfficeRect(r[0], r[1], r[2], r[3]) : null,
        width: size.length == 2 ? size[0] : null,
        height: size.length == 2 ? size[1] : null,
        title: json['title'] is String ? json['title'] as String : null,
        visible: visible == null ? null : '$visible' == 'true',
      ),
    );
  }

  static List<int> _ints(Object? value) => value == null
      ? const []
      : '$value'
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();

  // -------------------------------------------------------------------------
  // Ending

  void _finish({required bool sendClosed, required int code}) {
    if (_done.isCompleted) return;
    unawaited(_callbacks?.cancel());
    _callbacks = null;
    try {
      _doc?.destroy();
      _held?.destroy();
      _office?.destroy();
    } catch (e) {
      log('destroy failed: $e');
    }
    _doc = null;
    _held = null;
    _office = null;
    if (deleteProfile) _removeProfile();
    if (sendClosed) _send(const OfficeClosed());
    log('closed (exit $code)');
    _done.complete(code);
  }

  void _removeProfile() {
    try {
      final dir = Directory.fromUri(Uri.parse(profileUrl));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      log('could not delete the profile: $e');
    }
  }
}

final class _Refused implements Exception {
  const _Refused(this.code, this.message);
  final String code;
  final String message;
}

/// The options string of `documentLoadWithOptions` for [open].
/// LibreOfficeKit takes `Name=value` pairs it knows (`Language`, `Batch`) out
/// of it and hands the rest to the import filter as its `FilterOptions`.
/// With filter options (a CSV file's separator, quote, encoding and first
/// line) the load also runs as `Batch=true`: otherwise LibreOffice shows its
/// Text Import dialog and the load never returns. Without them it stays
/// interactive, so the password callbacks still come.
String loadOptions(OfficeOpen open) => open.filterOptions.isEmpty
    ? 'Language=${open.language}'
    : 'Batch=true,${open.filterOptions},Language=${open.language}';
