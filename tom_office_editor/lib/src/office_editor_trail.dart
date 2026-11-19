// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/foundation.dart';

// ============================================================
// DEBUG MODE SWITCH — Office Editor (tom_office_editor)
// ============================================================
// true  → event trail + heartbeat + FlutterError intercept enabled
// false → no trail (errors are reported either way)
//
// KEEP THIS FLAG. Do NOT remove even when not actively debugging.
// Switchable at run time (a host or a test sets it), like the YAML and
// Markdown editors' flags; off by default because the trail's
// FlutterError.onError intercept replaces the host's handler.
// ============================================================
bool kOfficeEditorDebug = false;

/// Logs a timestamped event (no-op while [kOfficeEditorDebug] is false).
///
/// Filter the output with the prefix: `flutter run 2>&1 | grep '\[OE'`.
/// Never pass typed text or a password here: input is logged as kind and key
/// code (the text's length at most), passwords as `password <redacted>`.
void officeTrail(String event) {
  if (!kOfficeEditorDebug) return;
  final now = DateTime.now();
  final ts =
      '${now.hour.toString().padLeft(2, '0')}'
      ':${now.minute.toString().padLeft(2, '0')}'
      ':${now.second.toString().padLeft(2, '0')}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('[OE $ts] $event');
}

/// Reports [error] through [FlutterError.reportError], whether the trail is
/// on or off, and logs it to the trail.
void officeReport(Object error, StackTrace stack, String context) {
  officeTrail('ERROR $context: $error');
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'tom_office_editor',
      context: ErrorDescription(context),
    ),
  );
}
