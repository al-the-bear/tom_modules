// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The `dart:io` part of the PDF editor: [TomPdfiumLocator], which finds the
/// PDFium library in the binaries layer and checks its release. The file
/// access the host gives the editor is `TomBinaryFileAccess` from
/// `package:tom_file_session/io.dart`.
library;

export 'src/io/locator.dart';
