// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/widgets.dart';
import 'package:tom_file_session/tom_file_session.dart';

import 'engine/engine.dart';

/// What every PDF view asks of the application: the editor over a
/// [TomPdfEngine] ([TomPdfEditorHost]) and the views of the engine packages
/// that render in a view of their own. It has the shape of
/// `TomOfficeEditorHost`, so the Forge integration treats every view alike.
abstract interface class TomPdfViewHost {
  /// The file's name, for notices and history labels.
  String get name;

  /// Its absolute path.
  String get filePath;

  /// `T` (the author) of the annotations the editor creates.
  String get authorName;

  /// Revision, temporary target and replace (`TomBinaryFileAccess` over
  /// `dart:io` in a desktop host).
  TomBinaryFiles get files;

  /// Shows [message]; [kind] is `info`, `warning` or `error`.
  void notice(BuildContext context, String message, {required String kind});

  /// Opens an external link.
  void openLink(String url);

  /// Undo / redo / dirty state changed: the shell refreshes its commands.
  void historyChanged();
}

/// Whether the engine can be started, and the tab's message about it: what
/// an engine package's locator answers (e.g. the native library found, of
/// the release the engine was built for). The editor never starts an engine
/// whose status is not usable; it shows [message] instead.
abstract interface class TomPdfEngineStatus {
  /// Whether the engine can be started.
  bool get isUsable;

  /// What the status is, for the trail and, when not usable, for the tab.
  String get message;
}

/// What the editor ([TomPdfEditor] over a [TomPdfEngine]) asks of the
/// application besides [TomPdfViewHost]: the engine's status and the
/// engine. The engine itself comes from an engine package.
abstract interface class TomPdfEditorHost implements TomPdfViewHost {
  /// Whether the engine can be started, or why not. An engine package's
  /// status type implements [TomPdfEngineStatus]; a host may declare that
  /// type here.
  TomPdfEngineStatus get engineStatus;

  /// The engine for [status] (the usable [engineStatus] the editor read; a
  /// host may declare its engine package's status type for it): typically
  /// one engine shared by every PDF tab. The editor gives its share up with
  /// [TomPdfEngine.release] when it closes.
  Future<TomPdfEngine> startEngine(covariant TomPdfEngineStatus status);
}
