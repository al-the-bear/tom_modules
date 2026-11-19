// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/testing.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'support.dart';

const _fonts =
    '{"commandName":".uno:CharFontName","commandValues":{'
    '"Liberation Sans":["10","12","14"],"Liberation Serif":["11","13"]}}';
const _styles =
    '{"commandName":".uno:StyleApply","commandValues":{'
    '"ParagraphStyles":["Standard","Heading 1","Heading 2"],'
    '"CharacterStyles":["Emphasis"]}}';

OfficeOpened _opened(OfficeDocType type, {int parts = 1}) => OfficeOpened(
  docType: type,
  parts: parts,
  partNames: [for (var i = 0; i < parts; i++) 'Part ${i + 1}'],
  currentPart: 0,
  width: 12240,
  height: 15840,
  tileMode: OfficePixelFormat.bgra,
);

TestHost _host(OfficeDocType type, {String path = '/docs/report.docx'}) =>
    TestHost(
      filePath: path,
      helper: FakeOfficeHelperLauncher(
        channelFor: () => FakeOfficeHelperChannel(
          opened: _opened(type),
          values: const {
            '.uno:CharFontName': _fonts,
            '.uno:StyleApply': _styles,
          },
        ),
      ),
    );

List<String> _tabs(WidgetTester tester) => [
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('ribbon-tab-'),
          )
          .evaluate())
    (e.widget.key! as ValueKey<String>).value.substring(11),
];

/// Scrolls the ribbon to [id]'s control and taps it.
Future<void> _tapRibbon(WidgetTester tester, String id) async {
  final finder = find.byKey(ValueKey(id));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

OfficeUno _lastUno(FakeOfficeHelperChannel c) => c.sentOf<OfficeUno>().last;

Map<String, Object?> _args(OfficeUno uno) =>
    (jsonDecode(uno.args) as Map).cast<String, Object?>();

void main() {
  testWidgets('RIB-1: the tabs per document type', (tester) async {
    for (final (type, path, tabs) in [
      (
        OfficeDocType.text,
        '/docs/report.docx',
        ['Home', 'Insert', 'Layout', 'Review', 'View'],
      ),
      (
        OfficeDocType.spreadsheet,
        '/docs/sheet.xlsx',
        ['Home', 'Insert', 'Layout', 'Data', 'Review', 'View'],
      ),
      (
        OfficeDocType.presentation,
        '/docs/deck.pptx',
        ['Home', 'Insert', 'Review', 'View'],
      ),
    ]) {
      final host = _host(type, path: path);
      final c = await openEditor(tester, host);
      expect(_tabs(tester), tabs, reason: '$type');
      await closeEditor(tester, c);
    }
  });

  testWidgets('RIB-2: failing commands are left out; a command is sent', (
    tester,
  ) async {
    final host = _host(OfficeDocType.presentation, path: '/docs/deck.pptx');
    final c = await openEditor(tester, host);
    // Impress's delete slide failed in the spike: not offered.
    expect(find.byKey(const ValueKey('ribbon-deleteSlide')), findsNothing);
    expect(find.byKey(const ValueKey('ribbon-formatPaintbrush')), findsNothing);
    await _tapRibbon(tester, 'ribbon-newSlide');
    await tester.pump();
    expect(_lastUno(host.helper.last).command, '.uno:InsertPage');
    await _tapRibbon(tester, 'ribbon-bold');
    await tester.pump();
    expect(_lastUno(host.helper.last).command, '.uno:Bold');
    await closeEditor(tester, c);
  });

  testWidgets('RIB-3: STATE_CHANGED checks, disables and names the font', (
    tester,
  ) async {
    final host = _host(OfficeDocType.text);
    final c = await openEditor(tester, host);
    host.helper.last
      ..callback('STATE_CHANGED', '.uno:Bold=true')
      ..callback('STATE_CHANGED', '.uno:Italic=disabled')
      ..callback('STATE_CHANGED', '.uno:CharFontName=Liberation Serif');
    await tester.pump();
    IconButton button(String id) =>
        tester.widget<IconButton>(find.byKey(ValueKey('ribbon-$id')));
    expect(button('bold').isSelected, isTrue);
    expect(button('underline').isSelected, isFalse);
    expect(button('italic').onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ribbon-fontName')),
        matching: find.text('Liberation Serif'),
      ),
      findsOneWidget,
    );
    await closeEditor(tester, c);
  });

  testWidgets('RIB-4: dropdowns are filled from getCommandValues', (
    tester,
  ) async {
    final host = _host(OfficeDocType.text);
    final c = await openEditor(tester, host);
    final channel = host.helper.last;
    await _tapRibbon(tester, 'ribbon-fontName');
    await settle(tester);
    expect(
      channel.sentOf<OfficeCommandValues>().first.command,
      '.uno:CharFontName',
    );
    await tester.tap(
      find.byKey(const ValueKey('ribbon-fontName-Liberation Serif')),
    );
    await settle(tester);
    var uno = _lastUno(channel);
    expect(uno.command, '.uno:CharFontName');
    expect(
      (_args(uno)['CharFontName.FamilyName']! as Map)['value'],
      'Liberation Serif',
    );
    // The sizes of the current font.
    channel.callback('STATE_CHANGED', '.uno:CharFontName=Liberation Serif');
    await tester.pump();
    await _tapRibbon(tester, 'ribbon-fontSize');
    await settle(tester);
    expect(find.byKey(const ValueKey('ribbon-fontSize-13')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ribbon-fontSize-13')));
    await settle(tester);
    uno = _lastUno(channel);
    expect(uno.command, '.uno:FontHeight');
    expect((_args(uno)['FontHeight.Height']! as Map)['value'], 13.0);
    // A paragraph style.
    await _tapRibbon(tester, 'ribbon-paragraphStyle');
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('ribbon-paragraphStyle-Heading 1')),
    );
    await settle(tester);
    uno = _lastUno(channel);
    expect(uno.command, '.uno:StyleApply');
    expect((_args(uno)['Style']! as Map)['value'], 'Heading 1');
    await closeEditor(tester, c);
  });

  testWidgets('RIB-5: the colour picker applies a colour, remembers it, '
      'and opens Custom colour', (tester) async {
    final host = _host(OfficeDocType.spreadsheet, path: '/docs/sheet.xlsx');
    final c = await openEditor(tester, host);
    final channel = host.helper.last;
    await _tapRibbon(tester, 'ribbon-fontColour-menu');
    await settle(tester);
    expect(find.byKey(const ValueKey('colour-automatic')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('colour-FF0000')));
    await settle(tester);
    var uno = _lastUno(channel);
    expect(uno.command, '.uno:Color');
    expect((_args(uno)['Color']! as Map)['value'], 0xFF0000);
    // The split button's main part applies the last colour again.
    await _tapRibbon(tester, 'ribbon-fontColour');
    await tester.pump();
    expect(
      channel.sentOf<OfficeUno>().where((u) => u.command == '.uno:Color'),
      hasLength(2),
    );
    // The recent colour shows; Custom colour opens Format Cells.
    await _tapRibbon(tester, 'ribbon-backgroundColour-menu');
    await settle(tester);
    expect(find.byKey(const ValueKey('recent-FF0000')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('colour-custom')));
    await settle(tester);
    expect(_lastUno(channel).command, '.uno:FormatCellDialog');
    // Automatic.
    await _tapRibbon(tester, 'ribbon-backgroundColour-menu');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('colour-automatic')));
    await settle(tester);
    uno = _lastUno(channel);
    expect(uno.command, '.uno:BackgroundColor');
    expect((_args(uno)['BackgroundColor']! as Map)['value'], -1);
    await closeEditor(tester, c);
  });

  testWidgets('RIB-6: Insert image takes the host\'s picker', (tester) async {
    final host = _host(OfficeDocType.text);
    final c = await openEditor(tester, host);
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-Insert')));
    await tester.pump();
    await _tapRibbon(tester, 'ribbon-image');
    await settle(tester);
    final uno = _lastUno(host.helper.last);
    expect(uno.command, '.uno:InsertGraphic');
    expect(
      (_args(uno)['FileName']! as Map)['value'],
      'file:///pictures/photo.png',
    );
    await closeEditor(tester, c);
  });

  testWidgets('RIB-7: Cmd+F opens Find & Replace; the dialog it opens is '
      'shown', (tester) async {
    final host = _host(OfficeDocType.text);
    final c = await openEditor(tester, host);
    final channel = host.helper.last;
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('office-tiles'))),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
    expect(_lastUno(channel).command, '.uno:SearchDialog');
    channel.emit(
      const OfficeWindowOpened(
        windowId: 3,
        kind: 'dialog',
        title: 'Find and Replace',
        width: 520,
        height: 310,
      ),
    );
    await settle(tester);
    // The dialog the command opened is shown as its window.
    expect(find.byKey(const ValueKey('office-window-3')), findsOneWidget);
    expect(c.lastWindow?.title, 'Find and Replace');
    await closeEditor(tester, c);
  });

  testWidgets('RIB-8: Tab and the arrow keys move along the controls', (
    tester,
  ) async {
    final host = _host(OfficeDocType.text);
    final c = await openEditor(tester, host);
    final bold = find.byKey(const ValueKey('ribbon-bold'));
    Focus.of(
      tester.element(find.descendant(of: bold, matching: find.byType(Icon))),
    ).requestFocus();
    await tester.pump();
    String? focused() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      String? id;
      ctx?.visitAncestorElements((e) {
        final key = e.widget.key;
        if (key is ValueKey<String> && key.value.startsWith('ribbon-')) {
          id = key.value;
          return false;
        }
        return true;
      });
      return id;
    }

    expect(focused(), 'ribbon-bold');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focused(), 'ribbon-italic');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(), 'ribbon-underline');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(), 'ribbon-italic');
    await closeEditor(tester, c);
  });

  testWidgets('RIB-9: a read-only document keeps only what does not edit', (
    tester,
  ) async {
    final host = _host(OfficeDocType.text);
    final c = await openEditor(tester, host, readOnly: true);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ribbon-bold')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ribbon-copy')))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('ribbon-find')));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ribbon-find')))
          .onPressed,
      isNotNull,
    );
    await _tapRibbon(tester, 'ribbon-find');
    await tester.pump();
    expect(_lastUno(host.helper.last).command, '.uno:SearchDialog');
    await closeEditor(tester, c);
  });
}
