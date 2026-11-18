// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/widgets.dart';
import 'package:tom_file_session/tom_file_session.dart';

import '../engine/engine.dart';
import '../engine/library.dart';
import '../host.dart';

/// A [TomPdfEditorHost] for tests: it records notices, links and history
/// changes, and hands out the engine it was given.
class FakePdfEditorHost implements TomPdfEditorHost {
  FakePdfEditorHost({
    required this.filePath,
    required this.files,
    required this.engine,
    this.authorName = 'Test Author',
    TomPdfiumLibrary? pdfium,
  }) : pdfium =
           pdfium ??
           const TomPdfiumLibrary.found(
             '/fake/libpdfium.dylib',
             kPdfiumBindingsTag,
           );

  @override
  final String filePath;

  @override
  final TomBinaryFiles files;

  /// The engine [startEngine] hands out.
  final TomPdfEngine engine;

  @override
  final String authorName;

  @override
  final TomPdfiumLibrary pdfium;

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
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library) async {
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
