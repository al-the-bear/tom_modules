// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// A run of an install route as the host reports it to
/// `TomLibreOfficeInstallHelp`: its output as it comes and its end. Pure
/// Dart; the host runs the commands.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'libreoffice_tool.dart';

/// How an install run ended.
@immutable
final class TomLibreOfficeInstallResult {
  /// An end from its parts.
  const TomLibreOfficeInstallResult(this.exitCode, {this.message});

  /// The last command's exit code (−1: it could not be started, a hash did
  /// not match, it was stopped).
  final int exitCode;

  /// What the host says about it, e.g. *The SHA-256 does not match.*
  final String? message;

  /// Whether every command exited 0.
  bool get ok => exitCode == 0;

  @override
  String toString() =>
      'TomLibreOfficeInstallResult($exitCode'
      '${message == null ? '' : ', $message'})';
}

/// One run of a route: [output] streams what the commands print (text as
/// it comes; the widget shows it as it is), [result] completes with the
/// end. [cancel], when given, stops it.
final class TomLibreOfficeInstallRun {
  /// A run from its parts.
  TomLibreOfficeInstallRun({
    required this.output,
    required this.result,
    this.cancel,
  });

  /// A run that ended at once (e.g. the host refused it).
  factory TomLibreOfficeInstallRun.finished(
    TomLibreOfficeInstallResult result, {
    String output = '',
  }) => TomLibreOfficeInstallRun(
    output: output.isEmpty ? const Stream.empty() : Stream.value(output),
    result: Future.value(result),
  );

  /// The commands' output.
  final Stream<String> output;

  /// The end.
  final Future<TomLibreOfficeInstallResult> result;

  /// Stops the run (the host kills its process); `null` when it cannot be
  /// stopped.
  final VoidCallback? cancel;
}

/// What a host builds a [TomLibreOfficeInstallRun] with: [add] the output
/// as it comes, [finish] at the end.
///
/// ```dart
/// final c = TomLibreOfficeInstallRunController();
/// final process = await Process.start(argv.first, argv.sublist(1));
/// process.stdout.transform(utf8.decoder).listen(c.add);
/// process.stderr.transform(utf8.decoder).listen(c.add);
/// process.exitCode.then(c.finish);
/// return c.run;
/// ```
final class TomLibreOfficeInstallRunController {
  /// A controller; [onCancel] makes the run stoppable.
  TomLibreOfficeInstallRunController({VoidCallback? onCancel})
    : _onCancel = onCancel;

  final VoidCallback? _onCancel;
  // Single-subscription: output added before the widget listens is kept.
  final _output = StreamController<String>();
  final _done = Completer<TomLibreOfficeInstallResult>();

  /// The run the widget is given.
  late final TomLibreOfficeInstallRun run = TomLibreOfficeInstallRun(
    output: _output.stream,
    result: _done.future,
    cancel: _onCancel,
  );

  /// Whether [finish] was called.
  bool get isFinished => _done.isCompleted;

  /// Adds output.
  void add(String text) {
    if (!_output.isClosed) _output.add(text);
  }

  /// Ends the run with [exitCode]; later calls are ignored.
  void finish(int exitCode, {String? message}) {
    if (_done.isCompleted) return;
    unawaited(_output.close());
    _done.complete(TomLibreOfficeInstallResult(exitCode, message: message));
  }
}

/// Runs [route] for the user (after the widget's confirmation): the host
/// runs its commands (a managed download first downloads, checks and
/// unpacks the archive) and reports through the run.
typedef TomLibreOfficeInstaller =
    TomLibreOfficeInstallRun Function(TomInstallRoute route);
