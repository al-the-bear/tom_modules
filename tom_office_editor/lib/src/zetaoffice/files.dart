// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// What `TomZetaOfficeView` needs from the machine, as interfaces without
/// `dart:io`: the cached ZetaOffice files ([TomZetaOfficeFiles]), the page
/// in the webview ([TomZetaOfficeChannel]) and the local server that hands
/// the files and the document to it ([TomZetaOfficeServing]). The real ones
/// are in `zetaoffice.dart`, fakes in `testing.dart`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// The state of the cached ZetaOffice files.
enum TomZetaOfficeCacheState {
  /// Not downloaded yet.
  missing,

  /// Present and their checksums match `zetaoffice.version`.
  ready,

  /// Present, but a file is gone or its checksum differs: downloaded again
  /// after the user confirms.
  damaged,
}

/// What the cache answers.
@immutable
final class TomZetaOfficeCacheStatus {
  /// A status from its parts.
  const TomZetaOfficeCacheStatus(this.state, {this.version, this.reason});

  /// The state.
  final TomZetaOfficeCacheState state;

  /// The cached version (the CDN's `Last-Modified`, and the product once a
  /// document reported it).
  final String? version;

  /// Why it is damaged.
  final String? reason;
}

/// The ZetaOffice files on the machine: downloaded once from
/// `cdn.zetaoffice.net` after the user confirms, kept with their checksums,
/// served from [folder].
abstract interface class TomZetaOfficeFiles {
  /// The cache folder (served as the page's `zeta/`).
  String get folder;

  /// Checks the cached files against their checksums.
  Future<TomZetaOfficeCacheStatus> status();

  /// The bytes the download will fetch, for the prompt (the CDN's sizes, or
  /// [kZetaOfficeDownloadBytes] when it cannot be asked).
  Future<int> downloadSize();

  /// Downloads the files, reporting the bytes received of [total].
  Future<void> download({void Function(int received, int total)? progress});

  /// Records the product name a document reported (`zetaoffice.version`).
  Future<void> recordProduct(String product);
}

/// The download the web spike measured (52.5 MB, Brotli).
const kZetaOfficeDownloadBytes = 52543023;

/// The webview between Dart and the host page: the real one is the
/// `TomZetaOfficeView`'s WKWebView, a test gives a fake. Dart never waits on
/// the page: [call] starts a bridge function, and everything the page says
/// comes back as [messages] (`{type, ...}`: `status`, `ready`, `loaded`,
/// `modified`, `history`, `saved`, `text`, `error`, `trail`).
abstract interface class TomZetaOfficeChannel {
  /// Loads [page].
  Future<void> load(Uri page);

  /// Calls `window.forgeBridge.<function>(...args)` in the page; completes
  /// once the page took the call, or after a few seconds when it does not
  /// answer (a page that hangs never hangs its caller).
  Future<void> call(String function, [List<Object?> args = const []]);

  /// The page as the webview shows it (PNG), or null.
  Future<Uint8List?> snapshot();

  /// What the page sent, and `{type: processGone}` when the webview's
  /// content process ended (the page is gone with it).
  Stream<Map<String, Object?>> get messages;
}

/// The local server of one ZetaOffice tab: the host page, the cached files,
/// the document, and the two POST routes the saved bytes come back by.
abstract interface class TomZetaOfficeServing {
  /// Starts serving the document at [documentPath] and the files of
  /// [files]; the saved bytes go to [onSave] and [onSaveCopy]. Returns the
  /// page's address with its query.
  Future<Uri> start({
    required String documentPath,
    required String name,
    required TomZetaOfficeFiles files,
    required FutureOr<void> Function(Uint8List bytes) onSave,
    required FutureOr<void> Function(Uint8List bytes) onSaveCopy,
  });

  /// The site's origin, for the webview's navigation check.
  Uri? get origin;

  /// Stops serving.
  Future<void> stop();
}
