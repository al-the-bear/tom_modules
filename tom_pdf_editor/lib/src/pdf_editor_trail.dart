// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/foundation.dart';

// ============================================================
// DEBUG MODE SWITCH — PDF Editor (tom_pdf_editor)
// ============================================================
// true  → event trail + heartbeat + FlutterError intercept enabled
// false → no trail (errors are reported either way)
//
// KEEP THIS FLAG. Do NOT remove even when not actively debugging.
// Switchable at run time (a host or a test sets it), like the YAML and
// Markdown editors' flags; off by default because the trail's
// FlutterError.onError intercept replaces the host's handler.
// ============================================================
bool kPdfEditorDebug = false;

/// Logs a timestamped event (no-op while [kPdfEditorDebug] is false).
///
/// Filter the output with the prefix: `flutter run 2>&1 | grep '\[PE'`.
/// Never pass a search term or a password: searches are logged by length,
/// passwords as `password <redacted>`.
void pdfTrail(String event) => _trail('PE', event);

/// The pdf.js view's trail: the same flag, the prefix `[PE:js]`.
void pdfJsTrail(String event) => _trail('PE:js', event);

void _trail(String prefix, String event) {
  if (!kPdfEditorDebug) return;
  final now = DateTime.now();
  final ts =
      '${now.hour.toString().padLeft(2, '0')}'
      ':${now.minute.toString().padLeft(2, '0')}'
      ':${now.second.toString().padLeft(2, '0')}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('[$prefix $ts] $event');
}

/// One trail line for a Flutter error: its message, the library that reported
/// it and the first line its information collector gives — for a layout
/// overflow, the widget that overflowed (`The relevant error-causing widget
/// was: Row ...`), so a report names it.
String pdfErrorSummary(FlutterErrorDetails details) {
  final message = details.exceptionAsString().split('\n').first.trim();
  final parts = <String>[message];
  if (details.library != null) parts.add('library: ${details.library}');
  try {
    for (final node in details.informationCollector?.call() ?? const []) {
      final line = node
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join(' ');
      if (line.isNotEmpty) {
        parts.add(line);
        break;
      }
    }
  } catch (e) {
    parts.add('(information collector failed: $e)');
  }
  return parts.join(' | ');
}

/// Reports [error] through [FlutterError.reportError] whether the trail is on
/// or off, and logs it to the trail.
void pdfReport(Object error, StackTrace stack, String context) {
  pdfTrail('ERROR $context: $error');
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'tom_pdf_editor',
      context: ErrorDescription(context),
    ),
  );
}
