// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// A thin Dart wrapper over the LibreOfficeKit bindings, for the spike.
/// Spike code: todo officeproto8 reuses what holds up, todo later24 removes
/// the spike.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'lok_bindings.g.dart';
import 'lok_trampoline.dart';

/// VCL key codes (vcl/keycodes.hxx, com.sun.star.awt.Key). They are not in
/// the LibreOfficeKit headers.
abstract final class Keys {
  static const down = 1024;
  static const up = 1025;
  static const left = 1026;
  static const right = 1027;
  static const home = 1028;
  static const end = 1029;
  static const enter = 1280;
  static const escape = 1281;
  static const tab = 1282;
  static const backspace = 1283;
}

const callbackNames = <int, String>{
  0: 'INVALIDATE_TILES',
  1: 'INVALIDATE_VISIBLE_CURSOR',
  2: 'TEXT_SELECTION',
  3: 'TEXT_SELECTION_START',
  4: 'TEXT_SELECTION_END',
  5: 'CURSOR_VISIBLE',
  6: 'GRAPHIC_SELECTION',
  7: 'HYPERLINK_CLICKED',
  8: 'STATE_CHANGED',
  9: 'STATUS_INDICATOR_START',
  10: 'STATUS_INDICATOR_SET_VALUE',
  11: 'STATUS_INDICATOR_FINISH',
  12: 'SEARCH_NOT_FOUND',
  13: 'DOCUMENT_SIZE_CHANGED',
  14: 'SET_PART',
  15: 'SEARCH_RESULT_SELECTION',
  16: 'UNO_COMMAND_RESULT',
  17: 'CELL_CURSOR',
  18: 'MOUSE_POINTER',
  19: 'CELL_FORMULA',
  20: 'DOCUMENT_PASSWORD',
  21: 'DOCUMENT_PASSWORD_TO_MODIFY',
  22: 'ERROR',
  23: 'CONTEXT_MENU',
  24: 'INVALIDATE_VIEW_CURSOR',
  32: 'COMMENT',
  33: 'INVALIDATE_HEADER',
  34: 'CELL_ADDRESS',
  35: 'RULER_UPDATE',
  36: 'WINDOW',
  39: 'CONTEXT_CHANGED',
  46: 'JSDIALOG',
  50: 'INVALIDATE_SHEET_GEOMETRY',
  52: 'DOCUMENT_BACKGROUND_COLOR',
  57: 'FONTS_MISSING',
  61: 'APPLICATION_BACKGROUND_COLOR',
  70: 'CORE_LOG',
  71: 'TOOLTIP',
};

String callbackName(int type) => callbackNames[type] ?? 'TYPE_$type';

/// One callback as Dart received it from the trampoline.
class LokEvent {
  LokEvent(this.type, this.payload, this.tag, this.intact, this.at);

  final int type;
  final String payload;
  final int tag;

  /// The FNV-1a hash and length of Dart's copy match what the trampoline saw
  /// in LibreOffice's original payload.
  final bool intact;
  final Duration at;

  String get name => callbackName(type);

  @override
  String toString() =>
      '$name ${payload.length > 160 ? '${payload.substring(0, 160)}…' : payload}';
}

final Stopwatch clock = Stopwatch()..start();
final StreamController<LokEvent> _events = StreamController.broadcast(
  sync: true,
);
Stream<LokEvent> get lokEvents => _events.stream;
final List<LokEvent> eventLog = [];
int receivedCount = 0;
int corruptCount = 0;
NativeCallable<TomLokListenerNative>? _listener;

void _onCallback(
  int type,
  Pointer<Char> payload,
  int length,
  int hash,
  int tag,
) {
  var text = '';
  var intact = true;
  if (payload != nullptr) {
    final ownHash = tomLokFnv1a(payload, length);
    text = payload.cast<Utf8>().toDartString(length: length);
    intact = ownHash == hash && utf8.encode(text).length == length;
    tomLokFree(payload.cast());
  }
  receivedCount++;
  if (!intact) corruptCount++;
  final event = LokEvent(type, text, tag, intact, clock.elapsed);
  eventLog.add(event);
  _events.add(event);
}

int tomCallbackCount() => tomLokCallbackCount();

void installListener() {
  _listener ??= NativeCallable<TomLokListenerNative>.listener(_onCallback);
  tomLokSetListener(_listener!.nativeFunction);
}

/// Waits for the first event (after now) that [test] accepts.
Future<LokEvent?> waitEvent(
  bool Function(LokEvent e) test, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<LokEvent?>();
  late StreamSubscription<LokEvent> sub;
  sub = lokEvents.listen((e) {
    if (test(e) && !completer.isCompleted) completer.complete(e);
  });
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });
  final result = await completer.future;
  timer.cancel();
  await sub.cancel();
  return result;
}

/// Lets the event loop deliver pending callbacks for [time].
Future<void> settle([Duration time = const Duration(milliseconds: 300)]) =>
    Future<void>.delayed(time);

Pointer<Char> _str(String s, Arena arena) =>
    s.toNativeUtf8(allocator: arena).cast();

String? _take(Pointer<Char> p, {bool free = true}) {
  if (p == nullptr) return null;
  final text = p.cast<Utf8>().toDartString();
  if (free) malloc.free(p);
  return text;
}

class Office {
  Office._(this.kit);

  final Pointer<LibreOfficeKit> kit;

  LibreOfficeKitClass get _c => kit.ref.pClass.ref;

  /// The nSize check: is field [index] (0-based, after nSize) of the class
  /// inside the size the library reports?
  bool has(int index) => 8 + 8 * (index + 1) <= _c.nSize;

  static Office? init(String program, String profileUrl) {
    installListener();
    return using((arena) {
      final kit = tomLokInit2(_str(program, arena), _str(profileUrl, arena));
      if (kit == nullptr) return null;
      final office = Office._(kit);
      office._c.registerCallback
          .asFunction<
            void Function(
              Pointer<LibreOfficeKit>,
              LibreOfficeKitCallback,
              Pointer<Void>,
            )
          >()(kit, tomLokCallbackPointer(), Pointer.fromAddress(0));
      return office;
    });
  }

  String versionInfo() =>
      _take(
        _c.getVersionInfo
            .asFunction<Pointer<Char> Function(Pointer<LibreOfficeKit>)>()(kit),
      ) ??
      '';

  /// The password the trampoline gives when LibreOfficeKit asks (null:
  /// cancel).
  void answerPasswords(String? password) => using(
    (a) => tomLokSetPasswordAnswer(
      kit,
      password == null ? nullptr : _str(password, a),
    ),
  );

  /// setDocumentPassword called directly from Dart.
  void setDocumentPassword(String path, String? password) => using(
    (a) =>
        _c.setDocumentPassword
            .asFunction<
              void Function(
                Pointer<LibreOfficeKit>,
                Pointer<Char>,
                Pointer<Char>,
              )
            >()(
          kit,
          _str(Uri.file(path).toString(), a),
          password == null ? nullptr : _str(password, a),
        ),
  );

  void setOptionalFeatures(int features) => _c.setOptionalFeatures
      .asFunction<void Function(Pointer<LibreOfficeKit>, int)>()(kit, features);

  void setOption(String option, String value) => using(
    (a) => _c.setOption
        .asFunction<
          void Function(Pointer<LibreOfficeKit>, Pointer<Char>, Pointer<Char>)
        >()(kit, _str(option, a), _str(value, a)),
  );

  String? error() => _take(
    _c.getError.asFunction<Pointer<Char> Function(Pointer<LibreOfficeKit>)>()(
      kit,
    ),
  );

  Document? load(
    String path, {
    String options = '{"Language":"en-US"}',
    int tag = 1,
  }) => using((arena) {
    final url = Uri.file(path).toString();
    final doc = _c.documentLoadWithOptions
        .asFunction<
          Pointer<LibreOfficeKitDocument> Function(
            Pointer<LibreOfficeKit>,
            Pointer<Char>,
            Pointer<Char>,
          )
        >()(kit, _str(url, arena), _str(options, arena));
    if (doc == nullptr) return null;
    final document = Document._(doc, path, tag);
    document._register();
    return document;
  });

  void destroy() =>
      _c.destroy.asFunction<void Function(Pointer<LibreOfficeKit>)>()(kit);
}

class Document {
  Document._(this.doc, this.path, this.tag);

  final Pointer<LibreOfficeKitDocument> doc;
  final String path;
  final int tag;

  LibreOfficeKitDocumentClass get _c => doc.ref.pClass.ref;

  void _register() => _c.registerCallback
      .asFunction<
        void Function(
          Pointer<LibreOfficeKitDocument>,
          LibreOfficeKitCallback,
          Pointer<Void>,
        )
      >()(doc, tomLokCallbackPointer(), Pointer.fromAddress(tag));

  int get type => _c.getDocumentType
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(doc);
  int get parts => _c.getParts
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(doc);
  int get part => _c.getPart
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(doc);
  set part(int p) =>
      _c.setPart
          .asFunction<void Function(Pointer<LibreOfficeKitDocument>, int)>()(
        doc,
        p,
      );
  String partName(int p) =>
      _take(
        _c.getPartName
            .asFunction<
              Pointer<Char> Function(Pointer<LibreOfficeKitDocument>, int)
            >()(doc, p),
      ) ??
      '';
  int get tileMode => _c.getTileMode
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(doc);

  (int, int) get size => using((a) {
    final w = a<Long>();
    final h = a<Long>();
    _c.getDocumentSize
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            Pointer<Long>,
            Pointer<Long>,
          )
        >()(doc, w, h);
    return (w.value, h.value);
  });

  void initializeForRendering([String args = '{}']) => using(
    (a) => _c.initializeForRendering
        .asFunction<
          void Function(Pointer<LibreOfficeKitDocument>, Pointer<Char>)
        >()(doc, _str(args, a)),
  );

  void setClientZoom(int pxW, int pxH, int twW, int twH) => _c.setClientZoom
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int, int)
      >()(doc, pxW, pxH, twW, twH);

  void setClientVisibleArea(int x, int y, int w, int h) => _c
      .setClientVisibleArea
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int, int)
      >()(doc, x, y, w, h);

  /// One tile of [pxW]×[pxH] pixels showing the twip rectangle (x, y, w, h).
  Uint8List paintTile(int part, int pxW, int pxH, int x, int y, int w, int h) {
    final buffer = calloc<Uint8>(pxW * pxH * 4);
    try {
      _c.paintPartTile
          .asFunction<
            void Function(
              Pointer<LibreOfficeKitDocument>,
              Pointer<UnsignedChar>,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
            )
          >()(doc, buffer.cast(), part, 0, pxW, pxH, x, y, w, h);
      return Uint8List.fromList(buffer.asTypedList(pxW * pxH * 4));
    } finally {
      calloc.free(buffer);
    }
  }

  void postKey(int type, int charCode, int keyCode) => _c.postKeyEvent
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int)
      >()(doc, type, charCode, keyCode);

  /// Key down and up for one character or key.
  void press({int char = 0, int key = 0}) {
    postKey(0, char, key);
    postKey(1, char, key);
  }

  void typeText(String text) {
    for (final rune in text.runes) {
      press(char: rune);
    }
  }

  void postMouse(
    int type,
    int x,
    int y, {
    int count = 1,
    int buttons = 1,
    int modifier = 0,
  }) => _c.postMouseEvent
      .asFunction<
        void Function(
          Pointer<LibreOfficeKitDocument>,
          int,
          int,
          int,
          int,
          int,
          int,
        )
      >()(doc, type, x, y, count, buttons, modifier);

  void click(int x, int y) {
    postMouse(0, x, y);
    postMouse(1, x, y);
  }

  void uno(String command, [String args = '', bool notify = true]) => using(
    (a) => _c.postUnoCommand
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            Pointer<Char>,
            Pointer<Char>,
            bool,
          )
        >()(doc, _str(command, a), _str(args, a), notify),
  );

  String? commandValues(String command) => using(
    (a) => _take(
      _c.getCommandValues
          .asFunction<
            Pointer<Char> Function(
              Pointer<LibreOfficeKitDocument>,
              Pointer<Char>,
            )
          >()(doc, _str(command, a)),
    ),
  );

  String? textSelection([String mime = 'text/plain;charset=utf-8']) =>
      using((a) {
        final used = a<Pointer<Char>>();
        final text = _take(
          _c.getTextSelection
              .asFunction<
                Pointer<Char> Function(
                  Pointer<LibreOfficeKitDocument>,
                  Pointer<Char>,
                  Pointer<Pointer<Char>>,
                )
              >()(doc, _str(mime, a), used),
        );
        if (used.value != nullptr) malloc.free(used.value);
        return text;
      });

  /// 1 on success.
  int saveAs(String path, {String format = '', String filterOptions = ''}) =>
      using(
        (a) =>
            _c.saveAs
                .asFunction<
                  int Function(
                    Pointer<LibreOfficeKitDocument>,
                    Pointer<Char>,
                    Pointer<Char>,
                    Pointer<Char>,
                  )
                >()(
              doc,
              _str(Uri.file(path).toString(), a),
              _str(format, a),
              _str(filterOptions, a),
            ),
      );

  Uint8List paintWindow(int windowId, int x, int y, int w, int h) {
    final buffer = calloc<Uint8>(w * h * 4);
    try {
      _c.paintWindow
          .asFunction<
            void Function(
              Pointer<LibreOfficeKitDocument>,
              int,
              Pointer<UnsignedChar>,
              int,
              int,
              int,
              int,
            )
          >()(doc, windowId, buffer.cast(), x, y, w, h);
      return Uint8List.fromList(buffer.asTypedList(w * h * 4));
    } finally {
      calloc.free(buffer);
    }
  }

  void postWindow(int windowId, int action, [String data = '']) => using(
    (a) => _c.postWindow
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            int,
            int,
            Pointer<Char>,
          )
        >()(doc, windowId, action, _str(data, a)),
  );

  void windowKey(int windowId, {int char = 0, int key = 0}) {
    final f = _c.postWindowKeyEvent
        .asFunction<
          void Function(Pointer<LibreOfficeKitDocument>, int, int, int, int)
        >();
    f(doc, windowId, 0, char, key);
    f(doc, windowId, 1, char, key);
  }

  void windowClick(int windowId, int x, int y) {
    final f = _c.postWindowMouseEvent
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            int,
            int,
            int,
            int,
            int,
            int,
            int,
          )
        >();
    f(doc, windowId, 0, x, y, 1, 1, 0);
    f(doc, windowId, 1, x, y, 1, 1, 0);
  }

  void destroy() => _c.destroy
      .asFunction<void Function(Pointer<LibreOfficeKitDocument>)>()(doc);

  void registerAgain() => _register();

  /// postUnoCommand from a second isolate (another thread): a dialog that
  /// LibreOffice runs modally blocks the posting thread until it closes, and
  /// this keeps the main isolate free to receive its WINDOW callback, paint it
  /// and close it.
  Future<void> unoInIsolate(String command, [String args = '']) {
    final address = doc.address;
    return Isolate.run(
      () => Document._(
        Pointer.fromAddress(address),
        '',
        0,
      ).uno(command, args, true),
    );
  }

  int createView() => _c.createView
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(doc);

  set view(int id) =>
      _c.setView
          .asFunction<void Function(Pointer<LibreOfficeKitDocument>, int)>()(
        doc,
        id,
      );
}

// --------------------------------------------------------------------------
// Pixels
// --------------------------------------------------------------------------

/// Share of pixels that differ from the tile's most common colour.
double inkShare(Uint8List px) {
  final counts = <int, int>{};
  final n = px.length ~/ 4;
  for (var i = 0; i < n; i++) {
    final v = px.buffer.asByteData().getUint32(i * 4);
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final top = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
  return n == 0 ? 0 : (n - top) / n;
}

int diffPixels(Uint8List a, Uint8List b) {
  var d = 0;
  for (var i = 0; i < a.length && i < b.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) d++;
  }
  return d;
}

/// Writes [px] (BGRA when [bgra], else RGBA) as a PNG.
void writePng(String path, Uint8List px, int w, int h, {bool bgra = true}) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (bgra) {
        raw.add([px[i + 2], px[i + 1], px[i], 255]);
      } else {
        raw.add([px[i], px[i + 1], px[i + 2], 255]);
      }
    }
  }
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    out.add(_u32(data.length));
    out.add(body);
    out.add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, 6, 0, 0, 0]);
  chunk('IDAT', ZLibCodec(level: 6).encode(raw.toBytes()));
  chunk('IEND', []);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(out.toBytes());
}

List<int> _u32(int v) => [
  (v >> 24) & 255,
  (v >> 16) & 255,
  (v >> 8) & 255,
  v & 255,
];

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 255] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
