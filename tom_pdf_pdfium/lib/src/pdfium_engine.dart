// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:tom_pdf_editor/tom_pdf_editor.dart';

import 'pdfium_bindings.g.dart' show FPDF_REMOVE_SECURITY;
import 'pdfium_trail.dart';
import 'pdfium_worker.dart';

/// [TomPdfEngine] over PDFium: one long-lived worker isolate that makes every
/// PDFium call of the process (PDFium is not thread-safe). [acquire] gives
/// every PDF tab the one shared engine; [release] gives a tab's share up, and
/// the last one ends it (`FPDF_DestroyLibrary`).
final class PdfiumEngine implements TomPdfEngine {
  PdfiumEngine._(this._isolate, this._port, this._inbox);

  final Isolate _isolate;
  final SendPort _port;
  final ReceivePort _inbox;
  final _pending = <int, Completer<Object?>>{};
  final _streams = <int, StreamController<PdfSearchHit>>{};
  var _nextId = 1;
  bool _disposed = false;

  static PdfiumEngine? _shared;
  static Future<PdfiumEngine>? _starting;
  var _users = 0;

  /// The process's shared engine on the library at [libraryPath], started on
  /// first use; each call is one share, given up with [release].
  static Future<PdfiumEngine> acquire(String libraryPath) async {
    final engine =
        _shared ??
        await (_starting ??= start(libraryPath).whenComplete(() {
          _starting = null;
        }));
    _shared = engine;
    engine._users++;
    return engine;
  }

  @override
  Future<void> release() async {
    if (_users > 0) _users--;
    if (_users == 0) {
      if (identical(_shared, this)) _shared = null;
      await dispose();
    }
  }

  /// Starts an engine of its own on the library at [libraryPath] (`DynamicLibrary.open`
  /// and `FPDF_InitLibraryWithConfig` on the worker). Throws a [StateError]
  /// naming the failure when the library does not load.
  static Future<PdfiumEngine> start(String libraryPath) async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(pdfiumWorkerMain, [
      inbox.sendPort,
      libraryPath,
    ], debugName: 'PdfiumEngine');
    final first = Completer<List<Object?>>();
    late final PdfiumEngine engine;
    inbox.listen((message) {
      final list = message as List<Object?>;
      if (list[0] == 'init') {
        first.complete(list);
        return;
      }
      engine._onReply(list);
    });
    final init = await first.future;
    if (init[1] != 'ok') {
      inbox.close();
      isolate.kill();
      throw StateError('PDFium did not load from $libraryPath: ${init[2]}');
    }
    pdfiumTrail('engine started ($libraryPath)');
    return engine = PdfiumEngine._(isolate, init[2] as SendPort, inbox);
  }

  void _onReply(List<Object?> reply) {
    final id = reply[0] as int;
    switch (reply[1]) {
      case 'hit':
        _streams[id]?.add(
          PdfSearchHit(
            reply[2] as int,
            reply[3] as int,
            reply[4] as int,
            _rectList(reply[5] as List<Object?>),
          ),
        );
      case 'done':
        unawaited(_streams.remove(id)?.close());
      case 'ok':
        _pending.remove(id)?.complete(reply[2]);
      case 'err':
        final error = StateError('PDFium: ${reply[2]}');
        final completer = _pending.remove(id);
        if (completer != null) {
          completer.completeError(error);
        } else {
          _streams.remove(id)
            ?..addError(error)
            ..close();
        }
    }
  }

  Future<T> _call<T>(String op, List<Object?> args) {
    if (_disposed) return Future.error(StateError('the engine has ended'));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _port.send([id, op, ...args]);
    return completer.future.then((v) => v as T);
  }

  static List<PdfRect> _rectList(List<Object?> flat) => [
    for (var i = 0; i + 3 < flat.length; i += 4)
      PdfRect(
        flat[i] as double,
        flat[i + 1] as double,
        flat[i + 2] as double,
        flat[i + 3] as double,
      ),
  ];

  static List<PdfOutlineEntry> _outline(List<Object?> raw) => [
    for (final e in raw.cast<List<Object?>>())
      PdfOutlineEntry(
        e[0] as String,
        e[1] as int?,
        _outline(e[2] as List<Object?>),
      ),
  ];

  @override
  Future<PdfOpenResult> open(String path, {String? password}) async =>
      _opened(await _call<List<Object?>>('open', [path, password]));

  @override
  Future<PdfOpenResult> openBytes(Uint8List bytes, {String? password}) async =>
      _opened(
        await _call<List<Object?>>('openBytes', [
          TransferableTypedData.fromList([bytes]),
          password,
        ]),
      );

  @override
  Future<Uint8List> saveIncrementalBytes(int doc) async =>
      (await _call<TransferableTypedData>('saveBytes', [
        doc,
        null,
      ])).materialize().asUint8List();

  @override
  Future<Uint8List> saveCopyBytes(
    int doc, {
    bool removeSecurity = false,
  }) async => (await _call<TransferableTypedData>('saveBytes', [
    doc,
    removeSecurity ? FPDF_REMOVE_SECURITY : 0,
  ])).materialize().asUint8List();

  PdfOpenResult _opened(List<Object?> r) {
    if (r[0] == 'failed') {
      final error = switch (r[1] as int) {
        2 => PdfOpenError.file,
        3 => PdfOpenError.format,
        4 => PdfOpenError.password,
        5 => PdfOpenError.security,
        _ => PdfOpenError.unknown,
      };
      return PdfOpenResult.failed(error, r[2] as String);
    }
    final sizes = (r[2] as List<Object?>).cast<double>();
    return PdfOpenResult.opened(
      PdfDocumentInfo(
        handle: r[1] as int,
        pages: [
          for (var i = 0; i + 1 < sizes.length; i += 2)
            PdfPageSize(sizes[i], sizes[i + 1]),
        ],
        permissions: r[3] as int,
        securityRevision: r[4] as int,
        fileVersion: r[5] as int,
        outline: _outline(r[6] as List<Object?>),
        formType: switch (r[7] as int) {
          1 => PdfFormType.acroForm,
          2 => PdfFormType.xfaFull,
          3 => PdfFormType.xfaForeground,
          _ => PdfFormType.none,
        },
      ),
    );
  }

  @override
  Future<void> close(int doc) => _call<Object?>('close', [doc]);

  @override
  Future<PdfRendered?> render(
    int doc,
    int page, {
    required double scale,
    required int x,
    required int y,
    required int pxW,
    required int pxH,
    PdfRenderPriority priority = PdfRenderPriority.visible,
    int? ticket,
  }) async {
    if (_disposed) return Future.error(StateError('the engine has ended'));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _port.send([
      id,
      'render',
      [doc, page, scale, x, y, pxW, pxH],
      priority.index,
      ticket,
    ]);
    final r = await completer.future as List<Object?>?;
    if (r == null) return null; // cancelled
    return PdfRendered(
      r[0] as int,
      r[1] as int,
      (r[2] as TransferableTypedData).materialize().asUint8List(),
    );
  }

  @override
  void cancel(int ticket) {
    if (!_disposed) _port.send([0, 'cancel', ticket]);
  }

  @override
  Future<int> charCount(int doc, int page) =>
      _call<int>('charCount', [doc, page]);

  @override
  Future<int> charIndexAt(int doc, int page, double x, double y) =>
      _call<int>('charIndexAt', [doc, page, x, y]);

  @override
  Future<List<PdfRect>> rangeRects(
    int doc,
    int page,
    int start,
    int count,
  ) async => _rectList(
    await _call<List<Object?>>('rangeRects', [doc, page, start, count]),
  );

  @override
  Future<PdfText> text(int doc, int page, int start, int count) async {
    final r = await _call<List<Object?>>('text', [doc, page, start, count]);
    return PdfText(r[0] as String, r[1] as int);
  }

  @override
  Stream<PdfSearchHit> find(
    int doc,
    String term, {
    bool matchCase = false,
    bool wholeWord = false,
    int fromPage = 0,
  }) {
    final id = _nextId++;
    final controller = StreamController<PdfSearchHit>();
    _streams[id] = controller;
    final flags = (matchCase ? 1 : 0) | (wholeWord ? 2 : 0);
    _port.send([id, 'find', doc, term, flags, fromPage, 0]);
    return controller.stream;
  }

  @override
  Future<PdfLink?> linkAt(int doc, int page, double x, double y) async {
    final r = await _call<List<Object?>?>('linkAt', [doc, page, x, y]);
    if (r == null) return null;
    return r[0] == 'uri'
        ? PdfLink.uri(r[1] as String)
        : PdfLink.page(r[1] as int);
  }

  @override
  Future<List<PdfAnnotation>> annotations(int doc, int page) async => [
    for (final w in await _call<List<Object?>>('annots', [doc, page]))
      PdfAnnotation.fromWire(w! as List<Object?>),
  ];

  @override
  Future<PdfAnnotation> addAnnotation(
    int doc,
    int page,
    PdfAnnotation annotation,
  ) async => PdfAnnotation.fromWire(
    await _call<List<Object?>>('addAnnot', [doc, page, annotation.toWire()]),
  );

  @override
  Future<void> updateAnnotation(
    int doc,
    int page,
    String match,
    PdfAnnotation state,
  ) => _call<Object?>('updateAnnot', [doc, page, match, state.toWire()]);

  @override
  Future<void> removeAnnotation(int doc, int page, String match) =>
      _call<Object?>('removeAnnot', [doc, page, match]);

  @override
  Future<List<PdfFormField>> formFields(int doc, int page) async => [
    for (final w in await _call<List<Object?>>('formFields', [doc, page]))
      PdfFormField.fromWire(w! as List<Object?>),
  ];

  @override
  Future<PdfFormField?> formFieldAt(
    int doc,
    int page,
    double x,
    double y,
  ) async {
    final w = await _call<List<Object?>?>('formFieldAt', [doc, page, x, y]);
    return w == null ? null : PdfFormField.fromWire(w);
  }

  Future<PdfFormResult> _form(String op, List<Object?> args) async =>
      PdfFormResult.fromWire(await _call<List<Object?>>(op, args));

  @override
  Future<PdfFormResult> formClick(int doc, int page, double x, double y) =>
      _form('formClick', [doc, page, x, y]);

  @override
  Future<PdfFormResult> formText(int doc, String text) =>
      _form('formText', [doc, text]);

  @override
  Future<PdfFormResult> formKey(
    int doc,
    PdfFormKey key, {
    bool shift = false,
  }) => _form('formKey', [doc, key.index, shift]);

  @override
  Future<PdfFormResult> formUndo(int doc, {bool redo = false}) =>
      _form('formUndo', [doc, redo]);

  @override
  Future<PdfFormResult> formKillFocus(int doc) => _form('formKillFocus', [doc]);

  @override
  Future<PdfFormResult> formSetValue(
    int doc,
    int page,
    String name,
    PdfFieldType type,
    String value,
  ) => _form('formSetValue', [doc, page, name, type.index, value]);

  @override
  Future<String?> saveCopy(
    int doc,
    String target, {
    bool removeSecurity = false,
  }) => _call<String?>('saveCopy', [doc, target, removeSecurity]);

  @override
  Future<String?> saveIncremental(int doc, String target) =>
      _call<String?>('save', [doc, target]);

  /// Ends the engine now (`FPDF_DestroyLibrary`), whatever its shares.
  Future<void> dispose() async {
    if (_disposed) return;
    await _call<Object?>('dispose', const []);
    _disposed = true;
    _inbox.close();
    _isolate.kill();
    pdfiumTrail('engine ended');
  }
}
