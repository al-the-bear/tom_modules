// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:tom_pdf_editor/tom_pdf_editor.dart' show pdfEditorTrail;

/// The PDFium engine's trail: the editor's flag (`kPdfEditorDebug`) and its
/// prefix `[PE]`.
void pdfiumTrail(String event) => pdfEditorTrail('PE', event);
