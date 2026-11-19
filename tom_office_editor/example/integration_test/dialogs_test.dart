// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// LibreOffice's dialogs in window mode on mbp: Character, Paragraph, Page
/// Style, Find & Replace (text), Format Cells, the colour dialog (through
/// Format Cells' Background page and *Pick…*, as the spike reached it),
/// Insert Chart (spreadsheet) and Insert Table (presentation) open from the
/// ribbon, are painted, take keys and mouse, and close.
///
/// ```sh
/// cd tom_ai/modules/tom_office_editor/example
/// flutter test integration_test/dialogs_test.dart -d macos
/// ```
///
/// `TOM_OFFICE_DIALOG_SHOTS`: a folder to write each dialog's pixels to as
/// PNG (for looking at them).
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_editor_example/main.dart';

void _step(String what) => debugPrint('[DIALOG-IT] $what');

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what, {
  int seconds = 30,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('no $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _wait(WidgetTester tester, [int ms = 500]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _wait(tester, 300);
}

/// The number of distinct colours in [image] (a blank one has one).
Future<int> _colours(WidgetTester tester, ui.Image image) async {
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final bytes = data!.buffer.asUint32List();
  return bytes.toSet().length;
}

Future<void> _shot(WidgetTester tester, String name, ui.Image image) async {
  final folder = Platform.environment['TOM_OFFICE_DIALOG_SHOTS'];
  if (folder == null) return;
  final png = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('$folder/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

Future<TomOfficeEditorController> _open(
  WidgetTester tester,
  OfficeEditorExamplePageState page,
  String sample,
) async {
  _step('open $sample');
  await tester.tap(find.byKey(ValueKey('sample-$sample')));
  await _until(
    tester,
    () => page.controller?.state == TomOfficeEditorState.open,
    '$sample open',
    seconds: 120,
  );
  final c = page.controller!;
  await _until(tester, () => c.tiles.length >= 4, 'tiles');
  final view = find.byType(TomOfficeDocumentView);
  await tester.tapAt(tester.getTopLeft(view) + const Offset(40, 40));
  await _wait(tester, 300);
  c.key(VclKey.escape);
  await _wait(tester, 300);
  return c;
}

/// Waits for a dialog titled [title] and its pixels; returns it.
Future<TomOfficeWindow> _dialog(
  WidgetTester tester,
  TomOfficeEditorController c,
  String title,
) async {
  await _until(
    tester,
    () => c.windows.any((w) => w.isDialog && w.title.contains(title)),
    'dialog $title (${c.windows.map((w) => w.title)})',
  );
  final w = c.windows.lastWhere((w) => w.title.contains(title));
  await _until(tester, () => w.image != null, '$title painted');
  expect(
    find.byKey(ValueKey('office-window-pixels-${w.id}')),
    findsOneWidget,
    reason: '$title shown',
  );
  expect(
    tester.getSize(find.byKey(ValueKey('office-window-pixels-${w.id}'))),
    Size(w.width.toDouble(), w.height.toDouble()),
  );
  final colours = await _colours(tester, w.image!);
  expect(colours, greaterThan(8), reason: '$title is not blank');
  await _shot(tester, title.replaceAll(RegExp(r'[^A-Za-z]'), '_'), w.image!);
  _step('$title: ${w.width}x${w.height}, $colours colours');
  return w;
}

/// Keys reach [w]: Tab moves its focus, which LibreOffice answers with a
/// repaint or a cursor change.
Future<void> _works(WidgetTester tester, TomOfficeWindow w) async {
  final before = w.changes;
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await _until(
    tester,
    () => w.changes > before,
    '${w.title} answering Tab',
    seconds: 10,
  );
}

/// Escape closes [w] (LibreOffice's cancel).
Future<void> _close(
  WidgetTester tester,
  TomOfficeEditorController c,
  TomOfficeWindow w,
) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await _until(
    tester,
    () => !c.windows.any((x) => x.id == w.id),
    '${w.title} closed',
    seconds: 15,
  );
  _step('${w.title} closed');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OE-DIALOG-APP: the dialogs open, work and close as windows', (
    tester,
  ) async {
    await tester.pumpWidget(const OfficeEditorExampleApp());
    final page = tester.state<OfficeEditorExamplePageState>(
      find.byType(OfficeEditorExamplePage),
    );
    await _until(
      tester,
      () =>
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('sample-letter.docx')),
              )
              .onPressed !=
          null,
      'detection',
    );

    // -------------------------------------------------------------- text
    var c = await _open(tester, page, 'letter.docx');
    expect(c.dialogMode, TomOfficeDialogMode.window, reason: 'the start');
    for (final (control, title) in [
      ('characterDialog', 'Character'),
      ('paragraphDialog', 'Paragraph'),
      ('find', 'Find and Replace'),
    ]) {
      await _tap(tester, 'ribbon-$control');
      final w = await _dialog(tester, c, title);
      if (title == 'Find and Replace') {
        // Text typed into its search field.
        final painted = w.image;
        for (final k in [LogicalKeyboardKey.keyM, LogicalKeyboardKey.keyO]) {
          await tester.sendKeyEvent(k);
        }
        await _until(
          tester,
          () => !identical(w.image, painted),
          'the typed text painted',
          seconds: 10,
        );
        // Its combo box's arrow: does LibreOffice open a child window,
        // and where (`position`)?
        final o = tester.getTopLeft(
          find.byKey(ValueKey('office-window-pixels-${w.id}')),
        );
        final ids = c.windows.map((x) => x.id).toSet();
        await tester.tapAt(o + const Offset(558, 26));
        await _wait(tester, 1500);
        for (final child in c.windows.where((x) => !ids.contains(x.id))) {
          _step(
            'child window ${child.id} ${child.kind} ${child.width}x'
            '${child.height} parent ${child.parentId} at ${child.x},'
            '${child.y}',
          );
          if (child.image != null) {
            await _shot(tester, 'child_${child.id}', child.image!);
          }
        }
        await _shot(tester, 'Find_and_Replace_typed', w.image!);
        if (c.windows.length > ids.length) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _wait(tester, 800);
        }
      }
      await _works(tester, w);
      await _close(tester, c, w);
    }
    await _tap(tester, 'ribbon-tab-Layout');
    await _tap(tester, 'ribbon-pageStyle');
    var w = await _dialog(tester, c, 'Page Style');
    await _works(tester, w);
    await _close(tester, c, w);
    // The switch: JSON is refused by the desktop build, windows stay.
    c.setDialogMode(TomOfficeDialogMode.json);
    await _until(
      tester,
      () => c.jsonDialogsAvailable == false,
      'the JSON refusal',
      seconds: 10,
    );
    expect(c.dialogMode, TomOfficeDialogMode.window);

    // ------------------------------------------------------------- sheet
    c = await _open(tester, page, 'sheet.xlsx');
    await _tap(tester, 'ribbon-formatCells');
    final cells = await _dialog(tester, c, 'Format Cells');
    // The way to the colour dialog: clicks on the dialog's pixels.
    final origin = tester.getTopLeft(
      find.byKey(ValueKey('office-window-pixels-${cells.id}')),
    );
    // The Background page, its Color button (a fresh profile shows None /
    // Color first), then Pick….
    for (final at in [
      const Offset(80, 219),
      const Offset(500, 30),
      const Offset(669, 278),
    ]) {
      await tester.tapAt(origin + at);
      await _wait(tester, 800);
      await _shot(
        tester,
        'cells_after_${at.dx.round()}_${at.dy.round()}',
        cells.image!,
      );
    }
    final picker = await _dialog(tester, c, 'Pick a Color');
    await _works(tester, picker);
    await _close(tester, c, picker);
    await _close(tester, c, cells);
    await _tap(tester, 'ribbon-tab-Insert');
    await _tap(tester, 'ribbon-chart');
    w = await _dialog(tester, c, 'Chart');
    await _works(tester, w);
    await _close(tester, c, w);

    // ------------------------------------------------------------ slides
    c = await _open(tester, page, 'deck.pptx');
    await _tap(tester, 'ribbon-tab-Insert');
    await _tap(tester, 'ribbon-table');
    w = await _dialog(tester, c, 'Insert Table');
    await _works(tester, w);
    await _close(tester, c, w);
    await page.controller?.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
