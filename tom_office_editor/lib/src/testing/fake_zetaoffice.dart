// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:typed_data';

import '../zetaoffice/files.dart';

/// Cached ZetaOffice files without a disk: [state] answers [status];
/// [download] counts and makes them ready.
class FakeZetaOfficeFiles implements TomZetaOfficeFiles {
  /// Files in [state].
  FakeZetaOfficeFiles({
    this.state = TomZetaOfficeCacheState.missing,
    this.size = kZetaOfficeDownloadBytes,
    this.failDownload = false,
  });

  /// The cache's state.
  TomZetaOfficeCacheState state;

  /// The download's size.
  final int size;

  /// Whether the download fails.
  final bool failDownload;

  /// Downloads made.
  int downloads = 0;

  /// The product recorded.
  String? product;

  @override
  String get folder => '/cache/zetaoffice';

  @override
  Future<TomZetaOfficeCacheStatus> status() async => TomZetaOfficeCacheStatus(
    state,
    reason: state == TomZetaOfficeCacheState.damaged
        ? 'soffice.wasm.br does not match its checksum'
        : null,
  );

  @override
  Future<int> downloadSize() async => size;

  @override
  Future<void> download({
    void Function(int received, int total)? progress,
  }) async {
    downloads++;
    if (failDownload) throw StateError('offline');
    progress?.call(size ~/ 2, size);
    progress?.call(size, size);
    state = TomZetaOfficeCacheState.ready;
  }

  @override
  Future<void> recordProduct(String product) async => this.product = product;
}

/// A server without a socket: [start] keeps the save routes, which a test
/// calls as the page's POST would ([postSave], [postCopy]).
class FakeZetaOfficeServing implements TomZetaOfficeServing {
  /// The page's address.
  static final page = Uri.parse('http://127.0.0.1:1/token/host/index.html');

  FutureOr<void> Function(Uint8List bytes)? _save;
  FutureOr<void> Function(Uint8List bytes)? _copy;

  /// Starts made.
  int starts = 0;

  /// Whether it is serving.
  bool serving = false;

  @override
  Uri? get origin => serving ? Uri.parse('http://127.0.0.1:1') : null;

  @override
  Future<Uri> start({
    required String documentPath,
    required String name,
    required TomZetaOfficeFiles files,
    required FutureOr<void> Function(Uint8List bytes) onSave,
    required FutureOr<void> Function(Uint8List bytes) onSaveCopy,
  }) async {
    starts++;
    serving = true;
    _save = onSave;
    _copy = onSaveCopy;
    return page;
  }

  /// The page posts the saved bytes.
  Future<void> postSave(List<int> bytes) async =>
      _save!(Uint8List.fromList(bytes));

  /// The page posts a copy's bytes.
  Future<void> postCopy(List<int> bytes) async =>
      _copy!(Uint8List.fromList(bytes));

  @override
  Future<void> stop() async => serving = false;
}

/// The page without a webview: [loaded] records the pages loaded, [calls]
/// the bridge calls; [emit] sends what the page would.
class FakeZetaOfficeChannel implements TomZetaOfficeChannel {
  final _messages = StreamController<Map<String, Object?>>.broadcast();

  /// The pages loaded.
  final loaded = <Uri>[];

  /// The bridge calls, as `function` or `function(args)`.
  final calls = <String>[];

  /// What happens on a bridge call (a test answers `save` with bytes).
  void Function(String function, List<Object?> args)? onCall;

  /// Sends [message] as the page would.
  void emit(Map<String, Object?> message) => _messages.add(message);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<void> load(Uri page) async => loaded.add(page);

  /// What [snapshot] answers.
  Uint8List? snapshotBytes;

  @override
  Future<Uint8List?> snapshot() async => snapshotBytes;

  @override
  Future<void> call(String function, [List<Object?> args = const []]) async {
    calls.add(args.isEmpty ? function : '$function(${args.join(', ')})');
    onCall?.call(function, args);
  }
}
