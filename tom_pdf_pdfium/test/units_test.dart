// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart' show TomPdfEngineStatus;
import 'package:tom_pdf_pdfium/tom_pdf_pdfium.dart';

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
        platform: 'darwin-arm64',
        environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
      ).locate();
      expect(found.isUsable, isTrue);
      expect(found.path, '${root.path}/pdfium/darwin-arm64/libpdfium.dylib');
    });

    test('PDF-LOCATE-2: not found; another release is a mismatch', () {
      final none = TomPdfiumLocator(
        binariesRoot: root.path,
        platform: 'darwin-arm64',
      ).locate();
      expect(none.problem, TomPdfiumProblem.notFound);
      expect(none.message, startsWith('PDFium not found'));
      lib('chromium/7000');
      final other = TomPdfiumLocator(
        binariesRoot: root.path,
        platform: 'darwin-arm64',
      ).locate();
      expect(other.problem, TomPdfiumProblem.versionMismatch);
      expect(other.message, contains('chromium/7000'));
      expect(
        const TomPdfiumLocator(environment: {}).locate().problem,
        TomPdfiumProblem.notFound,
      );
    });

    void bundleLib(
      String folder,
      String tag, {
      bool versionInResources = false,
    }) {
      final dir = Directory('${root.path}/$folder')
        ..createSync(recursive: true);
      File('${dir.path}/libpdfium.dylib').writeAsStringSync('');
      final versionDir = versionInResources
          ? (Directory('${dir.parent.path}/Resources')..createSync())
          : dir;
      File(
        '${versionDir.path}/pdfium.version.json',
      ).writeAsStringSync(jsonEncode({'tag': tag}));
    }

    test('PDF-LOCATE-3: the bundle\'s library wins over the binaries layer, '
        'its version file in Contents/Resources', () {
      lib('chromium/7000');
      bundleLib(
        'Forge.app/Contents/Frameworks',
        kPdfiumBindingsTag,
        versionInResources: true,
      );
      final found = TomPdfiumLocator(
        platform: 'darwin-arm64',
        bundleFolders: [
          '${root.path}/Forge.app/Contents/Frameworks',
          '${root.path}/Forge.app/Contents/MacOS',
        ],
        environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
      ).locate();
      expect(found.isUsable, isTrue);
      expect(
        found.path,
        '${root.path}/Forge.app/Contents/Frameworks/libpdfium.dylib',
      );
    });

    test('PDF-LOCATE-4: nothing in the bundle — the binaries layer', () {
      lib(kPdfiumBindingsTag);
      Directory('${root.path}/bundle').createSync();
      final found = TomPdfiumLocator(
        platform: 'darwin-arm64',
        bundleFolders: ['${root.path}/bundle'],
        environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
      ).locate();
      expect(found.isUsable, isTrue);
      expect(found.path, '${root.path}/pdfium/darwin-arm64/libpdfium.dylib');
    });

    test('PDF-LOCATE-5: neither — not found', () {
      final none = TomPdfiumLocator(
        platform: 'darwin-arm64',
        bundleFolders: ['${root.path}/bundle'],
        environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
      ).locate();
      expect(none.problem, TomPdfiumProblem.notFound);
      expect(none.path, '${root.path}/pdfium/darwin-arm64/libpdfium.dylib');
    });

    test('PDF-LOCATE-6: a library beside a Linux or Windows executable, and '
        'in a Linux bundle\'s lib/', () {
      for (final (platform, name, folder) in [
        ('linux-x64', 'libpdfium.so', 'bundle/lib'),
        ('win32-x64', 'pdfium.dll', 'app'),
      ]) {
        final dir = Directory('${root.path}/$folder')
          ..createSync(recursive: true);
        File('${dir.path}/$name').writeAsStringSync('');
        File(
          '${dir.path}/pdfium.version.json',
        ).writeAsStringSync(jsonEncode({'tag': kPdfiumBindingsTag}));
        final found = TomPdfiumLocator(
          platform: platform,
          bundleFolders: [
            '${root.path}/${folder.split('/').first}',
            '${root.path}/$folder',
          ],
          environment: const {},
        ).locate();
        expect(found.isUsable, isTrue, reason: platform);
        expect(found.path, '${dir.path}/$name');
      }
    });

    test('PDF-LOCATE-7: under flutter test there is no bundle, so the default '
        'lookup reaches the binaries layer', () {
      lib(kPdfiumBindingsTag);
      expect(
        TomPdfiumLocator(
          platform: 'darwin-arm64',
          environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
        ).expectedPath,
        '${root.path}/pdfium/darwin-arm64/libpdfium.dylib',
      );
    });
  });

  group('PDF-STATUS the library as the editor\'s engine status', () {
    test('PDF-STATUS-1: a found library is usable, a problem is not, with '
        'the tab\'s message', () {
      const TomPdfEngineStatus found = TomPdfiumLibrary.found(
        '/b/libpdfium.dylib',
        kPdfiumBindingsTag,
      );
      expect(found.isUsable, isTrue);
      expect(found.message, 'PDFium $kPdfiumBindingsTag at /b/libpdfium.dylib');
      const TomPdfEngineStatus other = TomPdfiumLibrary.problem(
        TomPdfiumProblem.versionMismatch,
        '/b/libpdfium.dylib',
        tag: 'chromium/7000',
      );
      expect(other.isUsable, isFalse);
      expect(other.message, startsWith('PDFium version mismatch'));
    });
  });
}
