// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';

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
/// delivers them); a render cancelled before then answers `null`.
class FakePdfEngine implements TomPdfEngine {
  FakePdfEngine(this.documents, {this.files});

  /// The documents by path.
  final Map<String, FakePdfDocument> documents;

  /// Where [saveIncremental] writes (an in-memory store in widget tests).
  final MemoryBinaryFiles? files;

  final _open = <int, FakePdfDocument>{};
  var _next = 1;
  final _cancelled = <int>{};

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
    await Future<void>.value(); // a microtask: pump() flushes it
    if (ticket != null && _cancelled.remove(ticket)) return null;
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
  void cancel(int ticket) => _cancelled.add(ticket);

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
