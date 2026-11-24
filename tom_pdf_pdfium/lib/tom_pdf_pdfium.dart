// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDFium engine of the PDF editor: [PdfiumEngine], the worker isolate
/// that makes every PDFium call over FFI, the cross-reference fix applied to
/// its saves ([fixXrefInFile], `xref_fix.dart`), and [TomPdfiumLocator],
/// which finds the library in the binaries layer and answers a
/// [TomPdfiumLibrary] (the editor's engine status). Uses `dart:ffi` and
/// `dart:io`; the editor it drives is `package:tom_pdf_editor`.
library;

export 'src/library.dart';
export 'src/locator.dart';
export 'src/pdfium_engine.dart';
export 'src/pdfium_worker.dart' show fixXrefInFile;
export 'src/xref_fix.dart';
