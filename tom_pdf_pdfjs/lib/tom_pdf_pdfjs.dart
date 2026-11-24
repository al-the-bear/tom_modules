// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The pdf.js view: [TomPdfJsView] (pdf.js in the workspace's webview fork),
/// its [TomPdfJsController] and the bridge's [TomPdfJsChannel], in the three
/// modes of [TomPdfJsMode]. pdf.js is vendored (`third_party/pdfjs/`) and
/// served by `TomLocalContentServer`; the host is `package:tom_pdf_editor`'s
/// `TomPdfViewHost`. Uses `dart:io` and the webview plugin.
library;

export 'src/channel.dart';
export 'src/controller.dart';
export 'src/view.dart';
