// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/widgets.dart';
import 'package:tom_file_session/tom_file_session.dart';

import 'helper/helper_channel.dart';

/// What the office editor asks of the application, in the style of
/// `TomFileEditorHost`: the editor reaches the application only through it.
abstract interface class TomOfficeEditorHost {
  /// The file's name, for notices and history labels.
  String get name;

  /// Its absolute path.
  String get filePath;

  /// Revision, temporary target and replace (`TomBinaryFileAccess` over
  /// `dart:io` in a desktop host).
  TomBinaryFiles get files;

  /// The detection result and the helper's start.
  TomOfficeHelperLauncher get helper;

  /// Shows [message]; [kind] is `info`, `warning` or `error`.
  void notice(BuildContext context, String message, {required String kind});

  /// Opens an external link (`HYPERLINK_CLICKED`).
  void openLink(String url);

  /// Undo / redo / dirty state changed: the shell refreshes its commands.
  void historyChanged();
}
