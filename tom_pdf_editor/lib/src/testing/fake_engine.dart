// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:tom_file_session/tom_file_session.dart';

import '../engine/engine.dart';

/// A fake document: page sizes, the text of each page, links, a password.
///
/// Text is laid out on a grid: line `l` of a page (lines split on `\n`, the
/// line break itself a character) starts at ([kFakeLeft],
/// `kFakeTop + l * kFakeLineHeight`), each character [kFakeCharWidth] points
/// wide and [kFakeCharHeight] high.
class FakePdfDocument {
  FakePdfDocument({
    required this.pages,
    List<String>? texts,
    this.links = const {},
    this.password,
    this.permissions = 0xFFFFFFFF,
    this.securityRevision = -1,
    this.outline = const [],
    this.formType = PdfFormType.none,
    this.unmapped = const {},
    Map<int, List<PdfAnnotation>>? annotations,
    this.fields = const [],
  }) : texts = texts ?? List.filled(pages.length, ''),
       annotations = annotations ?? {};

  /// Every page's size.
  final List<PdfPageSize> pages;

  /// Every page's text.
  final List<String> texts;

  /// Links per page: a rectangle and its target.
  final Map<int, List<(PdfRect, PdfLink)>> links;

  /// The user password, or `null`.
  final String? password;

  /// The permission bits.
  final int permissions;

  /// -1 when not encrypted.
  final int securityRevision;

  /// The outline.
  final List<PdfOutlineEntry> outline;

  /// The form type.
  final PdfFormType formType;

  /// `(page, index)` of characters without a Unicode mapping.
  final Set<(int, int)> unmapped;

  /// The annotations of each page (the file's, then the editor's).
  final Map<int, List<PdfAnnotation>> annotations;

  /// The form fields (widgets; set [formType] to `acroForm`).
  final List<FakeFormField> fields;

  // The focused field, its value when it got the focus, the text being
  // typed into it (committed when it loses the focus) and its typing undo.
  FakeFormField? _focus;
  String _focusValue = '';
  String _typed = '';
  bool _allSelected = false;
  final _typing = <String>[];
}

/// A widget of a fake form field; [value] and [checked] change as it is
/// filled.
class FakeFormField {
  FakeFormField({
    required this.page,
    required this.name,
    required this.type,
    required this.rect,
    this.index = 0,
    this.value = '',
    this.checked = false,
    this.readOnly = false,
  });

  final int page;
  final String name;
  final int index;
  final PdfFieldType type;
  final PdfRect rect;
  String value;
  bool checked;
  final bool readOnly;

  PdfFormField get field => PdfFormField(
    page: page,
    name: name,
    index: index,
    type: type,
    rect: rect,
    value: value,
    checked: checked,
    readOnly: readOnly,
  );
}

/// The fake grid's left edge, in points.
const kFakeLeft = 36.0;

/// The fake grid's first line's top, in points.
const kFakeTop = 36.0;

/// A character's width.
const kFakeCharWidth = 6.0;

/// A character's height.
const kFakeCharHeight = 10.0;

/// The line pitch.
const kFakeLineHeight = 14.0;

/// The view-point rectangle of character [index] of [text].
PdfRect fakeCharRect(String text, int index) {
  var line = 0;
  var column = 0;
  for (var i = 0; i < index; i++) {
    if (text[i] == '\n') {
      line++;
      column = 0;
    } else {
      column++;
    }
  }
  final left = kFakeLeft + column * kFakeCharWidth;
  final top = kFakeTop + line * kFakeLineHeight;
  return PdfRect(left, top, left + kFakeCharWidth, top + kFakeCharHeight);
}

/// A fake [TomPdfEngine] serving fixed page images, text and links from
/// [FakePdfDocument]s by path, so the editor's tests run without PDFium.
/// Renders answer after a microtask (no timer, so a widget test's `pump`
/// delivers them); a render cancelled before then answers `null`, a cancel
/// after it ran changes nothing.
class FakePdfEngine implements TomPdfEngine {
  FakePdfEngine(this.documents, {this.files});

  /// The documents by path.
  final Map<String, FakePdfDocument> documents;

  /// Where [saveIncremental] writes (an in-memory store in widget tests).
  final MemoryBinaryFiles? files;

  final _open = <int, FakePdfDocument>{};
  var _next = 1;
  final _cancelled = <int>{};

  /// The tickets of the renders that have not run yet.
  final _queued = <int>{};

  /// The tickets every render was sent with, in order.
  final tickets = <int?>[];

  /// Renders still to be answered `null` as if the engine had dropped them
  /// without a cancel (a test of the view's recovery).
  int dropNextRenders = 0;

  /// Every call, in order (`open <path>`, `render <page> …`, `find …`).
  final calls = <String>[];

  /// The renders made (not cancelled), as `(page, scale, x, y, pxW, pxH)`.
  final renders = <(int, double, int, int, int, int)>[];

  /// How often [release] was called.
  int releases = 0;

  /// Passwords given to [open], to show a test what was asked (the editor
  /// must never log them).
  final passwordsSeen = <String?>[];

  FakePdfDocument _doc(int handle) =>
      _open[handle] ?? (throw StateError('document $handle is not open'));

  @override
  Future<PdfOpenResult> open(String path, {String? password}) async {
    calls.add('open $path');
    passwordsSeen.add(password);
    final d = documents[path];
    if (d == null) {
      return const PdfOpenResult.failed(PdfOpenError.file, 'file not found');
    }
    if (d.password != null && d.password != password) {
      return const PdfOpenResult.failed(
        PdfOpenError.password,
        'password required or incorrect',
      );
    }
    final handle = _next++;
    _open[handle] = d;
    return PdfOpenResult.opened(
      PdfDocumentInfo(
        handle: handle,
        pages: d.pages,
        permissions: d.permissions,
        securityRevision: d.securityRevision,
        outline: d.outline,
        formType: d.formType,
      ),
    );
  }

  /// The key a document opened from [bytes] is looked up under in
  /// [documents]: `bytes:` and the bytes as Latin-1.
  static String bytesKey(List<int> bytes) => 'bytes:${latin1.decode(bytes)}';

  var _savedBytes = 0;

  @override
  Future<PdfOpenResult> openBytes(Uint8List bytes, {String? password}) {
    calls.add('openBytes ${bytes.length}');
    return open(bytesKey(bytes), password: password);
  }

  /// Answers `%PDF-saved-<n>`, registered for the same document, so a
  /// reopen from the saved bytes finds it.
  @override
  Future<Uint8List> saveIncrementalBytes(int doc) async {
    calls.add('saveBytes');
    final bytes = Uint8List.fromList(
      utf8.encode('%PDF-saved-${++_savedBytes}'),
    );
    documents[bytesKey(bytes)] = _doc(doc);
    return bytes;
  }

  @override
  Future<Uint8List> saveCopyBytes(
    int doc, {
    bool removeSecurity = false,
  }) async {
    calls.add('saveCopyBytes ${removeSecurity ? 'unencrypted' : 'as is'}');
    _doc(doc);
    return Uint8List.fromList(
      utf8.encode(removeSecurity ? '%PDF-unencrypted' : '%PDF-copy'),
    );
  }

  @override
  Future<void> close(int doc) async {
    calls.add('close $doc');
    _open.remove(doc);
  }

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
    tickets.add(ticket);
    if (ticket != null) _queued.add(ticket);
    await Future<void>.value(); // a microtask: pump() flushes it
    if (ticket != null) _queued.remove(ticket);
    if (ticket != null && _cancelled.remove(ticket)) return null;
    if (dropNextRenders > 0) {
      dropNextRenders--;
      return null;
    }
    _doc(doc);
    renders.add((page, scale, x, y, pxW, pxH));
    final pixels = Uint8List(pxW * pxH * 4);
    // A light shade per page, opaque.
    final shade = 200 + (page * 7) % 50;
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = shade;
      pixels[i + 1] = shade;
      pixels[i + 2] = 255;
      pixels[i + 3] = 255;
    }
    return PdfRendered(pxW, pxH, pixels);
  }

  @override
  void cancel(int ticket) {
    // Like PDFium's worker: only a render that has not run is dropped; a
    // cancel that comes later is forgotten, never held for the ticket's
    // next use.
    if (_queued.contains(ticket)) _cancelled.add(ticket);
  }

  @override
  Future<int> charCount(int doc, int page) async =>
      _doc(doc).texts[page].length;

  @override
  Future<int> charIndexAt(int doc, int page, double x, double y) async {
    final text = _doc(doc).texts[page];
    for (var i = 0; i < text.length; i++) {
      final r = fakeCharRect(text, i);
      if (x >= r.left - 5 &&
          x <= r.right + 5 &&
          y >= r.top - 5 &&
          y <= r.bottom + 5) {
        // The nearest within the tolerance: prefer the box that contains it.
        if (r.contains(x, y)) return i;
      }
    }
    for (var i = 0; i < text.length; i++) {
      final r = fakeCharRect(text, i);
      if (x >= r.left - 5 &&
          x <= r.right + 5 &&
          y >= r.top - 5 &&
          y <= r.bottom + 5) {
        return i;
      }
    }
    return -1;
  }

  @override
  Future<List<PdfRect>> rangeRects(
    int doc,
    int page,
    int start,
    int count,
  ) async {
    final text = _doc(doc).texts[page];
    final rects = <PdfRect>[];
    PdfRect? current;
    for (var i = start; i < start + count && i < text.length; i++) {
      if (text[i] == '\n') continue;
      final r = fakeCharRect(text, i);
      if (current != null && current.top == r.top && current.right == r.left) {
        current = PdfRect(current.left, current.top, r.right, current.bottom);
      } else {
        if (current != null) rects.add(current);
        current = r;
      }
    }
    if (current != null) rects.add(current);
    return rects;
  }

  @override
  Future<PdfText> text(int doc, int page, int start, int count) async {
    final d = _doc(doc);
    final text = d.texts[page];
    final buffer = StringBuffer();
    var skipped = 0;
    for (var i = start; i < start + count && i < text.length; i++) {
      if (d.unmapped.contains((page, i))) {
        skipped++;
        continue;
      }
      buffer.write(text[i]);
    }
    return PdfText(buffer.toString(), skipped);
  }

  @override
  Stream<PdfSearchHit> find(
    int doc,
    String term, {
    bool matchCase = false,
    bool wholeWord = false,
    int fromPage = 0,
  }) async* {
    calls.add('find ${term.length} chars');
    final d = _doc(doc);
    final n = d.pages.length;
    for (var k = 0; k < n; k++) {
      final page = (fromPage + k) % n;
      await Future<void>.value(); // a microtask: pump() flushes it
      final text = matchCase ? d.texts[page] : d.texts[page].toLowerCase();
      final needle = matchCase ? term : term.toLowerCase();
      if (needle.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = text.indexOf(needle, from);
        if (at < 0) break;
        from = at + 1;
        if (wholeWord) {
          final word = RegExp(r'\w');
          if (at > 0 && word.hasMatch(text[at - 1])) continue;
          final end = at + needle.length;
          if (end < text.length && word.hasMatch(text[end])) continue;
        }
        yield PdfSearchHit(
          page,
          at,
          needle.length,
          await rangeRects(doc, page, at, needle.length),
        );
      }
    }
  }

  @override
  Future<PdfLink?> linkAt(int doc, int page, double x, double y) async {
    for (final (rect, link)
        in _doc(doc).links[page] ?? const <(PdfRect, PdfLink)>[]) {
      if (rect.contains(x, y)) return link;
    }
    return null;
  }

  @override
  Future<String?> saveIncremental(int doc, String target) async {
    calls.add('save $target');
    _doc(doc);
    files?.write(target, utf8.encode('%PDF-saved'));
    return null;
  }

  @override
  Future<List<PdfAnnotation>> annotations(int doc, int page) async => [
    for (final (i, a)
        in (_doc(doc).annotations[page] ?? const <PdfAnnotation>[]).indexed)
      a.id.isEmpty ? a.copyWith(id: '#$i') : a,
  ];

  int _index(List<PdfAnnotation> list, String match) {
    if (match.startsWith('#')) {
      final i = int.parse(match.substring(1));
      if (i < list.length && list[i].id.isEmpty) return i;
      throw StateError('no annotation $match');
    }
    final i = list.indexWhere((a) => a.id == match);
    if (i < 0) throw StateError('no annotation $match');
    return i;
  }

  @override
  Future<PdfAnnotation> addAnnotation(
    int doc,
    int page,
    PdfAnnotation annotation,
  ) async {
    calls.add('addAnnotation $page ${annotation.kind.name}');
    (_doc(doc).annotations[page] ??= []).add(annotation);
    return annotation;
  }

  @override
  Future<void> updateAnnotation(
    int doc,
    int page,
    String match,
    PdfAnnotation state,
  ) async {
    calls.add('updateAnnotation $page $match');
    final list = _doc(doc).annotations[page] ?? [];
    list[_index(list, match)] = state;
  }

  @override
  Future<void> removeAnnotation(int doc, int page, String match) async {
    calls.add('removeAnnotation $page $match');
    final list = _doc(doc).annotations[page] ?? [];
    list.removeAt(_index(list, match));
  }

  // ------------------------------------------------------------------ forms

  FakeFormField? _fieldAt(FakePdfDocument d, int page, double x, double y) {
    for (final f in d.fields) {
      if (f.page == page &&
          x >= f.rect.left &&
          x <= f.rect.right &&
          y >= f.rect.top &&
          y <= f.rect.bottom) {
        return f;
      }
    }
    return null;
  }

  /// Commits the focused field's typing and takes the focus away.
  List<PdfFormChange> _blur(FakePdfDocument d) {
    final f = d._focus;
    d._focus = null;
    if (f == null || f.type != PdfFieldType.text) return const [];
    f.value = d._typed;
    d._typing.clear();
    if (f.value == d._focusValue) return const [];
    return [PdfFormChange(f.page, f.name, f.type, d._focusValue, f.value)];
  }

  void _focusOn(FakePdfDocument d, FakeFormField f) {
    d._focus = f;
    d._focusValue = f.value;
    d._typed = f.value;
    d._allSelected = false;
    d._typing.clear();
  }

  PdfFormResult _result(
    FakePdfDocument d, {
    bool handled = true,
    Set<int> dirty = const {},
    List<PdfFormChange> changes = const [],
  }) {
    final f = d._focus;
    return PdfFormResult(
      handled: handled,
      dirtyPages: dirty,
      focused: f == null
          ? null
          : PdfFormField(
              page: f.page,
              name: f.name,
              index: f.index,
              type: f.type,
              rect: f.rect,
              value: f.type == PdfFieldType.text ? d._typed : f.value,
              checked: f.checked,
              readOnly: f.readOnly,
            ),
      changes: changes,
    );
  }

  @override
  Future<List<PdfFormField>> formFields(int doc, int page) async => [
    for (final f in _doc(doc).fields)
      if (f.page == page) f.field,
  ];

  @override
  Future<PdfFormField?> formFieldAt(
    int doc,
    int page,
    double x,
    double y,
  ) async => _fieldAt(_doc(doc), page, x, y)?.field;

  @override
  Future<PdfFormResult> formClick(int doc, int page, double x, double y) async {
    calls.add('formClick $page');
    final d = _doc(doc);
    final f = _fieldAt(d, page, x, y);
    if (f == null || !f.field.fillable) {
      final old = d._focus?.page;
      final changes = _blur(d);
      return _result(d, handled: false, dirty: {?old}, changes: changes);
    }
    final changes = <PdfFormChange>[];
    final dirty = <int>{page};
    if (!identical(d._focus, f)) {
      final old = d._focus?.page;
      if (old != null) dirty.add(old);
      changes.addAll(_blur(d));
      _focusOn(d, f);
    }
    if (f.type == PdfFieldType.checkbox) {
      f.checked = !f.checked;
      changes.add(
        PdfFormChange(
          page,
          f.name,
          f.type,
          f.checked ? 'off' : 'on',
          f.checked ? 'on' : 'off',
        ),
      );
    } else if (f.type == PdfFieldType.radio && !f.checked) {
      var before = '';
      for (final o in d.fields) {
        if (o.page == page && o.name == f.name && o.checked) {
          before = '${o.index}';
          o.checked = false;
        }
      }
      f.checked = true;
      changes.add(PdfFormChange(page, f.name, f.type, before, '${f.index}'));
    }
    return _result(d, dirty: dirty, changes: changes);
  }

  @override
  Future<PdfFormResult> formText(int doc, String text) async {
    final d = _doc(doc);
    final f = d._focus;
    if (f == null || f.type != PdfFieldType.text) {
      return _result(d, handled: false);
    }
    d._typing.add(d._typed);
    d._typed = d._allSelected ? text : d._typed + text;
    d._allSelected = false;
    return _result(d, dirty: {f.page});
  }

  @override
  Future<PdfFormResult> formKey(
    int doc,
    PdfFormKey key, {
    bool shift = false,
  }) async {
    final d = _doc(doc);
    final f = d._focus;
    if (f == null) return _result(d, handled: false);
    switch (key) {
      case PdfFormKey.backspace when f.type == PdfFieldType.text:
        d._typing.add(d._typed);
        d._typed = d._allSelected || d._typed.isEmpty
            ? ''
            : d._typed.substring(0, d._typed.length - 1);
        d._allSelected = false;
      case PdfFormKey.selectAll:
        d._allSelected = true;
      case PdfFormKey.tab:
        final fillable = [
          for (final o in d.fields)
            if (o.field.fillable) o,
        ];
        final at = fillable.indexOf(f);
        final next = fillable[(at + (shift ? -1 : 1)) % fillable.length];
        final changes = _blur(d);
        _focusOn(d, next);
        return _result(d, dirty: {f.page, next.page}, changes: changes);
      default:
        break;
    }
    return _result(d, dirty: {f.page});
  }

  @override
  Future<PdfFormResult> formUndo(int doc, {bool redo = false}) async {
    final d = _doc(doc);
    final f = d._focus;
    if (redo || f == null || d._typing.isEmpty) {
      return _result(d, handled: false);
    }
    d._typed = d._typing.removeLast();
    return _result(d, dirty: {f.page});
  }

  @override
  Future<PdfFormResult> formKillFocus(int doc) async {
    calls.add('formKillFocus');
    final d = _doc(doc);
    final old = d._focus?.page;
    final changes = _blur(d);
    return _result(d, dirty: {?old}, changes: changes);
  }

  @override
  Future<PdfFormResult> formSetValue(
    int doc,
    int page,
    String name,
    PdfFieldType type,
    String value,
  ) async {
    calls.add('formSetValue $page $name $value');
    final d = _doc(doc);
    _blur(d);
    for (final f in d.fields) {
      if (f.page != page || f.name != name) continue;
      switch (type) {
        case PdfFieldType.text:
          f.value = value;
        case PdfFieldType.checkbox:
          f.checked = value == 'on';
        case PdfFieldType.radio:
          if (value.isNotEmpty) f.checked = '${f.index}' == value;
        default:
          break;
      }
    }
    return _result(d, dirty: {page});
  }

  @override
  Future<String?> saveCopy(
    int doc,
    String target, {
    bool removeSecurity = false,
  }) async {
    calls.add('saveCopy ${removeSecurity ? 'unencrypted' : 'as is'}');
    _doc(doc);
    files?.write(
      target,
      utf8.encode(removeSecurity ? '%PDF-unencrypted' : '%PDF-copy'),
    );
    return null;
  }

  @override
  Future<void> release() async {
    releases++;
  }
}

/// [TomBinaryFiles] in memory, for widget tests: files are byte lists with a
/// modification counter.
class MemoryBinaryFiles implements TomBinaryFiles {
  final _files = <String, Uint8List>{};
  final _times = <String, int>{};
  var _clock = 0;

  /// Paths that are not writable.
  final readOnly = <String>{};

  /// Writes [bytes] at [path] (a test changing the file on disk).
  void write(String path, List<int> bytes) {
    _files[path] = Uint8List.fromList(bytes);
    _times[path] = ++_clock;
  }

  /// Deletes [path].
  void delete(String path) {
    _files.remove(path);
    _times.remove(path);
  }

  /// The bytes at [path].
  Uint8List? read(String path) => _files[path];

  /// Every path held.
  Iterable<String> get paths => _files.keys;

  @override
  Future<TomFileRevision?> revisionOf(String path) async {
    final bytes = _files[path];
    if (bytes == null) return null;
    return TomFileRevision(
      size: bytes.length,
      modified: DateTime.fromMillisecondsSinceEpoch(_times[path]! * 1000),
      sha256: base64.encode(bytes), // the bytes themselves stand in for it
    );
  }

  @override
  Future<bool> isWritable(String path) async =>
      _files.containsKey(path) && !readOnly.contains(path);

  @override
  Future<String> temporaryTarget(String path) async {
    final slash = path.lastIndexOf('/');
    final folder = path.substring(0, slash);
    final name = path.substring(slash + 1);
    for (var n = 1; ; n++) {
      final t = '$folder/.$name.tom-save-$n';
      if (!_files.containsKey(t)) {
        write(t, const []);
        return t;
      }
    }
  }

  @override
  Future<TomBinaryReplaceResult> replace(
    String original,
    String temporary,
    TomFileRevision? expectedRevision, {
    bool force = false,
  }) async {
    final current = await revisionOf(original);
    final unchanged =
        force ||
        (expectedRevision == null
            ? current == null
            : current != null && current.sameContent(expectedRevision));
    if (!unchanged) {
      return TomBinaryReplaceResult(
        TomBinaryReplaceOutcome.conflict,
        current,
        temporary,
      );
    }
    write(original, _files.remove(temporary) ?? const []);
    _times.remove(temporary);
    return TomBinaryReplaceResult(
      TomBinaryReplaceOutcome.replaced,
      await revisionOf(original),
      temporary,
    );
  }

  @override
  Future<TomBinaryReplaceResult> save(
    String path,
    List<int> bytes,
    TomFileRevision? expectedRevision,
  ) async {
    final t = await temporaryTarget(path);
    write(t, bytes);
    return replace(path, t, expectedRevision);
  }

  @override
  Future<String> keepAsCopy(String temporary, String original) async {
    final dot = original.lastIndexOf('.');
    final stem = dot > 0 ? original.substring(0, dot) : original;
    final ext = dot > 0 ? original.substring(dot) : '';
    for (var n = 1; ; n++) {
      final copy = '$stem${n == 1 ? ' (copy)' : ' (copy $n)'}$ext';
      if (!_files.containsKey(copy)) {
        write(copy, _files.remove(temporary) ?? const []);
        return copy;
      }
    }
  }

  @override
  Future<List<String>> removeTemporaryFiles(String path) async {
    final slash = path.lastIndexOf('/');
    final prefix =
        '${path.substring(0, slash)}/.${path.substring(slash + 1)}.tom-save-';
    final victims = _files.keys.where((p) => p.startsWith(prefix)).toList();
    for (final v in victims) {
      delete(v);
    }
    return victims;
  }
}
