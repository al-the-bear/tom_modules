// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDF editor without an engine: [TomPdfEditor] (the widget),
/// [TomPdfEditorController], the hosts ([TomPdfViewHost],
/// [TomPdfEditorHost]) and the engine's status ([TomPdfEngineStatus]), the
/// view's cache and layout, the notice bar and toolbar row every PDF view
/// shares, the debug trail, and the engine's interface ([TomPdfEngine]) with
/// its value types. No `dart:io`, no `dart:ffi`, no webview: an engine
/// package supplies the engine or a view of its own.
library;

export 'src/controller.dart';
export 'src/editor.dart';
export 'src/engine/engine.dart';
export 'src/host.dart';
export 'src/pdf_editor_trail.dart'
    show kPdfEditorDebug, pdfErrorSummary, pdfEditorTrail, pdfEditorReport;
export 'src/view/bars.dart' show PdfNoticeBar, PdfToolbarRow;
export 'src/view/layout.dart';
export 'src/view/pdf_view.dart'
    show PdfPageView, PdfPageViewState, PdfImageDecoder, decodeBgra;
export 'src/view/render_cache.dart';
