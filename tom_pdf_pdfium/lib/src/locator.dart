// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';

import 'library.dart';

/// Finds the PDFium library in the binaries layer:
/// `<binaries root>/pdfium/<platform>/libpdfium.dylib`, the binaries root
/// being the parent of `TOM_BINARY_PATH` (`tom_binaries/tom` → `tom_binaries`)
/// unless the host gives one, or an explicit [libraryPath]. It checks that
/// the file exists and that its `pdfium.version.json` names the release the
/// bindings were generated for ([kPdfiumBindingsTag]).
class TomPdfiumLocator {
  /// A locator; [binariesRoot] is `tom_binaries`, [libraryPath] a library
  /// anywhere (its version file beside it). [environment] stands in for
  /// `Platform.environment` in tests.
  const TomPdfiumLocator({
    this.binariesRoot,
    this.libraryPath,
    this.platform = 'darwin-arm64',
    this.environment,
  });

  /// The binaries repository's root (`tom_binaries`).
  final String? binariesRoot;

  /// An explicit library path.
  final String? libraryPath;

  /// The platform folder.
  final String platform;

  /// The environment `TOM_BINARY_PATH` is read from.
  final Map<String, String>? environment;

  /// The library's file name on the platform.
  String get fileName => switch (platform) {
    final p when p.startsWith('darwin') => 'libpdfium.dylib',
    final p when p.startsWith('win32') => 'pdfium.dll',
    _ => 'libpdfium.so',
  };

  /// Where the library is expected, or `null` when no root is known.
  String? get expectedPath {
    if (libraryPath != null) return libraryPath;
    var root = binariesRoot;
    if (root == null) {
      final tom = (environment ?? Platform.environment)['TOM_BINARY_PATH'];
      if (tom == null || tom.isEmpty) return null;
      root = Directory(tom).parent.path;
    }
    return '$root/pdfium/$platform/$fileName';
  }

  /// Where the library is, or why it cannot be used.
  TomPdfiumLibrary locate() {
    final path = expectedPath;
    if (path == null || !File(path).existsSync()) {
      return TomPdfiumLibrary.problem(TomPdfiumProblem.notFound, path);
    }
    final versionFile = File('${File(path).parent.path}/pdfium.version.json');
    var tag = '';
    try {
      final json = jsonDecode(versionFile.readAsStringSync());
      if (json is Map && json['tag'] is String) tag = json['tag'] as String;
    } on Object {
      // A missing or unreadable version file: an unknown release.
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
