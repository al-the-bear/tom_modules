// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/testing.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'support.dart';

void main() {
  group('OFFICE-EDITOR opening', () {
    testWidgets('OE-OPEN-1: hello, open, opened; tiles drawn', (tester) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      expect(c.state, TomOfficeEditorState.open);
      final open = channel.sentOf<OfficeOpen>().single;
      expect(open.path, '/docs/report.docx');
      expect(open.filterOptions, isEmpty);
      expect(channel.sentOf<OfficeRenderTile>(), isNotEmpty);
      expect(c.tiles.length, greaterThan(0), reason: 'tiles cached');
      expect(find.byKey(const ValueKey('office-tiles')), findsOneWidget);
      // The first visible tile: (0, 0) at 100 % in twips.
      final first = channel.sentOf<OfficeRenderTile>().first;
      expect((first.x, first.y, first.w, first.pxW), (0, 0, 3840, 256));
      await closeEditor(tester, c);
    });

    testWidgets('OE-OPEN-2: detection not found: no helper, its state shown', (
      tester,
    ) async {
      var checks = 0;
      final host = TestHost(
        helper: FakeOfficeHelperLauncher(
          installation: const LibreOfficeInstallation(
            state: LibreOfficeState.tooOld,
            bundlePath: '/Applications/LibreOffice.app',
            version: '24.2.7.2',
          ),
        ),
      );
      final c = TomOfficeEditorController(host: host);
      await pumpEditor(tester, c, onCheckAgain: () => checks++);
      await c.open();
      await tester.pump();
      expect(c.state, TomOfficeEditorState.unavailable);
      expect(host.helper.channels, isEmpty);
      expect(
        find.text('LibreOffice 24.2.7.2 is older than 26.8.3.1.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('office-check-again')));
      expect(checks, 1);
      await tester.tap(find.text('Download LibreOffice'));
      expect(host.links, [kLibreOfficeDownloadUrl]);
      await closeEditor(tester, c);
    });

    testWidgets('OE-OPEN-3: a CSV file opens and saves with filter options', (
      tester,
    ) async {
      final host = TestHost(filePath: '/docs/data.csv', content: 'a,b\n1,2\n');
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      expect(
        channel.sentOf<OfficeOpen>().single.filterOptions,
        kCsvImportOptions,
      );
      await c.save();
      await settle(tester);
      final save = channel.sentOf<OfficeSave>().single;
      expect(save.format, isEmpty, reason: 'saved in its own format');
      expect(save.filterOptions, kCsvExportOptions);
      await closeEditor(tester, c);
    });
  });

  group('OFFICE-EDITOR input', () {
    testWidgets('OE-INPUT-1: keys, IME text and the mouse are forwarded', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      final view = find.byKey(const ValueKey('office-tiles'));
      // A click at (150, 30) px is (2250, 450) twips at 100 %.
      final topLeft = tester.getTopLeft(view);
      await tester.tapAt(topLeft + const Offset(150, 30));
      await tester.pump();
      final mice = channel.sentOf<OfficeMouse>();
      expect(mice.map((m) => m.type), [
        OfficeMouseEventType.down,
        OfficeMouseEventType.up,
      ]);
      expect((mice.first.x, mice.first.y, mice.first.buttons), (2250, 450, 1));
      // An arrow key goes out as VCL's KEY_LEFT, down and up.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      final keys = channel.sentOf<OfficeKey>();
      expect(keys.map((k) => (k.type, k.keyCode)), [
        (OfficeKeyEventType.down, VclKey.left),
        (OfficeKeyEventType.up, VclKey.left),
      ]);
      // Text from the platform's input method is committed as textInput.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'Hi'),
      );
      await tester.pump();
      final text = channel.sentOf<OfficeTextInput>();
      // As a composition and its end: LibreOffice inserts at the end.
      expect(text.map((t) => (t.type, t.text)), [
        (OfficeTextInputType.input, 'Hi'),
        (OfficeTextInputType.end, 'Hi'),
      ]);
      // Composing text is shown by LibreOffice as it is composed.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'é',
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      expect(
        channel.sentOf<OfficeTextInput>().last.type,
        OfficeTextInputType.input,
      );
      await closeEditor(tester, c);
    });

    testWidgets('OE-INPUT-2: own input repaints the visible tiles', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      final before = channel.sentOf<OfficeRenderTile>().length;
      c.typeText('x');
      // LibreOffice sends no INVALIDATE_TILES; the cursor callback marks
      // the visible tiles stale and they are asked for again.
      channel.callback('INVALIDATE_VISIBLE_CURSOR', '1500, 1500, 0, 276');
      await settle(tester);
      expect(channel.sentOf<OfficeRenderTile>().length, greaterThan(before));
      expect(c.cursor, const OfficeTwipRect(1500, 1500, 0, 276));
      // Without any callback the 100 ms timer does it.
      final again = channel.sentOf<OfficeRenderTile>().length;
      c.typeText('y');
      await tester.pump(const Duration(milliseconds: 150));
      expect(channel.sentOf<OfficeRenderTile>().length, greaterThan(again));
      await closeEditor(tester, c);
    });

    testWidgets('OE-TILE-2: repaint after repaint, the cache stays within '
        'its bound and every superseded tile is disposed', (tester) async {
      final host = TestHost();
      final made = <ui.Image>[];
      // Room for 40 tiles of 256 × 256 (the view shows about 20 with its
      // ring at 1000 × 800).
      const bound = 40 * 256 * 256 * 4;
      final c = TomOfficeEditorController(
        host: host,
        pingInterval: const Duration(seconds: 1),
        hangTimeout: const Duration(seconds: 3),
        cache: TileCache(maxBytes: bound),
        decoder: (pixels, w, h, format) async {
          final image = await decodeOfficeTile(pixels, w, h, format);
          made.add(image);
          return image;
        },
      );
      await pumpEditor(tester, c);
      await c.open();
      await settle(tester);
      final channel = host.helper.last;
      for (var i = 0; i < 30; i++) {
        // LibreOffice repaints everything (as typing in a long paragraph
        // makes it repaint the visible tiles again and again).
        channel.callback('INVALIDATE_TILES', 'EMPTY');
        await settle(tester);
      }
      expect(made.length, greaterThan(30 * 4), reason: 'tiles repainted');
      expect(c.tiles.bytes, lessThanOrEqualTo(bound));
      final cached = c.tiles.keys.map((k) => c.tiles.peek(k)!.image).toSet();
      final leaked = made.where((i) => !cached.contains(i) && !i.debugDisposed);
      expect(leaked, isEmpty, reason: 'superseded tiles are disposed');
      await closeEditor(tester, c);
      expect(made.every((i) => i.debugDisposed), isTrue);
    });

    testWidgets('OE-TILE-4: own input repaints the tile under the cursor '
        'first', (tester) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      final before = channel.sentOf<OfficeRenderTile>().length;
      c.typeText('x');
      // The cursor in the third tile row and second column (3840 twips a
      // tile at 100 %).
      channel.callback('INVALIDATE_VISIBLE_CURSOR', '4000, 8000, 0, 276');
      await tester.pump();
      final repaint = channel.sentOf<OfficeRenderTile>().skip(before).toList();
      expect(repaint.length, greaterThan(1), reason: 'the visible tiles');
      expect((repaint.first.x, repaint.first.y), (3840, 7680));
      await settle(tester);
      await closeEditor(tester, c);
    });

    testWidgets('OE-TILE-5: a stale tile is asked for once per '
        'invalidation; the view asking again keeps the pending request', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      final keys = c.tiles.keys.toSet();
      expect(keys, isNotEmpty);
      final zoom = keys.first.zoom;
      // From here the requests stay pending.
      channel.answerTiles = false;
      final before = channel.sentOf<OfficeRenderTile>().length;
      channel.callback('INVALIDATE_TILES', 'EMPTY');
      await tester.pump();
      final asked = channel.sentOf<OfficeRenderTile>().length;
      expect(asked, greaterThan(before), reason: 'the stale tiles asked for');
      // The view asks for all its tiles (the ring's too, not visible, so not
      // asked for by the invalidation), then again and again (rebuilds): the
      // pending requests were sent after the invalidation, so nothing more
      // is asked.
      c.showTiles(keys, zoom: zoom, devicePixelRatio: c.devicePixelRatio);
      await tester.pump();
      final all = channel.sentOf<OfficeRenderTile>().length;
      c.showTiles(keys, zoom: zoom, devicePixelRatio: c.devicePixelRatio);
      c.showTiles(keys, zoom: zoom, devicePixelRatio: c.devicePixelRatio);
      await tester.pump();
      expect(channel.sentOf<OfficeRenderTile>().length, all);
      // Invalidated again: the tiles are asked for again.
      channel.callback('INVALIDATE_TILES', 'EMPTY');
      await tester.pump();
      expect(channel.sentOf<OfficeRenderTile>().length, greaterThan(all));
      channel.answerTiles = true;
      await settle(tester);
      await closeEditor(tester, c);
    });

    testWidgets('OE-INPUT-3: the context menu runs its UNO command', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      final view = find.byKey(const ValueKey('office-tiles'));
      await tester.tapAt(
        tester.getCenter(view),
        buttons: kSecondaryMouseButton,
      );
      channel.callback(
        'CONTEXT_MENU',
        '{"menu": [{"text": "~Cut", "type": "command", "command": ".uno:Cut", '
            '"enabled": "true"}, {"type": "separator"}, {"text": "Paste '
            '~Special", "type": "command", "command": ".uno:PasteSpecial", '
            '"enabled": "false"}]}',
      );
      await settle(tester);
      expect(find.text('Cut'), findsOneWidget);
      await tester.tap(find.text('Cut'));
      await settle(tester);
      expect(channel.sentOf<OfficeUno>().last.command, '.uno:Cut');
      expect(channel.sentOf<OfficeMouse>().first.buttons, 4);
      await closeEditor(tester, c);
    });

    testWidgets('OE-INPUT-4: copy puts the selection on the clipboard', (
      tester,
    ) async {
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      final host = TestHost();
      final c = await openEditor(tester, host);
      final view = find.byKey(const ValueKey('office-tiles'));
      await tester.tapAt(tester.getCenter(view));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await settle(tester);
      expect(clipboard, ['copied']);
      expect(host.helper.last.sentOf<OfficeCopy>(), hasLength(1));
      await closeEditor(tester, c);
    });
  });

  group('OFFICE-EDITOR saving', () {
    testWidgets('OE-SAVE-1: save writes the temporary file and replaces', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      channel.callback('STATE_CHANGED', '.uno:ModifiedStatus=true');
      await tester.pump();
      expect(c.isDirty, isTrue);
      final outcome = await c.save();
      await settle(tester);
      expect(outcome, TomOfficeSaveOutcome.saved);
      final save = channel.sentOf<OfficeSave>().single;
      expect(save.targetPath, startsWith('/docs/.report.docx.tom-save-'));
      expect(await host.text(), 'saved by LibreOffice');
      expect(c.isDirty, isFalse);
      expect(host.fs.paths, ['/docs/report.docx'], reason: 'no temporary left');
      await closeEditor(tester, c);
    });

    testWidgets('OE-SAVE-2: a changed file is a conflict; keep mine replaces', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      await host.changeOnDisk('theirs');
      expect(await c.save(), TomOfficeSaveOutcome.conflict);
      await settle(tester);
      expect(await host.text(), 'theirs', reason: 'the original untouched');
      expect(find.byKey(const ValueKey('office-conflict')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('office-keep-mine')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('office-keep-mine-confirm')));
      await settle(tester);
      expect(await host.text(), 'saved by LibreOffice');
      expect(find.byKey(const ValueKey('office-conflict')), findsNothing);
      await closeEditor(tester, c);
    });

    testWidgets('OE-SAVE-3: take theirs reopens; save as copy keeps a copy', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      await host.changeOnDisk('theirs');
      await c.save();
      await settle(tester);
      final copy = await c.saveAsCopy();
      await settle(tester);
      expect(copy, '/docs/report (copy).docx');
      expect(
        await host.fs.readText(host.fs.uriOf(copy!)),
        'saved by LibreOffice',
      );
      await tester.tap(find.byKey(const ValueKey('office-take-theirs')));
      await settle(tester);
      expect(host.helper.channels, hasLength(2), reason: 'reopened');
      expect(c.state, TomOfficeEditorState.open);
      expect(c.conflict, isNull);
      await closeEditor(tester, c);
    });

    testWidgets('OE-SAVE-4: a failed save leaves the original', (tester) async {
      final host = TestHost(
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(onSave: (_) => false),
        ),
      );
      final c = await openEditor(tester, host);
      expect(await c.save(), TomOfficeSaveOutcome.failed);
      await settle(tester);
      expect(await host.text(), 'original');
      expect(host.notices.last.$1, 'error');
      await closeEditor(tester, c);
    });
  });

  group('OFFICE-EDITOR history and external changes', () {
    testWidgets('OE-HIST-1: dirty, undo and redo follow STATE_CHANGED', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      channel
        ..callback('STATE_CHANGED', '.uno:ModifiedStatus=true')
        ..callback('STATE_CHANGED', '.uno:Undo=enabled')
        ..callback('STATE_CHANGED', '.uno:Bold=true');
      await tester.pump();
      expect((c.isDirty, c.canUndo, c.canRedo), (true, true, false));
      expect(c.commandStates['.uno:Bold'], 'true');
      expect(host.historyChanges, 2);
      c.undo();
      expect(channel.sentOf<OfficeUno>().last.command, '.uno:Undo');
      channel.callback('STATE_CHANGED', '.uno:ModifiedStatus=false');
      await tester.pump();
      expect(c.isDirty, isFalse);
      await closeEditor(tester, c);
    });

    testWidgets('OE-EXT-1: a clean document reloads; a dirty one conflicts', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      await host.changeOnDisk('changed');
      await c.checkExternal();
      await settle(tester);
      expect(host.helper.channels, hasLength(2), reason: 'reopened');
      expect(host.notices.last.$2, contains('changed on disk'));
      host.helper.last.callback('STATE_CHANGED', '.uno:ModifiedStatus=true');
      await tester.pump();
      await host.changeOnDisk('changed again');
      await c.checkExternal();
      await settle(tester);
      expect(find.byKey(const ValueKey('office-conflict')), findsOneWidget);
      await closeEditor(tester, c);
    });

    testWidgets('OE-EXT-2: a deleted file is marked; saving recreates it', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      await host.fs.delete(host.fs.uriOf(host.filePath));
      await c.checkExternal();
      await settle(tester);
      expect(find.byKey(const ValueKey('office-deleted')), findsOneWidget);
      expect(await c.save(), TomOfficeSaveOutcome.saved);
      expect(await host.text(), 'saved by LibreOffice');
      await closeEditor(tester, c);
    });
  });

  group('OFFICE-EDITOR read-only and passwords', () {
    testWidgets('OE-RO-1: read-only drops edits, keeps navigation', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host, readOnly: true);
      final channel = host.helper.last;
      expect(channel.sentOf<OfficeOpen>().single.readOnly, isTrue);
      expect(find.byKey(const ValueKey('office-read-only')), findsOneWidget);
      c.typeText('x');
      c.key(VclKey.backspace);
      c.key(VclKey.down);
      expect(channel.sentOf<OfficeKey>().map((k) => k.keyCode), [
        VclKey.down,
        VclKey.down,
      ]);
      expect(await c.save(), TomOfficeSaveOutcome.refused);
      await closeEditor(tester, c);
    });

    testWidgets('OE-RO-2: a lock held by another LibreOffice is read-only', (
      tester,
    ) async {
      final host = TestHost(
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(
            opened: const OfficeOpened(
              docType: OfficeDocType.text,
              parts: 1,
              partNames: ['Page 1'],
              currentPart: 0,
              width: 12240,
              height: 15840,
              tileMode: OfficePixelFormat.bgra,
              readOnly: true,
              lockedBy: 'Alice',
            ),
          ),
        ),
      );
      final c = await openEditor(tester, host);
      expect(c.readOnlyReason, TomOfficeReadOnlyReason.locked);
      expect(find.text('Read-only: Alice has it open.'), findsOneWidget);
      await closeEditor(tester, c);
    });

    testWidgets('OE-PW-1: a wrong password asks again; the right one opens '
        'read-only (DPOE-3)', (tester) async {
      final host = TestHost(
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(password: 'secret'),
        ),
      );
      final c = await openEditor(tester, host);
      expect(c.state, TomOfficeEditorState.password);
      await tester.enterText(
        find.byKey(const ValueKey('office-password-field')),
        'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('office-password-ok')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('office-password-wrong')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('office-password-field')),
        'secret',
      );
      await tester.tap(find.byKey(const ValueKey('office-password-ok')));
      await settle(tester);
      expect(c.state, TomOfficeEditorState.open);
      expect(c.readOnlyReason, TomOfficeReadOnlyReason.passwordProtected);
      // Save as copy after the warning.
      await tester.tap(find.byKey(const ValueKey('office-save-copy')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('office-copy-confirm')));
      await settle(tester);
      expect(
        await host.fs.exists(host.fs.uriOf('/docs/report (copy).docx')),
        isTrue,
      );
      await closeEditor(tester, c);
    });

    testWidgets('OE-PW-2: cancelling a password fails the open; cancelling '
        'a password to modify opens read-only', (tester) async {
      final host = TestHost(
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(password: 'secret'),
        ),
      );
      final c = await openEditor(tester, host);
      await tester.tap(find.byKey(const ValueKey('office-password-cancel')));
      await settle(tester);
      expect(c.state, TomOfficeEditorState.failed);
      await closeEditor(tester, c);

      final host2 = TestHost(
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(
            password: 'secret',
            passwordToModify: true,
          ),
        ),
      );
      final c2 = await openEditor(tester, host2);
      expect(find.text('Open read-only'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('office-password-cancel')));
      await settle(tester);
      expect(c2.state, TomOfficeEditorState.open);
      expect(c2.readOnlyReason, TomOfficeReadOnlyReason.passwordToModify);
      await closeEditor(tester, c2);
    });
  });

  group('OFFICE-EDITOR helper stopping', () {
    testWidgets('OE-STOP-1: a crash shows the stopped view; history cleared', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      channel.callback('STATE_CHANGED', '.uno:ModifiedStatus=true');
      await tester.pump();
      final before = host.historyChanges;
      channel.crash();
      await settle(tester);
      expect(c.state, TomOfficeEditorState.stopped);
      expect((c.isDirty, c.canUndo, c.canRedo), (false, false, false));
      expect(host.historyChanges, greaterThan(before));
      expect(find.byKey(const ValueKey('office-stopped')), findsOneWidget);
      await tester.tap(find.text('Reopen'));
      await settle(tester);
      expect(c.state, TomOfficeEditorState.open);
      expect(host.helper.channels, hasLength(2));
      await closeEditor(tester, c);
    });

    testWidgets('OE-STOP-2: a hung helper is killed', (tester) async {
      final host = TestHost(
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(answerPings: false),
        ),
      );
      final c = await openEditor(tester, host);
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      expect(c.state, TomOfficeEditorState.stopped);
      expect(c.stopDescription, contains('hang'));
      await closeEditor(tester, c);
    });

    testWidgets('OE-STOP-3: a crash with a dialog open drops the dialog', (
      tester,
    ) async {
      final host = TestHost();
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      channel.emit(
        const OfficeWindowOpened(
          windowId: 7,
          kind: 'dialog',
          title: 'Format Cells',
          width: 400,
          height: 300,
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('office-window-7')), findsOneWidget);
      channel.crash();
      await settle(tester);
      expect(c.state, TomOfficeEditorState.stopped);
      expect(c.windows, isEmpty);
      expect(find.byKey(const ValueKey('office-window-7')), findsNothing);
      await closeEditor(tester, c);
    });
  });

  group('OFFICE-EDITOR parts', () {
    testWidgets('OE-PART-1: a spreadsheet shows its sheets and cell', (
      tester,
    ) async {
      final host = TestHost(
        filePath: '/docs/sheet.xlsx',
        helper: FakeOfficeHelperLauncher(
          channelFor: () => FakeOfficeHelperChannel(
            opened: const OfficeOpened(
              docType: OfficeDocType.spreadsheet,
              parts: 2,
              partNames: ['Basic', 'Advanced'],
              currentPart: 0,
              width: 27411,
              height: 14535,
              tileMode: OfficePixelFormat.bgra,
            ),
          ),
        ),
      );
      final c = await openEditor(tester, host);
      final channel = host.helper.last;
      channel
        ..callback('CELL_CURSOR', '0, 1425, 2547, 284, 0, 5')
        ..callback('CELL_ADDRESS', 'A6')
        ..callback('CELL_FORMULA', 'Brazilian coffee');
      await tester.pump();
      expect(find.text('Brazilian coffee'), findsOneWidget);
      expect(c.cellCursor?.row, 5);
      await tester.tap(find.text('Advanced'));
      await settle(tester);
      expect(channel.sentOf<OfficeSetPart>().single.part, 1);
      expect(channel.sentOf<OfficeRenderTile>().last.part, 1);
      await closeEditor(tester, c);
    });
  });
}
