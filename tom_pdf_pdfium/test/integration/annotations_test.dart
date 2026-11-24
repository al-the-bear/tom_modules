// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Annotations on the real PDFium: created, read back, changed, removed,
/// saved incrementally, reopened; the saved file in macOS PDFKit (Preview's
/// engine). Tagged `pdfium`.
@Tags(['pdfium'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfium/tom_pdf_pdfium.dart';

import '../samples.dart';

/// The annotations PDFKit reads on page [page] (0-based) of [path], as
/// `type:contents`, or `null` when it refuses the file.
List<String>? pdfKitAnnotations(String path, int page) {
  final r = Process.runSync('swift', [
    '-e',
    'import PDFKit; '
        'guard let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else { print("refused"); exit(0) }; '
        'let p = d.page(at: Int(CommandLine.arguments[2])!)!; '
        'print(p.annotations.map { (\$0.type ?? "?") + ":" + (\$0.contents ?? "") }.joined(separator: "|"))',
    path,
    '$page',
  ]);
  final out = '${r.stdout}'.trim();
  if (out == 'refused') return null;
  return out.isEmpty ? [] : out.split('|');
}

int _rgb(int argb) => argb % 0x1000000;

void main() {
  final library = const TomPdfiumLocator().locate();
  final skip = library.isUsable ? samplesSkipReason : library.message;
  late PdfiumEngine engine;
  late Directory dir;

  setUpAll(() async {
    if (skip != null) return;
    engine = await PdfiumEngine.acquire(library.path!);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await engine.release();
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('pdf-annot-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('PDF-ANNOT-1: highlight, note and ink are created, read back, '
      'changed, saved incrementally and reopened; PDFKit reads them', () async {
    final source = '${dir.path}/pdf-text.pdf';
    File(samplePath('pdf-text.pdf')).copySync(source);
    final info = (await engine.open(source)).info!;
    final doc = info.handle;
    final before = await engine.annotations(doc, 0);

    // A highlight over the first characters' line rectangles.
    final quads = await engine.rangeRects(doc, 0, 0, 20);
    expect(quads, isNotEmpty);
    final union = PdfRect(
      quads.map((q) => q.left).reduce((a, b) => a < b ? a : b),
      quads.map((q) => q.top).reduce((a, b) => a < b ? a : b),
      quads.map((q) => q.right).reduce((a, b) => a > b ? a : b),
      quads.map((q) => q.bottom).reduce((a, b) => a > b ? a : b),
    );
    final now = pdfDate(DateTime(2026, 11, 18, 12));
    final highlight = await engine.addAnnotation(
      doc,
      0,
      PdfAnnotation(
        id: 'hl-1',
        kind: PdfAnnotationKind.highlight,
        rect: union,
        quads: quads,
        color: 0xFFFFEB3B,
        author: 'Tester',
        modified: now,
      ),
    );
    expect(highlight.kind, PdfAnnotationKind.highlight);
    expect(highlight.quads.length, quads.length);
    expect(highlight.quads.first.left, closeTo(quads.first.left, 0.1));
    expect(highlight.modified, now);
    await engine.addAnnotation(
      doc,
      0,
      const PdfAnnotation(
        id: 'note-1',
        kind: PdfAnnotationKind.note,
        rect: PdfRect(400, 100, 420, 120),
        color: 0xFFFFC107,
        contents: 'A note from the test',
        author: 'Tester',
      ),
    );
    await engine.addAnnotation(
      doc,
      0,
      PdfAnnotation(
        id: 'ink-1',
        kind: PdfAnnotationKind.ink,
        rect: const PdfRect(100, 300, 300, 340),
        color: 0xFFE53935,
        strokes: [
          [
            for (var i = 0; i <= 20; i++)
              (x: 100.0 + i * 10, y: 320.0 + (i.isEven ? -15 : 15)),
          ],
        ],
        author: 'Tester',
      ),
    );
    var after = await engine.annotations(doc, 0);
    expect(after.length, before.length + 3);
    final ink = after.firstWhere((a) => a.id == 'ink-1');
    expect(ink.strokes.single.length, 21);
    expect(ink.strokes.single.first.x, closeTo(100, 0.1));
    expect(ink.width, 2);
    final note = after.firstWhere((a) => a.id == 'note-1');
    expect(note.contents, 'A note from the test');
    expect(note.author, 'Tester');

    // Change: move the ink, recolour the note.
    await engine.updateAnnotation(doc, 0, 'ink-1', ink.moved(0, 40));
    await engine.updateAnnotation(
      doc,
      0,
      'note-1',
      note.copyWith(color: 0xFF43A047),
    );
    after = await engine.annotations(doc, 0);
    expect(
      after.firstWhere((a) => a.id == 'ink-1').strokes.single.first.y,
      closeTo(345, 0.1),
    );
    expect(_rgb(after.firstWhere((a) => a.id == 'note-1').color), 0x43A047);

    // A removed annotation is gone.
    await engine.addAnnotation(
      doc,
      0,
      const PdfAnnotation(
        id: 'gone',
        kind: PdfAnnotationKind.note,
        rect: PdfRect(10, 10, 30, 30),
      ),
    );
    await engine.removeAnnotation(doc, 0, 'gone');
    expect(
      (await engine.annotations(doc, 0)).any((a) => a.id == 'gone'),
      isFalse,
    );

    // The page as edited.
    final page = info.pages[0];
    final w = page.width.round();
    final h = page.height.round();
    final edited = (await engine.render(
      doc,
      0,
      scale: 1,
      x: 0,
      y: 0,
      pxW: w,
      pxH: h,
    ))!;

    // Save incrementally, reopen.
    final target = '${dir.path}/saved.pdf';
    expect(await engine.saveIncremental(doc, target), isNull);
    await engine.close(doc);
    final original = File(source).readAsBytesSync();
    final saved = File(target).readAsBytesSync();
    expect(saved.sublist(0, original.length), original, reason: 'not a prefix');
    final reopened = (await engine.open(target)).info!;
    final back = await engine.annotations(reopened.handle, 0);
    expect(back.map((a) => a.id), containsAll(['hl-1', 'note-1', 'ink-1']));
    expect(back.firstWhere((a) => a.id == 'hl-1').quads.length, quads.length);

    // The reopened page renders like the edited one, and differs from the
    // original page where the annotations are.
    final again = (await engine.render(
      reopened.handle,
      0,
      scale: 1,
      x: 0,
      y: 0,
      pxW: w,
      pxH: h,
    ))!;
    await engine.close(reopened.handle);
    final plain = (await engine.open(source)).info!;
    final untouched = (await engine.render(
      plain.handle,
      0,
      scale: 1,
      x: 0,
      y: 0,
      pxW: w,
      pxH: h,
    ))!;
    await engine.close(plain.handle);
    int diff(PdfRendered a, PdfRendered b) {
      var n = 0;
      for (var i = 0; i < a.bgra.length; i++) {
        if (a.bgra[i] != b.bgra[i]) n++;
      }
      return n;
    }

    expect(diff(edited, again), lessThan(edited.bgra.length ~/ 100));
    expect(
      diff(untouched, again),
      greaterThan(1000),
      reason: 'the annotations are not drawn',
    );

    if (Platform.isMacOS) {
      final kit = pdfKitAnnotations(target, 0);
      expect(kit, isNotNull, reason: 'PDFKit refuses the saved file');
      expect(
        kit!.map((s) => s.split(':').first),
        containsAll(['Highlight', 'Text', 'Ink']),
      );
      expect(kit, contains('Text:A note from the test'));
    }
  }, skip: skip);

  test('PDF-ANNOT-2: an annotation of the file without NM is addressed by '
      'index and gets an NM when edited', () async {
    final source = '${dir.path}/pdf-annot.pdf';
    File(samplePath('pdf-annot.pdf')).copySync(source);
    final doc = (await engine.open(source)).info!.handle;
    PdfAnnotation? unnamed;
    var page = 0;
    for (; page < 3 && unnamed == null; page++) {
      final list = await engine.annotations(doc, page);
      unnamed = list.where((a) => a.unnamed && a.editable).firstOrNull;
    }
    page--;
    expect(
      unnamed,
      isNotNull,
      reason: 'pdf-annot has an editable annotation without NM',
    );
    final size = (await engine.open(source)).info!;
    final w = size.pages[page].width.round();
    final h = size.pages[page].height.round();
    await engine.close(size.handle);
    Future<PdfRendered> render() async =>
        (await engine.render(doc, page, scale: 1, x: 0, y: 0, pxW: w, pxH: h))!;
    final before = await render();
    await engine.updateAnnotation(
      doc,
      page,
      unnamed!.id,
      unnamed.copyWith(id: 'named-now', color: 0xFF1E88E5),
    );
    final list = await engine.annotations(doc, page);
    expect(_rgb(list.where((a) => a.id == 'named-now').single.color), 0x1E88E5);
    // The page shows the change: the appearance is generated anew.
    final after = await render();
    var changed = 0;
    var blue = 0;
    for (var i = 0; i + 3 < after.bgra.length; i += 4) {
      if (after.bgra[i] != before.bgra[i] ||
          after.bgra[i + 2] != before.bgra[i + 2]) {
        changed++;
      }
      if (after.bgra[i] > 0xC0 &&
          after.bgra[i + 1] > 0x70 &&
          after.bgra[i + 1] < 0xA0 &&
          after.bgra[i + 2] < 0x40) {
        blue++;
      }
    }
    expect(changed, greaterThan(50), reason: 'the page does not show the edit');
    expect(blue, greaterThan(20), reason: 'the new colour is not drawn');
    await engine.close(doc);
  }, skip: skip);

  test('PDF-ANNOT-3: a copy of an encrypted file without its security opens '
      'without a password', () async {
    final info = (await engine.open(
      samplePath('pdf-encrypted.pdf'),
      password: kEncryptedPassword,
    )).info!;
    final target = '${dir.path}/unencrypted.pdf';
    expect(
      await engine.saveCopy(info.handle, target, removeSecurity: true),
      isNull,
    );
    await engine.close(info.handle);
    final r = await engine.open(target);
    expect(r.info, isNotNull, reason: '${r.error}');
    expect(r.info!.encrypted, isFalse);
    await engine.close(r.info!.handle);
  }, skip: skip);
}
