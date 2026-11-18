// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDF editor: [TomPdfEditor] (the widget), [TomPdfEditorController],
/// [TomPdfEditorHost], the view's cache and layout, and the engine's
/// interface ([TomPdfEngine]) with its value types. No `dart:io`, no
/// `dart:ffi`: the PDFium engine is in `pdfium.dart`, the locator in
/// `io.dart`.
library;

export 'src/controller.dart';
export 'src/editor.dart';
export 'src/engine/engine.dart';
export 'src/engine/library.dart';
export 'src/engine/xref_fix.dart';
export 'src/host.dart';
export 'src/pdf_editor_trail.dart' show kPdfEditorDebug, pdfErrorSummary;
export 'src/view/layout.dart';
export 'src/view/pdf_view.dart'
    show PdfPageView, PdfPageViewState, PdfImageDecoder, decodeBgra;
export 'src/view/render_cache.dart';
