// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The PDFium engine: [PdfiumEngine], the worker isolate that makes every
/// PDFium call over FFI, and the cross-reference fix applied to its saves
/// ([fixXrefInFile]). Uses `dart:ffi` and `dart:io`.
library;

export 'src/pdfium/pdfium_engine.dart';
export 'src/pdfium/pdfium_worker.dart' show fixXrefInFile;
