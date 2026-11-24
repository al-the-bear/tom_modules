// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDFium engine against the real library from the binaries layer, over
/// the tom_forge sample set. Tagged `pdfium`; skipped where the library or
/// the samples are missing.
@Tags(['pdfium'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfium/tom_pdf_pdfium.dart';

import '../samples.dart';

/// Whether macOS's PDFKit (Preview's engine) opens [path].
bool pdfKitOpens(String path) {
  final r = Process.runSync('swift', [
    '-e',
    'import PDFKit; let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])); print(d == nil ? "refused" : "opened")',
    path,
  ]);
  return '${r.stdout}'.contains('opened');
}

void main() {
  final library = const TomPdfiumLocator().locate();
  final skip = !library.isUsable ? library.message : samplesSkipReason;
  late PdfiumEngine engine;

  setUpAll(() async {
    if (skip != null) return;
    engine = await PdfiumEngine.acquire(library.path!);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await engine.release();
  });

  Future<PdfDocumentInfo> open(String name, {String? password}) async {
    final r = await engine.open(samplePath(name), password: password);
    expect(r.info, isNotNull, reason: '${r.error}: ${r.message}');
    return r.info!;
  }

  double ink(PdfRendered r) {
    var dark = 0;
    for (var i = 0; i + 3 < r.bgra.length; i += 4) {
      if (r.bgra[i] < 200 || r.bgra[i + 1] < 200 || r.bgra[i + 2] < 200) dark++;
    }
    return dark / (r.bgra.length / 4);
  }

  test('PDFIUM-LIB-1: the locator finds chromium/8152', () {
    expect(library.tag, kPdfiumBindingsTag);
  }, skip: library.isUsable ? false : library.message);

  test(
    'PDFIUM-OPEN-1: pdf-text opens, renders, has text, searches, copies',
    () async {
      final info = await open('pdf-text.pdf');
      expect(info.pageCount, 43);
      expect(info.encrypted, isFalse);
      final page = info.pages.first;
      final r = (await engine.render(
        info.handle,
        0,
        scale: 1,
        x: 0,
        y: 0,
        pxW: page.width.round(),
        pxH: page.height.round(),
      ))!;
      expect(ink(r), greaterThan(0.01));
      final chars = await engine.charCount(info.handle, 0);
      expect(chars, greaterThan(100));
      final text = await engine.text(info.handle, 0, 0, 60);
      expect(text.text, contains('Chain-of-Thought'));
      final hits = await engine
          .find(info.handle, 'chain-of-thought', fromPage: 0)
          .toList();
      expect(hits.length, greaterThan(10));
      expect(hits.first.rects, isNotEmpty);
      expect(hits.first.rects.first.left, inInclusiveRange(0, page.width));
      // The first hit's characters, found again by position.
      final hit = hits.first;
      final rect = hit.rects.first;
      final at = await engine.charIndexAt(
        info.handle,
        hit.page,
        (rect.left + rect.right) / 2,
        (rect.top + rect.bottom) / 2,
      );
      expect(at, inInclusiveRange(hit.start, hit.start + hit.count));
      await engine.close(info.handle);
    },
    skip: skip,
  );

  test('PDFIUM-OPEN-2: pdf-scan has no text layer', () async {
    final info = await open('pdf-scan.pdf');
    expect(await engine.charCount(info.handle, 0), 0);
    await engine.close(info.handle);
  }, skip: skip);

  test('PDFIUM-OPEN-3: pdf-long opens fast with every page size; a far page '
      'renders; its outline reads', () async {
    final watch = Stopwatch()..start();
    final info = await open('pdf-long.pdf');
    expect(info.pageCount, 4211);
    expect(watch.elapsedMilliseconds, lessThan(5000));
    final r = await engine.render(
      info.handle,
      3999,
      scale: 0.5,
      x: 0,
      y: 0,
      pxW: 200,
      pxH: 200,
    );
    expect(r, isNotNull);
    await engine.close(info.handle);
  }, skip: skip);

  test(
    'PDFIUM-OPEN-4: pdf-encrypted asks for its password, then opens',
    () async {
      final r = await engine.open(samplePath('pdf-encrypted.pdf'));
      expect(r.error, PdfOpenError.password);
      final wrong = await engine.open(
        samplePath('pdf-encrypted.pdf'),
        password: 'nope',
      );
      expect(wrong.error, PdfOpenError.password);
      final info = await open(
        'pdf-encrypted.pdf',
        password: kEncryptedPassword,
      );
      expect(info.encrypted, isTrue);
      await engine.close(info.handle);
    },
    skip: skip,
  );

  test('PDFIUM-RENDER-1: a cancelled render is dropped', () async {
    final info = await open('pdf-long.pdf');
    final futures = [
      for (var i = 0; i < 20; i++)
        engine.render(
          info.handle,
          i,
          scale: 1,
          x: 0,
          y: 0,
          pxW: 300,
          pxH: 300,
          priority: PdfRenderPriority.prefetch,
          ticket: 1000 + i,
        ),
    ];
    for (var i = 5; i < 20; i++) {
      engine.cancel(1000 + i);
    }
    final results = await Future.wait(futures);
    expect(results.where((r) => r == null).length, greaterThan(0));
    await engine.close(info.handle);
  }, skip: skip);

  test('PDFIUM-SAVE-1: an incremental save of pdf-form and pdf-encrypted '
      'carries /Type/XRef and keeps the original bytes', () async {
    final dir = Directory.systemTemp.createTempSync('pdfium-save-');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final (name, password) in [
      ('pdf-form.pdf', null),
      ('pdf-encrypted.pdf', kEncryptedPassword),
    ]) {
      final info = await open(name, password: password);
      final target = '${dir.path}/$name';
      expect(await engine.saveIncremental(info.handle, target), isNull);
      await engine.close(info.handle);
      final original = File(samplePath(name)).readAsBytesSync();
      final saved = File(target).readAsBytesSync();
      expect(saved.sublist(0, original.length), original, reason: name);
      final tail = String.fromCharCodes(saved.sublist(original.length));
      // Both samples use cross-reference streams, so PDFium appends one,
      // and the fix gives it its /Type.
      expect(tail, contains('/W'), reason: '$name: no cross-reference stream');
      expect(tail, contains('/Type/XRef'), reason: name);
      if (Platform.isMacOS) {
        expect(pdfKitOpens(target), isTrue, reason: '$name: PDFKit refuses it');
        // The control: without the inserted key PDFKit refuses the file.
        final at = saved.length - tail.length + tail.indexOf(kXrefTypeEntry);
        final unfixed = '${dir.path}/unfixed-$name';
        File(unfixed).writeAsBytesSync([
          ...saved.sublist(0, at),
          ...saved.sublist(at + kXrefTypeEntry.length),
        ]);
        expect(pdfKitOpens(unfixed), isFalse, reason: '$name: control');
      }
      final reopened = await engine.open(target, password: password);
      expect(reopened.info, isNotNull, reason: name);
      await engine.close(reopened.info!.handle);
    }
  }, skip: skip);
}
