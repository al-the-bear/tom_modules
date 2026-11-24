/// The vendored pdf.js release is complete in the package: its `build/`
/// folder (the library and its worker, which the viewer loads) is easy to
/// lose to a `build/` ignore rule, and without it every open times out.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_pdfjs/tom_pdf_pdfjs.dart' show kPdfJsVersion;

void main() {
  test('PDFJS-VENDOR-1: the pdf.js build/ and web/ files the viewer loads '
      'are in the package', () {
    final root = 'third_party/pdfjs/$kPdfJsVersion';
    for (final file in const [
      'build/pdf.mjs',
      'build/pdf.worker.mjs',
      'build/pdf.sandbox.mjs',
      'build/pdf.renderer.mjs',
      'web/viewer.html',
      'web/viewer.mjs',
      'pdfjs.version.json',
      'LICENSE',
    ]) {
      expect(File('$root/$file').existsSync(), isTrue, reason: '$root/$file');
    }
  });
}
