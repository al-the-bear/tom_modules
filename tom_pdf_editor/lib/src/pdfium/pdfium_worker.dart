// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDFium engine isolate's side: every PDFium call of the process runs
/// here, one at a time, since PDFium is not thread-safe.
///
/// Requests arrive as `[id, op, args…]`; answers go back as
/// `[id, 'ok', value]`, `[id, 'err', message]`, and for a search
/// `[id, 'hit', …]` … `[id, 'done']`. Commands run in order; renders run
/// after them, by priority, and a render cancelled before it starts is
/// dropped.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../engine/xref_fix.dart';
import 'pdfium_bindings.g.dart';

/// The isolate's entry point: `[SendPort reply, String libraryPath]`.
void pdfiumWorkerMain(List<Object?> args) {
  final reply = args[0] as SendPort;
  final libraryPath = args[1] as String;
  final port = ReceivePort();
  final _Worker worker;
  try {
    worker = _Worker(PdfiumBindings(DynamicLibrary.open(libraryPath)), reply);
    worker.init();
  } catch (e) {
    reply.send(['init', 'err', '$e']);
    port.close();
    return;
  }
  reply.send(['init', 'ok', port.sendPort]);
  port.listen((message) {
    final list = message as List<Object?>;
    if (list[1] == 'cancel') {
      worker.cancelled.add(list[2] as int);
      return;
    }
    if (list[1] == 'dispose') {
      worker.dispose();
      reply.send([list[0], 'ok', null]);
      port.close();
      return;
    }
    worker.enqueue(list);
  });
}

/// One page held open: the page, its text page, and its form-fill state.
final class _OpenPage {
  _OpenPage(this.page, this.width, this.height);
  final FPDF_PAGE page;
  final double width;
  final double height;
  FPDF_TEXTPAGE text = nullptr;
}

/// One open document.
final class _Doc {
  _Doc(this.doc);
  final FPDF_DOCUMENT doc;
  FPDF_FORMHANDLE form = nullptr;
  Pointer<FPDF_FORMFILLINFO> formInfo = nullptr;

  /// The page window: open pages, least recently used first.
  final pages = <int, _OpenPage>{};
}

const _pageWindow = 12;

final class _Worker {
  _Worker(this.b, this.reply);

  final PdfiumBindings b;
  final SendPort reply;
  final docs = <int, _Doc>{};
  var _nextDoc = 1;

  final _commands = Queue<List<Object?>>();
  final _renders = <List<Object?>>[];
  final cancelled = <int>{};
  bool _pumping = false;

  NativeCallable<
    Void Function(
      Pointer<FPDF_FORMFILLINFO>,
      FPDF_PAGE,
      Double,
      Double,
      Double,
      Double,
    )
  >?
  _invalidate;

  void init() {
    final config = calloc<FPDF_LIBRARY_CONFIG>();
    try {
      config.ref.version = 2; // no V8, no font paths
      b.FPDF_InitLibraryWithConfig(config);
    } finally {
      calloc.free(config);
    }
  }

  void dispose() {
    for (final id in docs.keys.toList()) {
      _closeDoc(id);
    }
    _invalidate?.close();
    b.FPDF_DestroyLibrary();
  }

  void enqueue(List<Object?> message) {
    if (message[1] == 'render') {
      _renders.add(message);
    } else {
      _commands.add(message);
    }
    if (!_pumping) {
      _pumping = true;
      scheduleMicrotask(_pump);
    }
  }

  Future<void> _pump() async {
    while (_commands.isNotEmpty || _renders.isNotEmpty) {
      final List<Object?> job;
      if (_commands.isNotEmpty) {
        job = _commands.removeFirst();
      } else {
        // Highest priority (lowest number) first, then oldest.
        var best = 0;
        for (var i = 1; i < _renders.length; i++) {
          if ((_renders[i][3] as int) < (_renders[best][3] as int)) best = i;
        }
        job = _renders.removeAt(best);
        final ticket = job[4] as int?;
        if (ticket != null && cancelled.remove(ticket)) {
          reply.send([job[0], 'ok', null]);
          continue;
        }
      }
      _run(job);
      // Let new requests and cancels in between jobs.
      await Future<void>.delayed(Duration.zero);
    }
    _pumping = false;
  }

  void _run(List<Object?> job) {
    final id = job[0];
    try {
      final result = switch (job[1]) {
        'open' => _open(job[2] as String, job[3] as String?),
        'close' => _closeDoc(job[2] as int),
        'render' => _render(job[2] as List<Object?>),
        'charCount' => _charCount(job[2] as int, job[3] as int),
        'charIndexAt' => _charIndexAt(
          job[2] as int,
          job[3] as int,
          job[4] as double,
          job[5] as double,
        ),
        'rangeRects' => _rangeRects(
          job[2] as int,
          job[3] as int,
          job[4] as int,
          job[5] as int,
        ),
        'text' => _text(
          job[2] as int,
          job[3] as int,
          job[4] as int,
          job[5] as int,
        ),
        'find' => _findPage(job),
        'linkAt' => _linkAt(
          job[2] as int,
          job[3] as int,
          job[4] as double,
          job[5] as double,
        ),
        'save' => _save(job[2] as int, job[3] as String),
        'saveCopy' => _save(
          job[2] as int,
          job[3] as String,
          flags: job[4] == true ? FPDF_REMOVE_SECURITY : 0,
        ),
        'annots' => _annotations(job[2] as int, job[3] as int),
        'addAnnot' => _addAnnotation(
          job[2] as int,
          job[3] as int,
          job[4] as List<Object?>,
        ),
        'updateAnnot' => _updateAnnotation(
          job[2] as int,
          job[3] as int,
          job[4] as String,
          job[5] as List<Object?>,
        ),
        'removeAnnot' => _removeAnnotation(
          job[2] as int,
          job[3] as int,
          job[4] as String,
        ),
        _ => throw ArgumentError('unknown op ${job[1]}'),
      };
      if (result is _Streaming) return; // it answers itself
      reply.send([id, 'ok', result]);
    } catch (e) {
      reply.send([id, 'err', '$e']);
    }
  }

  // --------------------------------------------------------------- documents

  /// `['opened', handle, [w, h, …], permissions, securityRevision,
  /// fileVersion, outline, formType]` or `['failed', errorCode, message]`.
  List<Object?> _open(String path, String? password) {
    final doc = using((a) {
      return b.FPDF_LoadDocument(
        path.toNativeUtf8(allocator: a).cast(),
        password == null ? nullptr : password.toNativeUtf8(allocator: a).cast(),
      );
    });
    if (doc == nullptr) {
      final code = b.FPDF_GetLastError();
      return ['failed', code, _errorText(code)];
    }
    final handle = _nextDoc++;
    final d = _Doc(doc);
    docs[handle] = d;
    final count = b.FPDF_GetPageCount(doc);
    final sizes = <double>[];
    using((a) {
      final size = a<FS_SIZEF>();
      for (var i = 0; i < count; i++) {
        if (b.FPDF_GetPageSizeByIndexF(doc, i, size) != 0) {
          sizes
            ..add(size.ref.width)
            ..add(size.ref.height);
        } else {
          sizes
            ..add(612)
            ..add(792);
        }
      }
    });
    final version = using((a) {
      final v = a<Int>();
      return b.FPDF_GetFileVersion(doc, v) != 0 ? v.value : 0;
    });
    final formType = b.FPDF_GetFormType(doc);
    if (formType != 0) _initForm(d);
    return [
      'opened',
      handle,
      sizes,
      b.FPDF_GetDocPermissions(doc),
      b.FPDF_GetSecurityHandlerRevision(doc),
      version,
      _outline(doc, nullptr, 0, [0]),
      formType,
    ];
  }

  static String _errorText(int code) => switch (code) {
    1 => 'unknown error',
    2 => 'file not found or could not be opened',
    3 => 'not a PDF, or damaged',
    4 => 'password required or incorrect',
    5 => 'unsupported security scheme',
    6 => 'page not found or content error',
    _ => 'error $code',
  };

  /// The outline as nested `[title, page, children]` lists, at most 10 000
  /// entries and 32 levels (a loop in a damaged file ends there).
  List<Object?> _outline(
    FPDF_DOCUMENT doc,
    FPDF_BOOKMARK parent,
    int depth,
    List<int> seen,
  ) {
    final entries = <Object?>[];
    if (depth > 32) return entries;
    var bm = b.FPDFBookmark_GetFirstChild(doc, parent);
    while (bm != nullptr && seen[0] < 10000) {
      seen[0]++;
      final title = _wideString(
        (buf, len) => b.FPDFBookmark_GetTitle(bm, buf, len),
      );
      final dest = b.FPDFBookmark_GetDest(doc, bm);
      final page = dest == nullptr
          ? null
          : b.FPDFDest_GetDestPageIndex(doc, dest);
      entries.add([
        title,
        page != null && page >= 0 ? page : null,
        _outline(doc, bm, depth + 1, seen),
      ]);
      bm = b.FPDFBookmark_GetNextSibling(doc, bm);
    }
    return entries;
  }

  /// A UTF-16LE string from a PDFium getter that takes (buffer, bytes) and
  /// answers the bytes needed, terminator included.
  String _wideString(int Function(Pointer<Void> buf, int len) get) {
    final needed = get(nullptr, 0);
    if (needed <= 2) return '';
    final buf = calloc<Uint16>(needed ~/ 2);
    try {
      get(buf.cast(), needed);
      return String.fromCharCodes(buf.asTypedList(needed ~/ 2 - 1));
    } finally {
      calloc.free(buf);
    }
  }

  void _initForm(_Doc d) {
    _invalidate ??= NativeCallable.isolateLocal(_onInvalidate);
    final info = calloc<FPDF_FORMFILLINFO>();
    info.ref.version = 1;
    info.ref.FFI_Invalidate = _invalidate!.nativeFunction;
    d.formInfo = info;
    d.form = b.FPDFDOC_InitFormFillEnvironment(d.doc, info);
  }

  static void _onInvalidate(
    Pointer<FPDF_FORMFILLINFO> info,
    FPDF_PAGE page,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    // Display only in this todo: fields are drawn on every render.
  }

  Object? _closeDoc(int handle) {
    final d = docs.remove(handle);
    if (d == null) return null;
    for (final p in d.pages.values) {
      _closePage(d, p);
    }
    d.pages.clear();
    if (d.form != nullptr) b.FPDFDOC_ExitFormFillEnvironment(d.form);
    if (d.formInfo != nullptr) calloc.free(d.formInfo);
    b.FPDF_CloseDocument(d.doc);
    return null;
  }

  // ------------------------------------------------------------------- pages

  _Doc _docOf(int handle) =>
      docs[handle] ?? (throw StateError('document $handle is not open'));

  /// The page, from the window or loaded into it (the least recently used
  /// page is closed beyond the window).
  _OpenPage _page(_Doc d, int index) {
    final open = d.pages.remove(index);
    if (open != null) {
      d.pages[index] = open;
      return open;
    }
    final page = b.FPDF_LoadPage(d.doc, index);
    if (page == nullptr) throw StateError('page $index could not be loaded');
    if (d.form != nullptr) b.FORM_OnAfterLoadPage(page, d.form);
    final p = _OpenPage(
      page,
      b.FPDF_GetPageWidthF(page),
      b.FPDF_GetPageHeightF(page),
    );
    d.pages[index] = p;
    while (d.pages.length > _pageWindow) {
      final oldest = d.pages.keys.first;
      _closePage(d, d.pages.remove(oldest)!);
    }
    return p;
  }

  void _closePage(_Doc d, _OpenPage p) {
    if (p.text != nullptr) b.FPDFText_ClosePage(p.text);
    if (d.form != nullptr) b.FORM_OnBeforeClosePage(p.page, d.form);
    b.FPDF_ClosePage(p.page);
  }

  FPDF_TEXTPAGE _textPage(_Doc d, _OpenPage p) {
    if (p.text == nullptr) p.text = b.FPDFText_LoadPage(p.page);
    return p.text;
  }

  // Coordinates: view points are mapped through FPDF_PageToDevice /
  // FPDF_DeviceToPage at 100 device units per point, which applies the
  // page's rotation.
  static const _k = 100;

  (double, double) _toView(_OpenPage p, double px, double py) => using((a) {
    final dx = a<Int>();
    final dy = a<Int>();
    b.FPDF_PageToDevice(
      p.page,
      0,
      0,
      (p.width * _k).round(),
      (p.height * _k).round(),
      0,
      px,
      py,
      dx,
      dy,
    );
    return (dx.value / _k, dy.value / _k);
  });

  (double, double) _toPage(_OpenPage p, double vx, double vy) => using((a) {
    final px = a<Double>();
    final py = a<Double>();
    b.FPDF_DeviceToPage(
      p.page,
      0,
      0,
      (p.width * _k).round(),
      (p.height * _k).round(),
      0,
      (vx * _k).round(),
      (vy * _k).round(),
      px,
      py,
    );
    return (px.value, py.value);
  });

  /// A page-space rectangle as `[left, top, right, bottom]` in view points.
  List<double> _rectToView(
    _OpenPage p,
    double l,
    double t,
    double r,
    double bo,
  ) {
    final (x1, y1) = _toView(p, l, t);
    final (x2, y2) = _toView(p, r, bo);
    return [
      x1 < x2 ? x1 : x2,
      y1 < y2 ? y1 : y2,
      x1 < x2 ? x2 : x1,
      y1 < y2 ? y2 : y1,
    ];
  }

  // --------------------------------------------------------------- rendering

  /// `[doc, page, scale, x, y, pxW, pxH]` → `[pxW, pxH, TransferableTypedData]`.
  Object? _render(List<Object?> args) {
    final d = _docOf(args[0] as int);
    final p = _page(d, args[1] as int);
    final scale = args[2] as double;
    final x = args[3] as int;
    final y = args[4] as int;
    final w = args[5] as int;
    final h = args[6] as int;
    final buffer = calloc<Uint8>(w * h * 4);
    final matrix = calloc<FS_MATRIX>();
    final clip = calloc<FS_RECTF>();
    try {
      final bitmap = b.FPDFBitmap_CreateEx(
        w,
        h,
        FPDFBitmap_BGRA,
        buffer.cast(),
        w * 4,
      );
      if (bitmap == nullptr) throw StateError('bitmap $w × $h not created');
      try {
        b.FPDFBitmap_FillRect(bitmap, 0, 0, w, h, 0xFFFFFFFF);
        matrix.ref
          ..a = scale
          ..b = 0
          ..c = 0
          ..d = scale
          ..e = -x.toDouble()
          ..f = -y.toDouble();
        clip.ref
          ..left = 0
          ..top = 0
          ..right = w.toDouble()
          ..bottom = h.toDouble();
        b.FPDF_RenderPageBitmapWithMatrix(
          bitmap,
          p.page,
          matrix,
          clip,
          FPDF_ANNOT | FPDF_LCD_TEXT,
        );
        if (d.form != nullptr) {
          b.FPDF_FFLDraw(
            d.form,
            bitmap,
            p.page,
            -x,
            -y,
            (p.width * scale).round(),
            (p.height * scale).round(),
            0,
            FPDF_ANNOT | FPDF_LCD_TEXT,
          );
        }
      } finally {
        b.FPDFBitmap_Destroy(bitmap);
      }
      return [
        w,
        h,
        TransferableTypedData.fromList([buffer.asTypedList(w * h * 4)]),
      ];
    } finally {
      calloc.free(buffer);
      calloc.free(matrix);
      calloc.free(clip);
    }
  }

  // -------------------------------------------------------------------- text

  int _charCount(int doc, int page) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final count = b.FPDFText_CountChars(_textPage(d, p));
    return count < 0 ? 0 : count;
  }

  int _charIndexAt(int doc, int page, double x, double y) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final (px, py) = _toPage(p, x, y);
    return b.FPDFText_GetCharIndexAtPos(_textPage(d, p), px, py, 5, 5);
  }

  /// `[l, t, r, b, l, t, r, b, …]` in view points.
  List<double> _rangeRects(int doc, int page, int start, int count) {
    final d = _docOf(doc);
    final p = _page(d, page);
    return _rects(p, _textPage(d, p), start, count);
  }

  List<double> _rects(_OpenPage p, FPDF_TEXTPAGE tp, int start, int count) {
    final n = b.FPDFText_CountRects(tp, start, count);
    final out = <double>[];
    using((a) {
      final l = a<Double>();
      final t = a<Double>();
      final r = a<Double>();
      final bo = a<Double>();
      for (var i = 0; i < n; i++) {
        if (b.FPDFText_GetRect(tp, i, l, t, r, bo) != 0) {
          out.addAll(_rectToView(p, l.value, t.value, r.value, bo.value));
        }
      }
    });
    return out;
  }

  /// `[text, skipped]`: characters without a Unicode mapping or in the
  /// private use area are left out.
  List<Object?> _text(int doc, int page, int start, int count) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final tp = _textPage(d, p);
    final total = b.FPDFText_CountChars(tp);
    if (start < 0 || start >= total || count <= 0) return ['', 0];
    final n = count > total - start ? total - start : count;
    final buf = calloc<UnsignedShort>(n + 1);
    try {
      final written = b.FPDFText_GetText(tp, start, n, buf);
      final units = buf.cast<Uint16>().asTypedList(
        written > 0 ? written - 1 : 0,
      );
      final kept = <int>[];
      var skipped = 0;
      for (var i = 0; i < units.length; i++) {
        final u = b.FPDFText_GetUnicode(tp, start + i);
        final unit = units[i];
        final isLineBreak = unit == 10 || unit == 13;
        if (!isLineBreak && (u == 0 || (u >= 0xE000 && u <= 0xF8FF))) {
          skipped++;
          continue;
        }
        kept.add(unit);
      }
      return [String.fromCharCodes(kept), skipped];
    } finally {
      calloc.free(buf);
    }
  }

  // ------------------------------------------------------------------ search

  /// Searches one page per job and re-queues itself for the next, so other
  /// requests run in between. `job`: `[id, 'find', doc, term, flags, from,
  /// done]`.
  Object _findPage(List<Object?> job) {
    final id = job[0];
    final d = docs[job[2] as int];
    if (d == null) {
      reply.send([id, 'done']);
      return const _Streaming();
    }
    final term = job[3] as String;
    final flags = job[4] as int;
    final from = job[5] as int;
    final done = job[6] as int;
    final count = b.FPDF_GetPageCount(d.doc);
    if (done >= count || term.isEmpty) {
      reply.send([id, 'done']);
      return const _Streaming();
    }
    final index = (from + done) % count;
    final p = _page(d, index);
    final tp = _textPage(d, p);
    final units = term.codeUnits;
    final wide = calloc<UnsignedShort>(units.length + 1);
    try {
      for (var i = 0; i < units.length; i++) {
        wide[i] = units[i];
      }
      final handle = b.FPDFText_FindStart(tp, wide, flags, 0);
      if (handle != nullptr) {
        try {
          while (b.FPDFText_FindNext(handle) != 0) {
            final start = b.FPDFText_GetSchResultIndex(handle);
            final n = b.FPDFText_GetSchCount(handle);
            reply.send([id, 'hit', index, start, n, _rects(p, tp, start, n)]);
          }
        } finally {
          b.FPDFText_FindClose(handle);
        }
      }
    } finally {
      calloc.free(wide);
    }
    _commands.add([id, 'find', job[2], term, flags, from, done + 1]);
    return const _Streaming();
  }

  // ------------------------------------------------------------------- links

  /// `['uri', address]`, `['page', index]` or `null`.
  List<Object?>? _linkAt(int doc, int page, double x, double y) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final (px, py) = _toPage(p, x, y);
    final link = b.FPDFLink_GetLinkAtPoint(p.page, px, py);
    if (link == nullptr) return null;
    final action = b.FPDFLink_GetAction(link);
    if (action != nullptr) {
      final type = b.FPDFAction_GetType(action);
      if (type == PDFACTION_URI) {
        final needed = b.FPDFAction_GetURIPath(d.doc, action, nullptr, 0);
        if (needed <= 1) return null;
        final buf = calloc<Uint8>(needed);
        try {
          b.FPDFAction_GetURIPath(d.doc, action, buf.cast(), needed);
          return ['uri', String.fromCharCodes(buf.asTypedList(needed - 1))];
        } finally {
          calloc.free(buf);
        }
      }
      if (type == PDFACTION_GOTO) {
        final dest = b.FPDFAction_GetDest(d.doc, action);
        if (dest == nullptr) return null;
        final target = b.FPDFDest_GetDestPageIndex(d.doc, dest);
        return target < 0 ? null : ['page', target];
      }
      return null; // other action types are ignored
    }
    final dest = b.FPDFLink_GetDest(d.doc, link);
    if (dest == nullptr) return null;
    final target = b.FPDFDest_GetDestPageIndex(d.doc, dest);
    return target < 0 ? null : ['page', target];
  }

  // ------------------------------------------------------------------ saving

  RandomAccessFile? _sink;

  /// Saves to [target]: incrementally by default, then the cross-reference
  /// fix; with other [flags] (`FPDF_REMOVE_SECURITY`) a full copy. Answers
  /// `null`, or the error in words.
  String? _save(int doc, String target, {int? flags}) {
    final d = _docOf(doc);
    final callable =
        NativeCallable<
          Int Function(Pointer<FPDF_FILEWRITE>, Pointer<Void>, UnsignedLong)
        >.isolateLocal(_writeBlock, exceptionalReturn: 0);
    final writer = calloc<FPDF_FILEWRITE>();
    final file = File(target).openSync(mode: FileMode.write);
    _sink = file;
    try {
      writer.ref.version = 1;
      writer.ref.WriteBlock = callable.nativeFunction;
      final ok = b.FPDF_SaveAsCopy(d.doc, writer, flags ?? FPDF_INCREMENTAL);
      file.flushSync();
      if (ok == 0) return 'FPDF_SaveAsCopy failed';
    } finally {
      file.closeSync();
      _sink = null;
      calloc.free(writer);
      callable.close();
    }
    if (flags == null) fixXrefInFile(target);
    return null;
  }

  // ------------------------------------------------------------- annotations

  static const _kinds = {
    FPDF_ANNOT_HIGHLIGHT: 0, // PdfAnnotationKind.highlight
    FPDF_ANNOT_TEXT: 1, // note
    FPDF_ANNOT_INK: 2, // ink
  };

  static int _subtypeOf(int kind) => switch (kind) {
    0 => FPDF_ANNOT_HIGHLIGHT,
    1 => FPDF_ANNOT_TEXT,
    2 => FPDF_ANNOT_INK,
    _ => throw ArgumentError('cannot create annotation kind $kind'),
  };

  /// Every annotation of the page, as wire lists (`PdfAnnotation.toWire`).
  List<Object?> _annotations(int doc, int page) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final count = b.FPDFPage_GetAnnotCount(p.page);
    final out = <Object?>[];
    for (var i = 0; i < count; i++) {
      final a = b.FPDFPage_GetAnnot(p.page, i);
      if (a == nullptr) continue;
      try {
        out.add(_read(p, a, i));
      } finally {
        b.FPDFPage_CloseAnnot(a);
      }
    }
    return out;
  }

  List<Object?> _read(_OpenPage p, FPDF_ANNOTATION a, int index) {
    final subtype = b.FPDFAnnot_GetSubtype(a);
    final kind = _kinds[subtype] ?? 3;
    final nm = _string(a, 'NM');
    final rect = using((m) {
      final r = m<FS_RECTF>();
      if (b.FPDFAnnot_GetRect(a, r) == 0) return [0.0, 0.0, 0.0, 0.0];
      return _rectToView(p, r.ref.left, r.ref.top, r.ref.right, r.ref.bottom);
    });
    final color = using((m) {
      final r = m<UnsignedInt>();
      final g = m<UnsignedInt>();
      final bl = m<UnsignedInt>();
      final al = m<UnsignedInt>();
      if (b.FPDFAnnot_GetColor(
            a,
            FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            bl,
            al,
          ) ==
          0) {
        return 0xFFFFEB3B;
      }
      return (al.value << 24) | (r.value << 16) | (g.value << 8) | bl.value;
    });
    final quads = <double>[];
    final strokes = <Object?>[];
    var width = 2.0;
    if (kind == 0) {
      using((m) {
        final q = m<FS_QUADPOINTSF>();
        final n = b.FPDFAnnot_CountAttachmentPoints(a);
        for (var i = 0; i < n; i++) {
          if (b.FPDFAnnot_GetAttachmentPoints(a, i, q) == 0) continue;
          final xs = [q.ref.x1, q.ref.x2, q.ref.x3, q.ref.x4];
          final ys = [q.ref.y1, q.ref.y2, q.ref.y3, q.ref.y4];
          quads.addAll(
            _rectToView(
              p,
              xs.reduce((u, v) => u < v ? u : v),
              ys.reduce((u, v) => u > v ? u : v),
              xs.reduce((u, v) => u > v ? u : v),
              ys.reduce((u, v) => u < v ? u : v),
            ),
          );
        }
      });
    }
    if (kind == 2) {
      final n = b.FPDFAnnot_GetInkListCount(a);
      for (var i = 0; i < n; i++) {
        final len = b.FPDFAnnot_GetInkListPath(a, i, nullptr, 0);
        if (len <= 0) continue;
        final buf = calloc<FS_POINTF>(len);
        try {
          b.FPDFAnnot_GetInkListPath(a, i, buf, len);
          final stroke = <double>[];
          for (var k = 0; k < len; k++) {
            final (x, y) = _toView(p, buf[k].x, buf[k].y);
            stroke
              ..add(x)
              ..add(y);
          }
          strokes.add(stroke);
        } finally {
          calloc.free(buf);
        }
      }
      using((m) {
        final h = m<Float>();
        final v = m<Float>();
        final w = m<Float>();
        if (b.FPDFAnnot_GetBorder(a, h, v, w) != 0 && w.value > 0) {
          width = w.value;
        }
      });
    }
    return [
      nm.isEmpty ? '#$index' : nm,
      kind,
      subtype,
      rect,
      color,
      quads,
      strokes,
      width,
      _string(a, 'Contents'),
      _string(a, 'T'),
      _string(a, 'M'),
    ];
  }

  String _string(FPDF_ANNOTATION a, String key) => using((m) {
    final k = key.toNativeUtf8(allocator: m).cast<Char>();
    final needed = b.FPDFAnnot_GetStringValue(a, k, nullptr, 0);
    if (needed <= 2) return '';
    final buf = calloc<Uint16>(needed ~/ 2);
    try {
      b.FPDFAnnot_GetStringValue(a, k, buf.cast(), needed);
      return String.fromCharCodes(buf.asTypedList(needed ~/ 2 - 1));
    } finally {
      calloc.free(buf);
    }
  });

  void _setString(FPDF_ANNOTATION a, String key, String value) => using((m) {
    final units = value.codeUnits;
    final wide = m<UnsignedShort>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      wide[i] = units[i];
    }
    wide[units.length] = 0;
    b.FPDFAnnot_SetStringValue(a, key.toNativeUtf8(allocator: m).cast(), wide);
  });

  /// Finds annotation [match] (`NM`, or `#<index>`) on the page; the caller
  /// closes it.
  (FPDF_ANNOTATION, int) _find(_OpenPage p, String match) {
    final count = b.FPDFPage_GetAnnotCount(p.page);
    if (match.startsWith('#')) {
      final i = int.parse(match.substring(1));
      if (i >= count) throw StateError('no annotation $match');
      return (b.FPDFPage_GetAnnot(p.page, i), i);
    }
    for (var i = 0; i < count; i++) {
      final a = b.FPDFPage_GetAnnot(p.page, i);
      if (a == nullptr) continue;
      if (_string(a, 'NM') == match) return (a, i);
      b.FPDFPage_CloseAnnot(a);
    }
    throw StateError('no annotation $match');
  }

  /// Writes a wire annotation's state into [a].
  void _write(_OpenPage p, FPDF_ANNOTATION a, List<Object?> w) {
    // An appearance stream of the file would hide the change (PDFium also
    // refuses colours on such annotations): clear it, so PDFium and the
    // viewers generate the appearance from the values, as for new ones.
    b.FPDFAnnot_SetAP(a, FPDF_ANNOT_APPEARANCEMODE_NORMAL, nullptr);
    final r = (w[3] as List).cast<double>();
    using((m) {
      final rect = m<FS_RECTF>();
      final (l, t) = _toPage(p, r[0], r[1]);
      final (rr, bo) = _toPage(p, r[2], r[3]);
      rect.ref
        ..left = l < rr ? l : rr
        ..right = l < rr ? rr : l
        ..top = t > bo ? t : bo
        ..bottom = t > bo ? bo : t;
      b.FPDFAnnot_SetRect(a, rect);
    });
    final color = w[4] as int;
    b.FPDFAnnot_SetColor(
      a,
      FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
      (color >> 16) & 0xFF,
      (color >> 8) & 0xFF,
      color & 0xFF,
      (color >> 24) & 0xFF,
    );
    final kind = w[1] as int;
    if (kind == 0) {
      final q = (w[5] as List).cast<double>();
      using((m) {
        final quad = m<FS_QUADPOINTSF>();
        final existing = b.FPDFAnnot_CountAttachmentPoints(a);
        for (var i = 0, n = 0; i + 3 < q.length; i += 4, n++) {
          final (x1, y1) = _toPage(p, q[i], q[i + 1]);
          final (x2, y2) = _toPage(p, q[i + 2], q[i + 3]);
          final left = x1 < x2 ? x1 : x2;
          final right = x1 < x2 ? x2 : x1;
          final top = y1 > y2 ? y1 : y2;
          final bottom = y1 > y2 ? y2 : y1;
          // PDF order: upper left, upper right, lower left, lower right.
          quad.ref
            ..x1 = left
            ..y1 = top
            ..x2 = right
            ..y2 = top
            ..x3 = left
            ..y3 = bottom
            ..x4 = right
            ..y4 = bottom;
          if (n < existing) {
            b.FPDFAnnot_SetAttachmentPoints(a, n, quad);
          } else {
            b.FPDFAnnot_AppendAttachmentPoints(a, quad);
          }
        }
      });
    }
    if (kind == 2) {
      b.FPDFAnnot_RemoveInkList(a);
      for (final stroke in (w[6] as List).cast<List>()) {
        final n = stroke.length ~/ 2;
        if (n == 0) continue;
        final pts = calloc<FS_POINTF>(n);
        try {
          for (var k = 0; k < n; k++) {
            final (x, y) = _toPage(
              p,
              (stroke[2 * k] as num).toDouble(),
              (stroke[2 * k + 1] as num).toDouble(),
            );
            pts[k]
              ..x = x
              ..y = y;
          }
          b.FPDFAnnot_AddInkStroke(a, pts, n);
        } finally {
          calloc.free(pts);
        }
      }
      b.FPDFAnnot_SetBorder(a, 0, 0, (w[7] as num).toDouble());
    }
    _setString(a, 'Contents', w[8] as String);
    _setString(a, 'T', w[9] as String);
    _setString(a, 'M', w[10] as String);
    _setString(a, 'NM', w[0] as String);
  }

  List<Object?> _addAnnotation(int doc, int page, List<Object?> w) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final a = b.FPDFPage_CreateAnnot(p.page, _subtypeOf(w[1] as int));
    if (a == nullptr) throw StateError('the annotation could not be created');
    try {
      b.FPDFAnnot_SetFlags(a, FPDF_ANNOT_FLAG_PRINT);
      _write(p, a, w);
      return _read(p, a, b.FPDFPage_GetAnnotIndex(p.page, a));
    } finally {
      b.FPDFPage_CloseAnnot(a);
    }
  }

  Object? _updateAnnotation(int doc, int page, String match, List<Object?> w) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final (a, _) = _find(p, match);
    try {
      _write(p, a, w);
    } finally {
      b.FPDFPage_CloseAnnot(a);
    }
    return null;
  }

  Object? _removeAnnotation(int doc, int page, String match) {
    final d = _docOf(doc);
    final p = _page(d, page);
    final (a, index) = _find(p, match);
    b.FPDFPage_CloseAnnot(a);
    if (b.FPDFPage_RemoveAnnot(p.page, index) == 0) {
      throw StateError('the annotation could not be removed');
    }
    return null;
  }

  int _writeBlock(Pointer<FPDF_FILEWRITE> self, Pointer<Void> data, int size) {
    final sink = _sink;
    if (sink == null) return 0;
    sink.writeFromSync(data.cast<Uint8>().asTypedList(size));
    return 1;
  }
}

/// Applies the cross-reference fix to the file at [path]: reads its tail,
/// finds the object `startxref` names, and when it is a cross-reference
/// stream without `/Type`, rewrites the file from there with `/Type/XRef `
/// inserted. Returns whether it changed the file.
bool fixXrefInFile(String path) {
  final file = File(path).openSync(mode: FileMode.append);
  try {
    final length = file.lengthSync();
    final tailStart = length > 1024 ? length - 1024 : 0;
    file.setPositionSync(tailStart);
    final offset = startxrefOffset(file.readSync(length - tailStart));
    if (offset == null || offset < 0 || offset >= length) return false;
    // The object runs to the end of the file; refuse anything unexpectedly
    // large rather than reading it into memory.
    if (length - offset > 64 * 1024 * 1024) return false;
    file.setPositionSync(offset);
    final fixed = fixXrefObject(file.readSync(length - offset));
    if (fixed == null) return false;
    // Cut the file at the object and append the fixed object: the same as
    // writing in place, whether or not the platform's append mode allows
    // writes before the end.
    file.truncateSync(offset);
    file.setPositionSync(offset);
    file.writeFromSync(fixed);
    return true;
  } finally {
    file.closeSync();
  }
}

/// Marks a job that answers itself (search).
final class _Streaming {
  const _Streaming();
}
