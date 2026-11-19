// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/testing.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'support.dart';

/// The spike's recorded WINDOW payloads (test/fixtures/spike_windows.json).
final Map<String, Object?> _fixture =
    (jsonDecode(File('test/fixtures/spike_windows.json').readAsStringSync())
            as Map)
        .cast<String, Object?>();

Map<String, Object?> _at(String path) {
  Object? node = _fixture;
  for (final key in path.split('.')) {
    node = (node! as Map)[key];
  }
  return (node! as Map).cast<String, Object?>();
}

/// A recorded `created` payload as the helper sends it (`windowOpened`).
OfficeWindowOpened _opened(Map<String, Object?> json) {
  final size = '${json['size']}'.split(',').map((s) => int.parse(s.trim()));
  return OfficeWindowOpened(
    windowId: int.parse('${json['id']}'),
    kind: '${json['type']}',
    title: '${json['title']}',
    width: size.first,
    height: size.last,
  );
}

/// A logged action `<id>:<action>` as the helper sends it.
OfficeHelperEvent _action(String entry, Map<int, OfficeWindowOpened> created) {
  final [id, action] = entry.split(':');
  final windowId = int.parse(id);
  if (action == 'created') return created[windowId]!;
  return OfficeWindowChanged(
    windowId: windowId,
    action: action,
    width: action == 'size_changed' ? created[windowId]!.width : null,
    height: action == 'size_changed' ? created[windowId]!.height : null,
    rectangle: action == 'cursor_invalidate'
        ? const OfficeRect(100, 50, 1, 16)
        : null,
    visible: action == 'cursor_visible' ? true : null,
  );
}

TestHost _host({bool jsonDialogs = false}) => TestHost(
  filePath: '/docs/sheet.xlsx',
  helper: FakeOfficeHelperLauncher(
    channelFor: () => FakeOfficeHelperChannel(
      jsonDialogs: jsonDialogs,
      opened: const OfficeOpened(
        docType: OfficeDocType.spreadsheet,
        parts: 1,
        partNames: ['Sheet1'],
        currentPart: 0,
        width: 27411,
        height: 14535,
        tileMode: OfficePixelFormat.bgra,
      ),
    ),
  ),
);

Future<void> _bigView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  await tester.pump();
}

void main() {
  testWidgets('DLG-1: a dialog opens as an overlay of its size, painted', (
    tester,
  ) async {
    final host = _host();
    final c = await openEditor(tester, host);
    await _bigView(tester);
    final channel = host.helper.last;
    channel.emit(_opened(_at('findReplace.created')));
    await settle(tester);
    final paint = channel.sentOf<OfficePaintWindow>().single;
    expect((paint.windowId, paint.w, paint.h), (1, 584, 241));
    expect(find.byKey(const ValueKey('office-window-1')), findsOneWidget);
    expect(find.text('Find and Replace'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('office-window-pixels-1'))),
      const Size(584, 241),
    );
    expect(c.windows.single.image, isNotNull, reason: 'painted');
    expect(find.byKey(const ValueKey('office-dialog-barrier')), findsOneWidget);
    // The document waits behind the dialog.
    expect(c.windows.single.isDialog, isTrue);
    await closeEditor(tester, c);
  });

  testWidgets('DLG-2: Format Cells as the spike recorded it: input goes back, '
      'invalidations repaint, the colour dialog opens over it, close ends '
      'both', (tester) async {
    final host = _host();
    final c = await openEditor(tester, host);
    await _bigView(tester);
    final channel = host.helper.last;
    final created = {
      2: _opened(_at('formatCells.created')),
      3: _opened(_at('formatCells.colourPicker')),
    };
    channel.emit(created[2]!);
    await settle(tester);
    final pixels = find.byKey(const ValueKey('office-window-pixels-2'));
    final origin = tester.getTopLeft(pixels);
    final steps = (_fixture['formatCells']! as Map)['steps'] as List;
    for (final step in steps.cast<Map<String, Object?>>()) {
      final input = '${step['input']}';
      final before = channel.sentOf<OfficePaintWindow>().length;
      if (input.startsWith('click:')) {
        final [x, y] = input.substring(6).split(',').map(double.parse).toList();
        await tester.tapAt(origin + Offset(x, y));
        await tester.pump();
        final mouse = channel.sentOf<OfficeWindowMouse>();
        expect(
          mouse.reversed.take(2).map((m) => (m.windowId, m.type, m.x, m.y)),
          [
            (2, OfficeMouseEventType.up, x.round(), y.round()),
            (2, OfficeMouseEventType.down, x.round(), y.round()),
          ],
        );
      } else if (input.startsWith('text:')) {
        // Typed into the dialog: its characters go back as text.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();
        final typed = channel.sentOf<OfficeWindowKey>().last;
        expect((typed.windowId, typed.charCode), (2, 'a'.codeUnitAt(0)));
      }
      for (final entry in (step['actions']! as List).cast<String>()) {
        channel.emit(_action(entry, created));
      }
      await settle(tester);
      expect(
        channel.sentOf<OfficePaintWindow>().length,
        greaterThan(before),
        reason: 'repainted after $input',
      );
    }
    // The colour dialog is over Format Cells, with the keyboard.
    expect(find.text('Pick a Color'), findsOneWidget);
    expect(c.windows.map((w) => w.id), [2, 3]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final key = channel.sentOf<OfficeWindowKey>().last;
    expect((key.windowId, key.keyCode), (3, VclKey.tab));
    // Closing as recorded ends both.
    for (final entry
        in ((_fixture['formatCells']! as Map)['close']! as List)
            .cast<String>()) {
      channel.emit(_action(entry, created));
    }
    await settle(tester);
    expect(c.windows, isEmpty);
    expect(find.byKey(const ValueKey('office-dialog-barrier')), findsNothing);
    await closeEditor(tester, c);
  });

  testWidgets('DLG-3: the title bar closes a dialog; a child window sits at '
      'its position in its parent', (tester) async {
    final host = _host();
    final c = await openEditor(tester, host);
    await _bigView(tester);
    final channel = host.helper.last;
    channel
      ..emit(_opened(_at('formatCells.created')))
      ..emit(
        const OfficeWindowOpened(
          windowId: 9,
          kind: 'child',
          title: '',
          width: 150,
          height: 120,
          parentId: 2,
          x: 300,
          y: 80,
        ),
      );
    await settle(tester);
    final parent = tester.getTopLeft(
      find.byKey(const ValueKey('office-window-pixels-2')),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('office-window-pixels-9'))),
      parent + const Offset(300, 80),
    );
    await tester.tap(find.byKey(const ValueKey('office-window-close-2')));
    await settle(tester);
    expect(channel.sentOf<OfficeWindowClose>().single.windowId, 2);
    expect(find.byKey(const ValueKey('office-window-2')), findsNothing);
    await closeEditor(tester, c);
  });

  testWidgets('DLG-4: the switch sends dialogMode; a desktop LibreOffice '
      'refuses JSON and the tab stays with windows', (tester) async {
    final host = _host();
    final c = await openEditor(tester, host);
    expect(c.dialogMode, TomOfficeDialogMode.window, reason: 'starts so');
    await tester.tap(find.byKey(const ValueKey('office-dialog-mode')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('office-dialog-mode-json')));
    await settle(tester);
    final channel = host.helper.last;
    expect(
      channel.sentOf<OfficeDialogModeMessage>().single.mode,
      OfficeDialogMode.json,
    );
    expect(c.dialogMode, TomOfficeDialogMode.window);
    expect(c.jsonDialogsAvailable, isFalse);
    expect(host.notices.last.$2, contains('only as windows'));
    // The menu now offers JSON no more.
    await tester.tap(find.byKey(const ValueKey('office-dialog-mode')));
    await settle(tester);
    expect(
      tester
          .widget<CheckedPopupMenuItem<TomOfficeDialogMode>>(
            find.byKey(const ValueKey('office-dialog-mode-json')),
          )
          .enabled,
      isFalse,
    );
    await tester.tapAt(Offset.zero);
    await settle(tester);
    await closeEditor(tester, c);
  });

  testWidgets('DLG-5: in JSON mode a dialog that comes as a window is shown '
      'as one; the mode is per tab', (tester) async {
    final host = _host(jsonDialogs: true);
    final c = await openEditor(tester, host);
    await _bigView(tester);
    c.setDialogMode(TomOfficeDialogMode.json);
    await settle(tester);
    expect(c.dialogMode, TomOfficeDialogMode.json);
    final channel = host.helper.last;
    channel.emit(_opened(_at('findReplace.created')));
    await settle(tester);
    expect(find.byKey(const ValueKey('office-window-1')), findsOneWidget);
    // A JSDIALOG is counted, not shown (no form builder: spike item 8).
    channel.emit(const OfficeJsDialog(json: '{"jsontype":"dialog"}'));
    await settle(tester);
    expect(c.jsDialogCount, 1);
    // Another tab keeps its own mode.
    final other = TomOfficeEditorController(host: _host());
    expect(other.dialogMode, TomOfficeDialogMode.window);
    other.dispose();
    await closeEditor(tester, c);
  });
}
