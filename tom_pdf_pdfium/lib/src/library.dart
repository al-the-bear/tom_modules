// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/foundation.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart' show TomPdfEngineStatus;

/// The pdfium-binaries release the bindings were generated for; the locator
/// refuses a library whose version file names another.
const kPdfiumBindingsTag = 'chromium/8152';

/// Why the PDFium library cannot be used.
enum TomPdfiumProblem {
  /// No library at the expected place (*PDFium not found*).
  notFound,

  /// Its version file names another release (*PDFium version mismatch*).
  versionMismatch,
}

/// Where the PDFium library is, or why it cannot be used: what
/// `TomPdfiumLocator` answers, and the engine status a host hands the editor
/// (`TomPdfEditorHost.engineStatus`). The editor never starts on a library
/// it was not built for.
@immutable
final class TomPdfiumLibrary implements TomPdfEngineStatus {
  /// A usable library at [path], of release [tag].
  const TomPdfiumLibrary.found(String this.path, this.tag) : problem = null;

  /// A library that cannot be used; [path] is where it was looked for.
  const TomPdfiumLibrary.problem(
    TomPdfiumProblem this.problem,
    this.path, {
    this.tag = '',
  });

  /// The library's path, or where it was looked for.
  final String? path;

  /// The release its version file names (empty when unknown).
  final String tag;

  /// Why it cannot be used, or `null` when it can.
  final TomPdfiumProblem? problem;

  /// Whether the engine can be started on it.
  @override
  bool get isUsable => problem == null;

  /// The tab's message for a problem.
  @override
  String get message => switch (problem) {
    null => 'PDFium $tag at $path',
    TomPdfiumProblem.notFound =>
      'PDFium not found${path == null ? '' : ' at $path'}',
    TomPdfiumProblem.versionMismatch =>
      'PDFium version mismatch: $path is ${tag.isEmpty ? 'of an unknown release' : tag}, '
          'this editor was built for $kPdfiumBindingsTag',
  };

  @override
  String toString() => 'TomPdfiumLibrary($message)';
}
