// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:tom_pdf_editor/tom_pdf_editor.dart'
    show pdfEditorReport, pdfEditorTrail;

/// The pdf.js view's trail: the editor's flag (`kPdfEditorDebug`), the
/// prefix `[PE:js]`.
void pdfJsTrail(String event) => pdfEditorTrail('PE:js', event);

/// Reports [error] through `FlutterError.reportError` as this package's,
/// whether the trail is on or off, and logs it to the trail.
void pdfReport(Object error, StackTrace stack, String context) =>
    pdfEditorReport(error, stack, context, library: 'tom_pdf_pdfjs');
