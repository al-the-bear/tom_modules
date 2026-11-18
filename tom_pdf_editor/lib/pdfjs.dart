// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The pdf.js view: [TomPdfJsView] (pdf.js in the workspace's webview fork),
/// its [TomPdfJsController] and the bridge's [TomPdfJsChannel], in the three
/// modes of [TomPdfJsMode]. pdf.js is vendored (`third_party/pdfjs/`) and
/// served by `TomLocalContentServer`. Uses `dart:io` and the webview plugin.
library;

export 'src/pdfjs/channel.dart';
export 'src/pdfjs/controller.dart';
export 'src/pdfjs/view.dart';
