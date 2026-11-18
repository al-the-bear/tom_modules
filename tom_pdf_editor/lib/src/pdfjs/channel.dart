// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// How much of pdf.js's own interface the view shows (DPPJ-2); the host
/// chooses.
enum TomPdfJsMode {
  /// pdf.js's generic viewer with what the shell does itself hidden (open,
  /// print, download, present, bookmark, its find bar).
  integrated,

  /// pdf.js's generic viewer unchanged.
  full,

  /// pdf.js's viewer components in Forge's own page, with a small toolbar
  /// drawn in Flutter above the webview.
  components,
}

/// pdf.js's annotation editor tools (its `AnnotationEditorType`), as the
/// bridge's `setTool` takes them.
abstract final class TomPdfJsTool {
  /// No tool: select text, fill forms, click links.
  static const none = 0;

  /// Free text: click, type.
  static const freeText = 3;

  /// Highlight: select text, or draw.
  static const highlight = 9;

  /// Stamp: an image from a file.
  static const stamp = 13;

  /// Ink: draw.
  static const ink = 15;
}

/// The webview between Dart and a pdf.js page: the real one is the
/// `TomPdfJsView`'s WKWebView (`pdfjs.dart`), a test gives a fake.
///
/// Dart never waits on the page: [call] starts a bridge function and
/// returns, and everything the page says comes back as [messages]
/// (`{type, ...}`: `ready`, `loaded`, `textLayer`, `modified`, `history`,
/// `findCount`, `tool`, `saved`, `error`, `openLink`, `passwordRequested`,
/// `shortcut`, `trail`).
abstract interface class TomPdfJsChannel {
  /// Loads [page] into the webview.
  Future<void> load(Uri page);

  /// Calls `window.forgeBridge.<function>(...args)` in the page, without
  /// waiting for what it does. [args] are JSON values.
  Future<void> call(String function, [List<Object?> args = const []]);

  /// The messages the page sent through the bridge.
  Stream<Map<String, Object?>> get messages;
}
