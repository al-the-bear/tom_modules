// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// ZetaOffice in the webview (`part-office-webview`): [TomZetaOfficeView]
/// and its [TomZetaOfficeController], on the same host as the native office
/// editor; [TomZetaOfficeCache], the files downloaded once from
/// `cdn.zetaoffice.net` and kept on the machine; [TomZetaOfficeServer], the
/// local server that hands the page, the files and the document to the
/// webview. Desktop only (`dart:io`, the webview plugin).
library;

export 'src/zetaoffice/cache.dart' show TomZetaOfficeCache;
export 'src/zetaoffice/controller.dart';
export 'src/zetaoffice/files.dart';
export 'src/zetaoffice/serving.dart';
export 'src/zetaoffice/trail.dart' show kZetaOfficeDebug;
export 'src/zetaoffice/view.dart';
