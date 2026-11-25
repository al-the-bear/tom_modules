// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';

import 'package:tom_basics/native_binaries.dart';

import 'library.dart';

/// Finds the PDFium library:
///
/// 1. **In the running application's bundle** (an application started from
///    the Finder or the Start menu sees no `TOM_BINARY_PATH`): macOS
///    `<App>.app/Contents/Frameworks/libpdfium.dylib`, then
///    `Contents/MacOS/`; Linux beside the executable, then in the bundle's
///    `lib/`; Windows beside the executable (`pdfium.dll`). The bundle is
///    found from `Platform.resolvedExecutable`; [bundleFolders] replaces its
///    folders (tests). `dart test` and `flutter test` run from no bundle.
/// 2. **In the binaries layer**: `<binaries root>/pdfium/<platform>/<file>`,
///    the binaries root being the parent of `TOM_BINARY_PATH`
///    (`tom_binaries/tom` → `tom_binaries`) unless the host gives one.
///
/// An explicit [libraryPath] replaces both. It checks that the file exists
/// and that its `pdfium.version.json` — beside the library, or in a macOS
/// bundle's `Contents/Resources/` — names the release the bindings were
/// generated for ([kPdfiumBindingsTag]).
class TomPdfiumLocator {
  /// A locator; [binariesRoot] is `tom_binaries`, [libraryPath] a library
  /// anywhere (its version file beside it), [platform] the binaries layer's
  /// platform folder (default the running platform's, `darwin-arm64`).
  /// [environment] stands in for `Platform.environment` and [bundleFolders]
  /// for the running application's bundle folders in tests.
  const TomPdfiumLocator({
    this.binariesRoot,
    this.libraryPath,
    this.platform,
    this.environment,
    this.bundleFolders,
  });

  /// The binaries repository's root (`tom_binaries`).
  final String? binariesRoot;

  /// An explicit library path.
  final String? libraryPath;

  /// The platform folder; `null` for the running platform's.
  final String? platform;

  /// The environment `TOM_BINARY_PATH` is read from.
  final Map<String, String>? environment;

  /// The bundle folders looked in first; `null` for the running
  /// application's.
  final List<String>? bundleFolders;

  /// The binaries layer's platform folder: [platform] or the running one.
  String get platformFolder => platform ?? TomNativeBinaries.platformFolder();

  /// The library's file name on the platform.
  String get fileName => switch (platformFolder) {
    final p when p.startsWith('darwin') => 'libpdfium.dylib',
    final p when p.startsWith('win32') => 'pdfium.dll',
    _ => 'libpdfium.so',
  };

  /// The library in the application's bundle, or `null`.
  String? get bundlePath => TomNativeBinaries.findInBundle(
    fileName,
    kind: TomNativeFileKind.library,
    bundleFolders: bundleFolders,
  );

  /// Where the binaries layer keeps the library, or `null` when no root is
  /// known.
  String? get binariesPath {
    final root =
        binariesRoot ??
        TomNativeBinaries.binariesRepository(environment: environment);
    if (root == null) return null;
    return '$root/pdfium/$platformFolder/$fileName';
  }

  /// Where the library is expected: [libraryPath], else the bundle's copy
  /// when there is one, else the binaries layer's place; `null` when none
  /// is known.
  String? get expectedPath => libraryPath ?? bundlePath ?? binariesPath;

  /// Where the library is, or why it cannot be used.
  TomPdfiumLibrary locate() {
    final path = expectedPath;
    if (path == null || !File(path).existsSync()) {
      return TomPdfiumLibrary.problem(TomPdfiumProblem.notFound, path);
    }
    final folder = File(path).parent;
    var tag = '';
    for (final versionFile in [
      File('${folder.path}/pdfium.version.json'),
      // A macOS bundle keeps non-code files out of Contents/Frameworks/.
      File('${folder.parent.path}/Resources/pdfium.version.json'),
    ]) {
      if (!versionFile.existsSync()) continue;
      try {
        final json = jsonDecode(versionFile.readAsStringSync());
        if (json is Map && json['tag'] is String) tag = json['tag'] as String;
      } on Object {
        // An unreadable version file: an unknown release.
      }
      break;
    }
    if (tag != kPdfiumBindingsTag) {
      return TomPdfiumLibrary.problem(
        TomPdfiumProblem.versionMismatch,
        path,
        tag: tag,
      );
    }
    return TomPdfiumLibrary.found(path, tag);
  }
}
