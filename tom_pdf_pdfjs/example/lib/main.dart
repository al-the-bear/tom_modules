// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The pdf.js view in a window:
/// `TOM_PDF_FILE=<a pdf> TOM_PDF_VIEW=components|integrated|full
/// flutter run -d macos`. The PDFium editor has its own example
/// (`tom_pdf_pdfium/example`).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfjs/tom_pdf_pdfjs.dart';

/// A desktop host: the real file access.
class DesktopPdfHost implements TomPdfViewHost {
  DesktopPdfHost(this.filePath, {this.onLink});

  @override
  final String filePath;

  /// Called for every external link.
  final void Function(String url)? onLink;

  @override
  String get name => filePath.split('/').last;

  @override
  String get authorName => Platform.environment['USER'] ?? 'user';

  @override
  TomBinaryFiles get files => const TomBinaryFileAccess();

  @override
  void notice(BuildContext context, String message, {required String kind}) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void openLink(String url) => onLink?.call(url);

  @override
  void historyChanged() {}
}

/// `TOM_PDF_FILE`: the PDF to open; `TOM_PDF_VIEW`: the mode, `components`
/// (the default), `integrated` or `full`.
void main() {
  final path = Platform.environment['TOM_PDF_FILE'];
  final view = Platform.environment['TOM_PDF_VIEW'] ?? 'components';
  if (path == null) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Set TOM_PDF_FILE to a PDF.'))),
      ),
    );
    return;
  }
  final mode = TomPdfJsMode.values.firstWhere(
    (m) => view == m.name,
    orElse: () => TomPdfJsMode.components,
  );
  runApp(
    PdfJsExampleApp(
      controller: TomPdfJsController(DesktopPdfHost(path), mode: mode),
    ),
  );
}

/// The app with the pdf.js view over [controller]'s file.
class PdfJsExampleApp extends StatelessWidget {
  const PdfJsExampleApp({super.key, required this.controller});

  /// The pdf.js view's controller.
  final TomPdfJsController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: TomPdfJsView(controller: controller)),
  );
}
