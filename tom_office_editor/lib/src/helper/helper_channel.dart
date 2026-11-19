// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The editor's line to its helper: [TomOfficeHelperChannel], and the
/// [TomOfficeHelperLauncher] that starts one. The process-backed launcher is
/// `TomOfficeProcessLauncher` in `io.dart`; tests use the fake in
/// `testing.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import '../detection/installation.dart';

/// How a helper ended.
@immutable
final class TomOfficeHelperExit {
  /// An exit from its parts.
  const TomOfficeHelperExit({this.code, this.reason, this.stderrTail = ''});

  /// The exit code, or `null` when not known (a fake, a hang).
  final int? code;

  /// What ended it, in words: `exit 0`, `signal 9`, `hang (no pong in 20 s)`.
  final String? reason;

  /// The last lines of its stderr.
  final String stderrTail;

  /// Whether it ended after a clean `close` (exit code 0).
  bool get clean => code == 0;

  @override
  String toString() => reason ?? 'exit $code';
}

/// One running helper, speaking protocol 1.
abstract interface class TomOfficeHelperChannel {
  /// The helper's messages, decoded. The stream ends when the helper's
  /// stdout ends; a refused frame ends it with an error.
  Stream<OfficeHelperEvent> get events;

  /// The helper's log lines (stderr).
  Stream<String> get log;

  /// Sends [command].
  void send(OfficeHelperCommand command);

  /// Completes when the helper process has ended.
  Future<TomOfficeHelperExit> get exit;

  /// Ends the helper: `close`, then SIGTERM after 5 s, SIGKILL after 2 s
  /// more. Completes with its exit.
  Future<TomOfficeHelperExit> close();

  /// Kills the helper at once (a hang).
  void kill();
}

/// Starts helpers for the editor: the detection result it starts them with,
/// and the start itself.
abstract interface class TomOfficeHelperLauncher {
  /// The LibreOffice the helpers run against.
  LibreOfficeInstallation get installation;

  /// Starts a helper for the document at [documentPath] (recorded so a
  /// later clean-up can remove the lock file a killed helper leaves beside
  /// it).
  Future<TomOfficeHelperChannel> start({required String documentPath});
}
