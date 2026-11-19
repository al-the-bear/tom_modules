// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The example app on mbp: each sample (DOCX, XLSX, PPTX) opens with the
/// installed LibreOffice and the helper from the binaries layer, shows its
/// tiles, takes an edit, saves with Cmd+S and reopens.
///
/// ```sh
/// cd tom_ai/modules/tom_office_editor/example
/// flutter test integration_test/samples_test.dart -d macos
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_editor_example/main.dart';

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what, {
  int seconds = 120,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('no $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _contents(String path) {
  final part = switch (p.extension(path)) {
    '.docx' => 'word/document.xml',
    '.xlsx' => 'xl/sharedStrings.xml',
    '.pptx' => 'ppt/slides/slide1.xml',
    final ext => throw ArgumentError(ext),
  };
  return Process.runSync('unzip', ['-p', path, part]).stdout as String;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OE-APP-1: DOCX, XLSX and PPTX open, edit, save and reopen', (
    tester,
  ) async {
    await tester.pumpWidget(const OfficeEditorExampleApp());
    final page = tester.state<OfficeEditorExamplePageState>(
      find.byType(OfficeEditorExamplePage),
    );
    await _until(
      tester,
      () =>
          find
              .byKey(const ValueKey('sample-letter.docx'))
              .evaluate()
              .isNotEmpty &&
          tester
                  .widget<TextButton>(
                    find.byKey(const ValueKey('sample-letter.docx')),
                  )
                  .onPressed !=
              null,
      'detection',
    );
    for (final (sample, marker) in [
      ('letter.docx', 'OEAPPDOCX'),
      ('sheet.xlsx', 'OEAPPXLSX'),
      ('deck.pptx', 'OEAPPPPTX'),
    ]) {
      await tester.tap(find.byKey(ValueKey('sample-$sample')));
      await _until(
        tester,
        () => page.controller?.state == TomOfficeEditorState.open,
        '$sample open (${page.controller?.state} ${page.controller?.error})',
      );
      final c = page.controller!;
      await _until(tester, () => c.tiles.length >= 4, '$sample tiles');
      // Focus the document with a click (it may select a shape: the
      // letter's logo, a slide's title); Escape leaves it, Cmd+Home goes to
      // the start of the text (cell A1 in the sheet).
      final view = find.byType(TomOfficeDocumentView);
      expect(view, findsOneWidget);
      await tester.tapAt(tester.getTopLeft(view) + const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 300));
      c.key(VclKey.escape);
      if (c.docType == OfficeDocType.presentation) {
        c.key(VclKey.tab); // the first shape
        c.key(VclKey.enter); // its text
      } else {
        c.key(VclKey.home | VclKey.mod1);
      }
      await tester.pump(const Duration(milliseconds: 300));
      // A key through the view: the caret moves right and back.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 300));
      c.typeText('$marker ');
      if (c.docType == OfficeDocType.spreadsheet) c.key(VclKey.enter);
      if (c.docType == OfficeDocType.presentation) c.key(VclKey.escape);
      await _until(tester, () => c.isDirty, '$sample dirty');
      // Cmd+S through the app's shortcut.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await _until(
        tester,
        () => !c.isDirty && c.state == TomOfficeEditorState.open,
        '$sample saved',
      );
      final path = page.filePath!;
      await _until(
        tester,
        () => _contents(path).contains(marker),
        '$marker in $path',
        seconds: 20,
      );
      // Reopen: the saved file loads again.
      await tester.tap(find.byKey(const ValueKey('example-reopen')));
      await _until(
        tester,
        () =>
            page.controller != c &&
            page.controller?.state == TomOfficeEditorState.open,
        '$sample reopened',
      );
      await _until(tester, () => page.controller!.tiles.length >= 4, 'tiles');
      await tester.pump(const Duration(milliseconds: 500));
    }
    await page.controller?.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
