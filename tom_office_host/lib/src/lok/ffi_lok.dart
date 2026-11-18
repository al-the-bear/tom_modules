// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// [LokRuntime], [LokOffice] and [LokDocument] over the FFI bindings and the
/// C trampoline.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'lok_api.dart';
import 'lok_bindings.g.dart';
import 'trampoline.dart';

/// The slots of the calls the helper checks against the class's `nSize`
/// before calling (0-based among the function pointers, as the headers order
/// them; the test `LOK-SLOTS-1` checks them against the header).
abstract final class LokDocumentSlot {
  static const paste = 19;
  static const paintPartTile = 32;
  static const paintWindow = 35;
  static const postWindow = 36;
  static const postWindowKeyEvent = 37;
  static const postWindowMouseEvent = 38;
  static const postWindowExtTextInputEvent = 40;
  static const paintWindowDPI = 42;
}

/// Whether function-pointer [slot] lies inside a class of [nSize] bytes
/// (`nSize` itself first, then 8-byte pointers).
bool lokHasSlot(int nSize, int slot) => 8 + 8 * (slot + 1) <= nSize;

Pointer<Char> _str(String s, Arena arena) =>
    s.toNativeUtf8(allocator: arena).cast();

String? _take(Pointer<Char> p) {
  if (p == nullptr) return null;
  final text = p.cast<Utf8>().toDartString();
  malloc.free(p);
  return text;
}

/// The runtime over the trampoline. One per process: the trampoline has one
/// listener.
final class FfiLokRuntime implements LokRuntime {
  /// The runtime; [init] installs the listener.
  FfiLokRuntime();

  final _callbacks = StreamController<LokCallback>.broadcast(sync: true);
  NativeCallable<TomLokListenerNative>? _listener;

  @override
  Stream<LokCallback> get callbacks => _callbacks.stream;

  @override
  int get passwordAsked => tomLokPasswordAsked();

  void _onCallback(int type, Pointer<Char> payload, int length, int tag) {
    var text = '';
    if (payload != nullptr) {
      text = payload.cast<Utf8>().toDartString(length: length);
      tomLokFree(payload.cast());
    }
    _callbacks.add(LokCallback(type, text));
  }

  @override
  LokOffice? init(String program, String profileUrl) {
    _listener ??= NativeCallable<TomLokListenerNative>.listener(_onCallback);
    tomLokSetListener(_listener!.nativeFunction);
    return using((arena) {
      final kit = tomLokInit2(_str(program, arena), _str(profileUrl, arena));
      if (kit == nullptr) return null;
      kit.ref.pClass.ref.registerCallback
          .asFunction<
            void Function(
              Pointer<LibreOfficeKit>,
              LibreOfficeKitCallback,
              Pointer<Void>,
            )
          >()(kit, tomLokCallbackPointer(), nullptr);
      return FfiLokOffice._(kit);
    });
  }

  /// Closes the listener, which otherwise keeps the isolate alive.
  void close() {
    tomLokSetListener(nullptr);
    _listener?.close();
    _listener = null;
  }
}

/// The office over FFI.
final class FfiLokOffice implements LokOffice {
  FfiLokOffice._(this._kit);

  final Pointer<LibreOfficeKit> _kit;

  LibreOfficeKitClass get _c => _kit.ref.pClass.ref;

  @override
  String get versionInfo =>
      _take(
        _c.getVersionInfo
            .asFunction<Pointer<Char> Function(Pointer<LibreOfficeKit>)>()(
          _kit,
        ),
      ) ??
      '';

  @override
  void setOptionalFeatures(int features) =>
      _c.setOptionalFeatures
          .asFunction<void Function(Pointer<LibreOfficeKit>, int)>()(
        _kit,
        features,
      );

  @override
  void armPasswordAnswer(String? password) => using(
    (a) => tomLokSetPasswordAnswer(
      _kit,
      password == null ? nullptr : _str(password, a),
    ),
  );

  @override
  LokDocument? load(String path, String optionsJson) => using((arena) {
    final doc =
        _c.documentLoadWithOptions
            .asFunction<
              Pointer<LibreOfficeKitDocument> Function(
                Pointer<LibreOfficeKit>,
                Pointer<Char>,
                Pointer<Char>,
              )
            >()(
          _kit,
          _str(Uri.file(path).toString(), arena),
          _str(optionsJson, arena),
        );
    if (doc == nullptr) return null;
    doc.ref.pClass.ref.registerCallback
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            LibreOfficeKitCallback,
            Pointer<Void>,
          )
        >()(doc, tomLokCallbackPointer(), Pointer.fromAddress(1));
    return FfiLokDocument(doc.address);
  });

  @override
  String? lastError() => _take(
    _c.getError.asFunction<Pointer<Char> Function(Pointer<LibreOfficeKit>)>()(
      _kit,
    ),
  );

  @override
  void destroy() =>
      _c.destroy.asFunction<void Function(Pointer<LibreOfficeKit>)>()(_kit);
}

/// A document over FFI, by its address (so a second isolate can post a UNO
/// command to it).
final class FfiLokDocument implements LokDocument {
  /// The document at [address].
  FfiLokDocument(this.address);

  /// The `LibreOfficeKitDocument*`.
  final int address;

  Pointer<LibreOfficeKitDocument> get _doc => Pointer.fromAddress(address);

  LibreOfficeKitDocumentClass get _c => _doc.ref.pClass.ref;

  bool _has(int slot) => lokHasSlot(_c.nSize, slot);

  @override
  int get documentType => _c.getDocumentType
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(_doc);

  @override
  int get parts => _c.getParts
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(_doc);

  @override
  int get part => _c.getPart
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(_doc);

  @override
  set part(int value) =>
      _c.setPart
          .asFunction<void Function(Pointer<LibreOfficeKitDocument>, int)>()(
        _doc,
        value,
      );

  @override
  String partName(int part) =>
      _take(
        _c.getPartName
            .asFunction<
              Pointer<Char> Function(Pointer<LibreOfficeKitDocument>, int)
            >()(_doc, part),
      ) ??
      '';

  @override
  int get tileMode => _c.getTileMode
      .asFunction<int Function(Pointer<LibreOfficeKitDocument>)>()(_doc);

  @override
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
        >()(_doc, w, h);
    return (w.value, h.value);
  });

  @override
  void initializeForRendering(String argumentsJson) => using(
    (a) => _c.initializeForRendering
        .asFunction<
          void Function(Pointer<LibreOfficeKitDocument>, Pointer<Char>)
        >()(_doc, _str(argumentsJson, a)),
  );

  @override
  void setClientZoom(int tilePxW, int tilePxH, int tileTwW, int tileTwH) => _c
      .setClientZoom
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int, int)
      >()(_doc, tilePxW, tilePxH, tileTwW, tileTwH);

  @override
  void setClientVisibleArea(int x, int y, int w, int h) => _c
      .setClientVisibleArea
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int, int)
      >()(_doc, x, y, w, h);

  @override
  Uint8List paintTile(int part, int pxW, int pxH, int x, int y, int w, int h) {
    final buffer = calloc<Uint8>(pxW * pxH * 4);
    try {
      if (_has(LokDocumentSlot.paintPartTile)) {
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
            >()(_doc, buffer.cast(), part, 0, pxW, pxH, x, y, w, h);
      } else {
        _c.paintTile
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
              )
            >()(_doc, buffer.cast(), pxW, pxH, x, y, w, h);
      }
      return Uint8List.fromList(buffer.asTypedList(pxW * pxH * 4));
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void postKeyEvent(int type, int charCode, int keyCode) => _c.postKeyEvent
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int)
      >()(_doc, type, charCode, keyCode);

  @override
  bool postExtTextInput(int type, String text) {
    if (!_has(LokDocumentSlot.postWindowExtTextInputEvent)) return false;
    postWindowExtTextInput(0, type, text);
    return true;
  }

  @override
  void postMouseEvent(
    int type,
    int x,
    int y,
    int count,
    int buttons,
    int mods,
  ) => _c.postMouseEvent
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
      >()(_doc, type, x, y, count, buttons, mods);

  @override
  void setTextSelection(int type, int x, int y) => _c.setTextSelection
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int)
      >()(_doc, type, x, y);

  @override
  void setGraphicSelection(int type, int x, int y) => _c.setGraphicSelection
      .asFunction<
        void Function(Pointer<LibreOfficeKitDocument>, int, int, int)
      >()(_doc, type, x, y);

  @override
  void resetSelection() => _c.resetSelection
      .asFunction<void Function(Pointer<LibreOfficeKitDocument>)>()(_doc);

  @override
  String? textSelection(String mimeType) => using((a) {
    final used = a<Pointer<Char>>();
    final text = _take(
      _c.getTextSelection
          .asFunction<
            Pointer<Char> Function(
              Pointer<LibreOfficeKitDocument>,
              Pointer<Char>,
              Pointer<Pointer<Char>>,
            )
          >()(_doc, _str(mimeType, a), used),
    );
    if (used.value != nullptr) malloc.free(used.value);
    return text;
  });

  @override
  bool paste(String mimeType, String data) {
    if (!_has(LokDocumentSlot.paste)) return false;
    return using((a) {
      final bytes = data.toNativeUtf8(allocator: a);
      return _c.paste
          .asFunction<
            bool Function(
              Pointer<LibreOfficeKitDocument>,
              Pointer<Char>,
              Pointer<Char>,
              int,
            )
          >()(_doc, _str(mimeType, a), bytes.cast(), bytes.length);
    });
  }

  @override
  Future<void> postUnoCommand(String command, String argumentsJson) {
    final address = this.address;
    return Isolate.run(
      () => FfiLokDocument(address)._postUno(command, argumentsJson),
    );
  }

  void _postUno(String command, String argumentsJson) => using(
    (a) => _c.postUnoCommand
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            Pointer<Char>,
            Pointer<Char>,
            bool,
          )
        >()(_doc, _str(command, a), _str(argumentsJson, a), true),
  );

  @override
  String? commandValues(String command) => using(
    (a) => _take(
      _c.getCommandValues
          .asFunction<
            Pointer<Char> Function(
              Pointer<LibreOfficeKitDocument>,
              Pointer<Char>,
            )
          >()(_doc, _str(command, a)),
    ),
  );

  @override
  bool saveAs(String path, String format, String filterOptions) => using(
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
          _doc,
          _str(Uri.file(path).toString(), a),
          _str(format, a),
          _str(filterOptions, a),
        ) !=
        0,
  );

  @override
  Uint8List paintWindow(
    int windowId,
    int x,
    int y,
    int w,
    int h,
    double dpiScale,
  ) {
    final buffer = calloc<Uint8>(w * h * 4);
    try {
      if (dpiScale != 1.0 && _has(LokDocumentSlot.paintWindowDPI)) {
        _c.paintWindowDPI
            .asFunction<
              void Function(
                Pointer<LibreOfficeKitDocument>,
                int,
                Pointer<UnsignedChar>,
                int,
                int,
                int,
                int,
                double,
              )
            >()(_doc, windowId, buffer.cast(), x, y, w, h, dpiScale);
      } else {
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
            >()(_doc, windowId, buffer.cast(), x, y, w, h);
      }
      return Uint8List.fromList(buffer.asTypedList(w * h * 4));
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void postWindow(int windowId, int action) => using(
    (a) => _c.postWindow
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            int,
            int,
            Pointer<Char>,
          )
        >()(_doc, windowId, action, _str('', a)),
  );

  @override
  void postWindowKeyEvent(int windowId, int type, int charCode, int keyCode) =>
      _c.postWindowKeyEvent
          .asFunction<
            void Function(Pointer<LibreOfficeKitDocument>, int, int, int, int)
          >()(_doc, windowId, type, charCode, keyCode);

  @override
  void postWindowMouseEvent(
    int windowId,
    int type,
    int x,
    int y,
    int count,
    int buttons,
    int mods,
  ) => _c.postWindowMouseEvent
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
      >()(_doc, windowId, type, x, y, count, buttons, mods);

  @override
  void postWindowExtTextInput(int windowId, int type, String text) => using(
    (a) => _c.postWindowExtTextInputEvent
        .asFunction<
          void Function(
            Pointer<LibreOfficeKitDocument>,
            int,
            int,
            Pointer<Char>,
          )
        >()(_doc, windowId, type, _str(text, a)),
  );

  @override
  void destroy() => _c.destroy
      .asFunction<void Function(Pointer<LibreOfficeKitDocument>)>()(_doc);
}
