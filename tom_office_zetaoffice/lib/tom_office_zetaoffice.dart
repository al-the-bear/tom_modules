// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// ZetaOffice in the webview (`part-office-webview`): [TomZetaOfficeView]
/// and its [TomZetaOfficeController], on the office editor's host
/// (`TomOfficeEditorHost` from `tom_office_editor`); [TomZetaOfficeCache],
/// the files downloaded once from `cdn.zetaoffice.net` and kept on the
/// machine; [TomZetaOfficeServer], the local server that hands the page, the
/// files and the document to the webview. Desktop only (`dart:io`, the
/// webview plugin).
library;

export 'src/cache.dart' show TomZetaOfficeCache;
export 'src/controller.dart';
export 'src/files.dart';
export 'src/serving.dart';
export 'src/trail.dart' show kZetaOfficeDebug;
export 'src/view.dart';
