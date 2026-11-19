// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The ribbon on mbp: each sample is formatted through the ribbon's controls
/// (text: style, font, size, bold, colour, alignment, list; sheet: bold,
/// background, currency, sort; slides: new slide, layout, text colour,
/// alignment), saved, and the saved file checked.
///
/// ```sh
/// cd tom_ai/modules/tom_office_editor/example
/// flutter test integration_test/ribbon_test.dart -d macos
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_editor_example/main.dart';

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what, {
  int seconds = 60,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('no $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _wait(WidgetTester tester, [int ms = 600]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _part(String path, String part) =>
    Process.runSync('unzip', ['-p', path, part]).stdout as String;

List<String> _parts(String path) =>
    (Process.runSync('unzip', ['-Z1', path]).stdout as String)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();

void _step(String what) => debugPrint('[RIBBON-IT] $what');

Future<void> _tap(WidgetTester tester, String key) async {
  _step('tap $key');
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _wait(tester, 400);
}

Future<void> _tab(WidgetTester tester, String label) =>
    _tap(tester, 'ribbon-tab-$label');

/// Opens [control]'s dropdown and chooses [value].
Future<void> _choose(WidgetTester tester, String control, String value) async {
  await _tap(tester, 'ribbon-$control');
  await _until(
    tester,
    () => find.byKey(ValueKey('ribbon-$control-$value')).evaluate().isNotEmpty,
    '$value in $control',
    seconds: 20,
  );
  // The menu's opening animation moves its entries: let it end.
  await _wait(tester, 500);
  await _tap(tester, 'ribbon-$control-$value');
}

/// Opens [control]'s colour picker and chooses [hex].
Future<void> _colour(WidgetTester tester, String control, String hex) async {
  await _tap(tester, 'ribbon-$control-menu');
  await _tap(tester, 'colour-$hex');
}

Future<void> _save(WidgetTester tester, TomOfficeEditorController c) async {
  _step('save');
  await _until(tester, () => c.isDirty, 'dirty', seconds: 30);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  await _until(
    tester,
    () => !c.isDirty && c.state == TomOfficeEditorState.open,
    'saved',
    seconds: 60,
  );
}

Future<TomOfficeEditorController> _open(
  WidgetTester tester,
  OfficeEditorExamplePageState page,
  String sample,
) async {
  await tester.tap(find.byKey(ValueKey('sample-$sample')));
  await _until(
    tester,
    () => page.controller?.state == TomOfficeEditorState.open,
    '$sample open',
  );
  final c = page.controller!;
  await _until(tester, () => c.tiles.length >= 4, '$sample tiles');
  // Focus the document.
  final view = find.byType(TomOfficeDocumentView);
  await tester.tapAt(tester.getTopLeft(view) + const Offset(40, 40));
  await _wait(tester, 300);
  c.key(VclKey.escape);
  return c;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OE-RIBBON-APP: each sample formatted through the ribbon and '
      'saved', (tester) async {
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

    // ---------------------------------------------------------- text
    var c = await _open(tester, page, 'letter.docx');
    await _wait(tester);
    c.key(VclKey.home | VclKey.mod1); // the start of the text
    await _wait(tester);
    c.key(VclKey.end | VclKey.shift); // its first line selected
    await _until(
      tester,
      () => c.selection.isNotEmpty,
      'a selection',
      seconds: 10,
    );
    // Characters first: applying a paragraph style clears LibreOffice's
    // text selection (the later character commands would reach no text).
    _step('selection ${c.selection}');
    await _choose(tester, 'fontName', 'Liberation Serif');
    _step(
      'after font: selection ${c.selection} font ${c.stateOf('.uno:CharFontName')}',
    );
    await _choose(tester, 'fontSize', '16');
    _step(
      'after size: selection ${c.selection} size ${c.stateOf('.uno:FontHeight')}',
    );
    final boldBefore = c.isChecked('.uno:Bold');
    await _tap(tester, 'ribbon-bold');
    await _colour(tester, 'fontColour', 'FF0000');
    await _until(
      tester,
      () => c.isChecked('.uno:Bold') != boldBefore,
      'bold state (${c.commandStates['.uno:Bold']})',
      seconds: 20,
    );
    await _tap(tester, 'ribbon-alignCentre');
    await _tap(tester, 'ribbon-bullets');
    await _choose(tester, 'paragraphStyle', 'Heading 2');
    // The style's STATE_CHANGED lags behind; the saved file decides.
    await _wait(tester, 2000);
    await _save(tester, c);
    final docx = page.filePath!;
    final body = _part(docx, 'word/document.xml');
    expect(body, contains('w:pStyle w:val="Heading2"'), reason: 'style');
    expect(body, contains('Liberation Serif'), reason: 'font');
    expect(body, contains('w:sz w:val="32"'), reason: '16 pt');
    expect(
      body,
      contains(boldBefore ? '<w:b w:val="false"/>' : '<w:b/>'),
      reason: 'bold flipped',
    );
    expect(body, contains('w:color w:val="FF0000"'), reason: 'colour');
    expect(body, contains('w:jc w:val="center"'), reason: 'centred');
    expect(body, contains('<w:numPr>'), reason: 'list');

    // ---------------------------------------------------------- sheet
    c = await _open(tester, page, 'sheet.xlsx');
    // Three values in F1:F3, then the range sorted.
    c.uno('.uno:GoToCell', '{"ToPoint":{"type":"string","value":"F1"}}');
    await _wait(tester);
    for (final v in ['cherry', 'apple', 'banana']) {
      c.typeText(v);
      c.key(VclKey.enter);
      await _wait(tester, 300);
    }
    c.uno('.uno:GoToCell', '{"ToPoint":{"type":"string","value":"F1:F3"}}');
    await _wait(tester);
    await _tab(tester, 'Data');
    await _tap(tester, 'ribbon-sortAscending');
    await _tab(tester, 'Home');
    await _tap(tester, 'ribbon-bold');
    await _colour(tester, 'backgroundColour', 'FFFF00');
    c.uno('.uno:GoToCell', '{"ToPoint":{"type":"string","value":"G1"}}');
    await _wait(tester);
    c.typeText('1234.5');
    c.key(VclKey.enter);
    await _wait(tester, 300);
    c.uno('.uno:GoToCell', '{"ToPoint":{"type":"string","value":"G1"}}');
    await _wait(tester);
    await _tap(tester, 'ribbon-numberCurrency');
    await _save(tester, c);
    final xlsx = page.filePath!;
    final shared =
        RegExp(r'<si>(?:<t[^>]*>([^<]*)</t>|.*?<t[^>]*>([^<]*)</t>.*?)</si>')
            .allMatches(_part(xlsx, 'xl/sharedStrings.xml'))
            .map((m) => m.group(1) ?? m.group(2) ?? '')
            .toList();
    final sheet = _part(xlsx, 'xl/worksheets/sheet1.xml');
    String cell(String ref) {
      final m = RegExp(
        '<c r="$ref"[^>]*t="s"[^>]*>\\s*<v>(\\d+)</v>',
      ).firstMatch(sheet);
      return m == null ? '' : shared[int.parse(m.group(1)!)];
    }

    expect(
      [cell('F1'), cell('F2'), cell('F3')],
      ['apple', 'banana', 'cherry'],
      reason: 'sorted ascending',
    );
    final styles = _part(xlsx, 'xl/styles.xml');
    expect(styles, contains('FFFFFF00'), reason: 'yellow background');
    expect(styles, contains('<b'), reason: 'bold');
    expect(
      styles,
      matches(RegExp(r'formatCode="[^"]*(€|\$|\[\$)')),
      reason: 'a currency format',
    );

    // ---------------------------------------------------------- slides
    c = await _open(tester, page, 'deck.pptx');
    final slidesBefore = _parts(
      page.filePath!,
    ).where((p) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(p)).length;
    // Text of the first slide: colour and centring in its edit mode.
    c.key(VclKey.tab);
    c.key(VclKey.enter);
    await _wait(tester);
    c.uno('.uno:SelectAll');
    await _wait(tester);
    await _colour(tester, 'fontColour', 'FF0000');
    await _tap(tester, 'ribbon-alignCentre');
    c.key(VclKey.escape);
    c.key(VclKey.escape);
    await _wait(tester);
    // A new slide with the Title only layout.
    await _tap(tester, 'ribbon-newSlide');
    await _until(
      tester,
      () => c.parts == slidesBefore + 1 || c.currentPart > 0,
      'new slide',
      seconds: 20,
    );
    await _choose(tester, 'slideLayout', '19');
    await _wait(tester, 1000);
    await _save(tester, c);
    final pptx = page.filePath!;
    final slides = _parts(
      pptx,
    ).where((p) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(p)).toList();
    expect(slides.length, slidesBefore + 1, reason: 'a slide added');
    final layouts = [
      for (final s in slides)
        _part(
          pptx,
          s
              .replaceFirst('slides/', 'slides/_rels/')
              .replaceFirst('.xml', '.xml.rels'),
        ),
    ];
    final titleOnly = _parts(pptx)
        .where((p) => p.startsWith('ppt/slideLayouts/slideLayout'))
        .where((p) => _part(pptx, p).contains('type="titleOnly"'))
        .map((p) => p.split('/').last)
        .toSet();
    expect(
      layouts.any((rels) => titleOnly.any(rels.contains)),
      isTrue,
      reason: 'a slide with the Title only layout',
    );
    final first = _part(pptx, 'ppt/slides/slide1.xml');
    expect(first, contains('srgbClr val="FF0000"'), reason: 'red text');
    expect(first, contains('algn="ctr"'), reason: 'centred');
    await page.controller?.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
