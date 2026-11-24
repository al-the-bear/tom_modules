// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/widgets.dart';
import 'package:tom_file_session/tom_file_session.dart';

import '../engine/engine.dart';
import '../host.dart';

/// A [TomPdfEngineStatus] for tests: usable, or not with the message the tab
/// shows.
final class FakePdfEngineStatus implements TomPdfEngineStatus {
  /// A usable engine.
  const FakePdfEngineStatus.usable([this.message = 'fake engine'])
    : isUsable = true;

  /// An engine that cannot be started, for the reason [message] gives.
  const FakePdfEngineStatus.problem(this.message) : isUsable = false;

  @override
  final bool isUsable;

  @override
  final String message;

  @override
  String toString() => 'FakePdfEngineStatus($message)';
}

/// A [TomPdfEditorHost] for tests: it records notices, links and history
/// changes, and hands out the engine it was given.
class FakePdfEditorHost implements TomPdfEditorHost {
  FakePdfEditorHost({
    required this.filePath,
    required this.files,
    required this.engine,
    this.authorName = 'Test Author',
    TomPdfEngineStatus? engineStatus,
  }) : engineStatus = engineStatus ?? const FakePdfEngineStatus.usable();

  @override
  final String filePath;

  @override
  final TomBinaryFiles files;

  /// The engine [startEngine] hands out.
  final TomPdfEngine engine;

  @override
  final String authorName;

  @override
  final TomPdfEngineStatus engineStatus;

  /// `(kind, message)` of every notice.
  final notices = <(String, String)>[];

  /// Every link opened.
  final links = <String>[];

  /// How often [historyChanged] was called.
  int historyChanges = 0;

  /// How often [startEngine] was called.
  int engineStarts = 0;

  @override
  String get name => filePath.split('/').last;

  @override
  Future<TomPdfEngine> startEngine(TomPdfEngineStatus status) async {
    engineStarts++;
    return engine;
  }

  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      notices.add((kind, message));

  @override
  void openLink(String url) => links.add(url);

  @override
  void historyChanged() => historyChanges++;
}
