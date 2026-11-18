// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';

import '../pdfjs/channel.dart';

/// A [TomPdfJsChannel] for tests: it records the pages loaded and the bridge
/// calls made, and [send]s messages as the page would. [onCall] lets a test
/// answer a call (e.g. post the saved bytes, then send `saved`).
class FakePdfJsChannel implements TomPdfJsChannel {
  FakePdfJsChannel({this.onCall});

  /// Answers a call, as the page would.
  FutureOr<void> Function(String function, List<Object?> args)? onCall;

  /// The pages loaded, in order.
  final loads = <Uri>[];

  /// The calls made, as `(function, args)`.
  final calls = <(String, List<Object?>)>[];

  final _messages = StreamController<Map<String, Object?>>.broadcast();

  /// The names of the calls made, in order.
  List<String> get callNames => [for (final c in calls) c.$1];

  /// Sends [message] as the page would.
  void send(Map<String, Object?> message) => _messages.add(message);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<void> load(Uri page) async => loads.add(page);

  @override
  Future<void> call(String function, [List<Object?> args = const []]) async {
    calls.add((function, args));
    await onCall?.call(function, args);
  }
}
