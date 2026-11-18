// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/widgets.dart';
import 'package:tom_file_session/tom_file_session.dart';

import 'engine/engine.dart';
import 'engine/library.dart';

/// What the PDF editor asks of the application. It has the shape of
/// `TomOfficeEditorHost`, so the Forge integration treats both alike.
abstract interface class TomPdfEditorHost {
  /// The file's name, for notices and history labels.
  String get name;

  /// Its absolute path.
  String get filePath;

  /// `T` (the author) of the annotations the editor creates.
  String get authorName;

  /// Revision, temporary target and replace (`TomBinaryFileAccess` over
  /// `dart:io` in a desktop host).
  TomBinaryFiles get files;

  /// Where libpdfium is, or why it cannot be used (`TomPdfiumLocator` in
  /// `io.dart` answers it).
  TomPdfiumLibrary get pdfium;

  /// The engine on [library]: in a desktop host `PdfiumEngine.acquire`
  /// (`pdfium.dart`), one engine shared by every PDF tab. The editor gives
  /// its share up with [TomPdfEngine.release] when it closes.
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library);

  /// Shows [message]; [kind] is `info`, `warning` or `error`.
  void notice(BuildContext context, String message, {required String kind});

  /// Opens an external link.
  void openLink(String url);

  /// Undo / redo / dirty state changed: the shell refreshes its commands.
  void historyChanged();
}
