// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDF editor in a window, on the real PDFium library from the binaries
/// layer: `TOM_PDF_FILE=<a pdf> flutter run -d macos`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/io.dart';
import 'package:tom_pdf_editor/pdfium.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';

/// A desktop host: the binaries layer's PDFium, the real file access.
class DesktopPdfHost implements TomPdfEditorHost {
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
  TomPdfiumLibrary get pdfium => const TomPdfiumLocator().locate();

  @override
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library) =>
      PdfiumEngine.acquire(library.path!);

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

void main() {
  final path = Platform.environment['TOM_PDF_FILE'];
  runApp(PdfExampleApp(path: path));
}

/// The app: one editor over [path].
class PdfExampleApp extends StatefulWidget {
  const PdfExampleApp({super.key, this.path, this.controller});

  /// The PDF to open.
  final String? path;

  /// A controller from outside (the integration test).
  final TomPdfEditorController? controller;

  @override
  State<PdfExampleApp> createState() => _PdfExampleAppState();
}

class _PdfExampleAppState extends State<PdfExampleApp> {
  TomPdfEditorController? _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        (widget.path == null
            ? null
            : (TomPdfEditorController(DesktopPdfHost(widget.path!))..open()));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: _controller == null
          ? const Center(child: Text('Set TOM_PDF_FILE to a PDF.'))
          : TomPdfEditor(controller: _controller!),
    ),
  );
}
