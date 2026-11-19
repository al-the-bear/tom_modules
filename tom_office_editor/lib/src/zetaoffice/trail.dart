// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/foundation.dart';

// ============================================================
// DEBUG MODE SWITCH — ZetaOffice view (tom_office_editor)
// ============================================================
// true  → event trail + heartbeat + FlutterError intercept enabled
// false → no trail (errors are reported either way)
//
// KEEP THIS FLAG. Switchable at run time, like the office editor's
// kOfficeEditorDebug; off by default.
// ============================================================
bool kZetaOfficeDebug = false;

/// Logs a timestamped ZetaOffice event (no-op while [kZetaOfficeDebug] is
/// false). Filter with `grep '\[ZO'`. Never the document's text or bytes:
/// sizes and kinds only.
void zetaTrail(String event) {
  if (!kZetaOfficeDebug) return;
  final now = DateTime.now();
  final ts =
      '${now.hour.toString().padLeft(2, '0')}'
      ':${now.minute.toString().padLeft(2, '0')}'
      ':${now.second.toString().padLeft(2, '0')}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('[ZO $ts] $event');
}

/// Reports [error] through [FlutterError.reportError] whether the trail is
/// on or off, and logs it to the trail.
void zetaReport(Object error, StackTrace stack, String context) {
  zetaTrail('ERROR $context: $error');
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'tom_office_editor (ZetaOffice)',
      context: ErrorDescription(context),
    ),
  );
}
