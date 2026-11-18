// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_editor/io.dart';
import 'package:tom_pdf_editor/pdfium.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';

Uint8List _b(String s) => Uint8List.fromList(latin1.encode(s));

void main() {
  group('PDF-XREF the cross-reference fix', () {
    const stream =
        '12 0 obj\n<</W[1 3 1]/Size 13/Root 1 0 R/Index[11 2]/Length 10/Filter/FlateDecode>>stream\n'
        '0123456789\nendstream\nendobj\n';

    test('PDF-XREF-1: startxref names the offset', () {
      expect(startxrefOffset(_b('...\nstartxref\n12345\n%%EOF\n')), 12345);
      expect(startxrefOffset(_b('no marker')), isNull);
      expect(
        startxrefOffset(_b('startxref\n1\n%%EOF\nstartxref\n99\n%%EOF')),
        99,
      );
    });

    test(
      'PDF-XREF-2: /Type/XRef goes right after the stream dictionary\'s <<',
      () {
        final fixed = latin1.decode(fixXrefObject(_b(stream))!);
        expect(fixed, startsWith('12 0 obj\n<</Type/XRef /W[1 3 1]'));
        expect(fixed.length, stream.length + kXrefTypeEntry.length);
        // The stream data is untouched.
        expect(fixed, contains('stream\n0123456789\nendstream'));
      },
    );

    test('PDF-XREF-3: nothing to do for an xref table, a stream with its '
        '/Type, or another stream', () {
      expect(
        fixXrefObject(_b('xref\n0 1\n0000000000 65535 f \ntrailer<<>>')),
        isNull,
      );
      expect(
        fixXrefObject(_b(stream.replaceFirst('<<', '<</Type/XRef'))),
        isNull,
      );
      expect(
        fixXrefObject(_b(stream.replaceFirst('<<', '<</Type /XRef'))),
        isNull,
      );
      expect(
        fixXrefObject(_b('3 0 obj\n<</Length 4>>stream\nabcd\nendstream')),
        isNull,
        reason: 'no /W: not a cross-reference stream',
      );
    });

    test(
      'PDF-XREF-4: fixXrefInFile rewrites only the tail, offsets intact',
      () {
        final dir = Directory.systemTemp.createTempSync('xref-');
        addTearDown(() => dir.deleteSync(recursive: true));
        const head = '%PDF-1.7\n1 0 obj\n<<>>\nendobj\n';
        final file = File('${dir.path}/a.pdf')
          ..writeAsStringSync(
            '$head${stream}startxref\n${head.length}\n%%EOF\n',
          );
        expect(fixXrefInFile(file.path), isTrue);
        final text = file.readAsStringSync();
        expect(text, startsWith(head));
        expect(
          text.substring(head.length),
          startsWith('12 0 obj\n<</Type/XRef '),
        );
        expect(text, endsWith('startxref\n${head.length}\n%%EOF\n'));
        expect(fixXrefInFile(file.path), isFalse, reason: 'already fixed');
      },
    );
  });

  group('PDF-TILES the tile plan and the cache', () {
    test('PDF-TILES-1: up to 2048 px a page is one bitmap', () {
      final tiles = planTiles(0, 595, 842, 2);
      expect(tiles.single.key.whole, isTrue);
      expect((tiles.single.pxW, tiles.single.pxH), (1190, 1684));
    });

    test('PDF-TILES-2: above it, 512-px tiles; only the visible ones', () {
      final all = planTiles(0, 595, 842, 5); // 2975 × 4210
      expect(all.length, 6 * 9);
      expect(all.last.pxW, 2975 - 5 * 512);
      final some = planTiles(
        0,
        595,
        842,
        5,
        visible: (left: 600, top: 600, right: 1100, bottom: 1100),
      );
      expect(some.map((t) => (t.key.column, t.key.row)).toList(), [
        (1, 1),
        (2, 1),
        (1, 2),
        (2, 2),
      ]);
    });

    testWidgets('PDF-TILES-3: the cache evicts the least recently used over '
        'its bound, never a kept tile', (tester) async {
      final images = await tester.runAsync(
        () async => [
          for (var i = 0; i < 4; i++)
            await createTestImage(width: 64, height: 64),
        ],
      );
      final cache = PdfRenderCache(maxBytes: 3 * 64 * 64 * 4);
      PdfTileKey k(int i) => PdfTileKey(i, 1000, 0, 0, whole: true);
      for (var i = 0; i < 3; i++) {
        cache.put(k(i), images![i], 0, 0);
      }
      cache.get(k(0)); // 0 is now the newest
      cache.put(k(3), images![3], 0, 0, keep: {k(1)});
      expect(cache.contains(k(0)), isTrue);
      expect(cache.contains(k(1)), isTrue, reason: 'kept');
      expect(cache.contains(k(2)), isFalse);
      expect(cache.bytes, lessThanOrEqualTo(3 * 64 * 64 * 4));
    });
  });

  group('PDF-LAYOUT the page column', () {
    const pages = [
      PdfPageSize(612, 792),
      PdfPageSize(792, 612),
      PdfPageSize(612, 792),
    ];

    test(
      'PDF-LAYOUT-1: pages stack with gaps; hit maps back to view points',
      () {
        final l = PdfLayout(pages, 100);
        expect(l.pageTop(0), kPdfPageGap);
        expect(l.pageTop(1), kPdfPageGap * 2 + 792 * kPdfPixelsPerPoint);
        final r = l.pageRect(1, 2000);
        final hit = l.hit(r.topLeft + const Offset(10, 20), 2000)!;
        expect(hit.$1, 1);
        expect(hit.$2.dx, closeTo(10 / kPdfPixelsPerPoint, 1e-9));
        expect(l.pagesIn(l.pageTop(1) + 5, l.pageTop(1) + 10), [1]);
        expect(l.hit(const Offset(1, 1), 2000), isNull, reason: 'the margin');
      },
    );

    test('PDF-LAYOUT-2: zoom steps and fits', () {
      expect(zoomStepUp(100), 125);
      expect(zoomStepUp(400), 400);
      expect(zoomStepDown(50), 50);
      expect(zoomStepDown(110), 100);
      expect(
        fitWidthZoom(pages, 792 * kPdfPixelsPerPoint + 2 * kPdfPageGap),
        closeTo(100, 1e-6),
      );
      expect(
        fitPageZoom(
          pages[0],
          const Size(10000, 792 * kPdfPixelsPerPoint + 2 * kPdfPageGap),
        ),
        closeTo(100, 1e-6),
      );
    });
  });

  group('PDF-LOCATE the locator', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('pdfium-locate-'));
    tearDown(() => root.deleteSync(recursive: true));

    void lib(String tag) {
      final dir = Directory('${root.path}/pdfium/darwin-arm64')
        ..createSync(recursive: true);
      File('${dir.path}/libpdfium.dylib').writeAsStringSync('');
      File(
        '${dir.path}/pdfium.version.json',
      ).writeAsStringSync(jsonEncode({'tag': tag}));
    }

    test('PDF-LOCATE-1: found, from TOM_BINARY_PATH\'s parent', () {
      lib(kPdfiumBindingsTag);
      final found = TomPdfiumLocator(
        environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
      ).locate();
      expect(found.isUsable, isTrue);
      expect(found.path, '${root.path}/pdfium/darwin-arm64/libpdfium.dylib');
    });

    test('PDF-LOCATE-2: not found; another release is a mismatch', () {
      final none = TomPdfiumLocator(binariesRoot: root.path).locate();
      expect(none.problem, TomPdfiumProblem.notFound);
      expect(none.message, startsWith('PDFium not found'));
      lib('chromium/7000');
      final other = TomPdfiumLocator(binariesRoot: root.path).locate();
      expect(other.problem, TomPdfiumProblem.versionMismatch);
      expect(other.message, contains('chromium/7000'));
      expect(
        const TomPdfiumLocator(environment: {}).locate().problem,
        TomPdfiumProblem.notFound,
      );
    });
  });
}
