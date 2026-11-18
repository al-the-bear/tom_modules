// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Test support for the PDF editor: [FakePdfEngine] serves fixed page
/// images, text and links from [FakePdfDocument]s, [MemoryBinaryFiles] keeps
/// files in memory, and [FakePdfEditorHost] records what the editor asks of
/// its host — so the editor's tests run without PDFium.
library;

export 'src/testing/fake_engine.dart';
export 'src/testing/fake_host.dart';
