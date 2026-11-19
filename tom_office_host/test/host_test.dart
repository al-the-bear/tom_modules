// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The frame loop and message dispatch, against a fake LibreOfficeKit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_office_host/tom_office_host.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'fake_lok.dart';

const _codec = OfficeProtocolCodec();

/// A host over the fake, with its input, its decoded output and its log.
class Harness {
  Harness({String? lockedBy, Duration editStateWait = Duration.zero}) {
    host = OfficeHost(
      runtime: runtime,
      program: '/fake/Frameworks',
      profileUrl: profileDir.uri.toString(),
      output: (frame) {
        for (final m in reader.add(frame)) {
          received.add(m);
          _arrived.add(m);
        }
      },
      log: logLines.add,
      pid: 77,
      editStateWait: editStateWait,
      lockOwnerOf: (_) => lockedBy,
    );
  }

  final runtime = FakeRuntime();
  final input = StreamController<List<int>>();
  final reader = OfficeFrameReader(_codec);
  final received = <OfficeMessage>[];
  final _arrived = StreamController<OfficeMessage>.broadcast(sync: true);
  final logLines = <String>[];
  final profile = Directory('.dart_tool/test_scratch/host_test').absolute
    ..createSync(recursive: true);
  late final Directory profileDir = profile.createTempSync('profile-');
  late final OfficeHost host;
  late final Future<int> exit = host.serve(input.stream);

  FakeDocument get doc => runtime.office!.document!;

  void send(OfficeHelperCommand m) => input.add(_codec.encode(m));

  /// The first message received (from now or already) that is a [T] and
  /// passes [test].
  Future<T> next<T extends OfficeMessage>([bool Function(T m)? test]) {
    bool ok(OfficeMessage m) => m is T && (test == null || test(m));
    final seen = received.where(ok);
    if (seen.isNotEmpty) {
      final m = seen.first as T;
      received.remove(m);
      return Future.value(m);
    }
    return _arrived.stream
        .firstWhere(ok)
        .then((m) {
          received.remove(m);
          return m as T;
        })
        .timeout(const Duration(seconds: 5));
  }

  Future<OfficeOpened> open([String path = '/docs/report.xlsx']) async {
    unawaited(exit);
    await next<OfficeHello>();
    send(OfficeOpen(path: path, language: 'en-US'));
    return next<OfficeOpened>();
  }
}

void main() {
  late Harness h;

  tearDownAll(() {
    final scratch = Directory('.dart_tool/test_scratch/host_test');
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  setUp(() => h = Harness());
  tearDown(() async {
    if (!h.host.isDone) h.send(const OfficeClose());
    unawaited(h.input.close());
    await h.exit;
    if (h.profileDir.existsSync()) h.profileDir.deleteSync(recursive: true);
  });

  group('HOST-START start and hello', () {
    test(
      'HOST-START-1: init with program and profile, features, then hello',
      () async {
        unawaited(h.exit);
        final hello = await h.next<OfficeHello>();
        expect(hello.protocol, kOfficeProtocolVersion);
        expect(hello.helperVersion, kOfficeHostVersion);
        expect(hello.pid, 77);
        expect(hello.lokVersion, contains('Fake'));
        expect(
          h.runtime.calls.single,
          startsWith('init /fake/Frameworks file://'),
        );
        expect(h.runtime.office!.features, kLokFeatures);
      },
    );

    test(
      'HOST-START-2: LibreOfficeKit not loading is an error and exit 3',
      () async {
        h.runtime.initFails = true;
        expect(await h.exit, 3);
        expect((await h.next<OfficeError>()).code, 'initFailed');
      },
    );

    test('HOST-VERSION-1: the version is the pubspec\'s', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('\nversion: $kOfficeHostVersion\n'));
    });
  });

  group('HOST-OPEN opening', () {
    test('HOST-OPEN-1: open reports type, parts, size and tile mode', () async {
      final opened = await h.open();
      expect(opened.docType, OfficeDocType.spreadsheet);
      expect(opened.parts, 2);
      expect(opened.partNames, ['Sheet1', 'Daten']);
      expect(opened.width, 12000);
      expect(opened.height, 30000);
      expect(opened.tileMode, OfficePixelFormat.bgra);
      expect(opened.readOnly, isFalse);
      expect(
        h.runtime.office!.loads.single,
        '/docs/report.xlsx Language=en-US',
      );
      expect(h.doc.calls, contains('initializeForRendering'));
    });

    test('HOST-OPEN-6: filter options come first, with Batch', () {
      expect(
        loadOptions(const OfficeOpen(path: '/d/a.docx', language: 'de-DE')),
        'Language=de-DE',
      );
      expect(
        loadOptions(
          const OfficeOpen(
            path: '/d/a.csv',
            language: 'en-US',
            filterOptions: '59,34,76,1',
          ),
        ),
        'Batch=true,59,34,76,1,Language=en-US',
      );
    });

    test('HOST-OPEN-2: a load error is an error message', () async {
      unawaited(h.exit);
      await h.next<OfficeHello>();
      h.runtime.office!.loadError = 'General input/output error';
      h.send(const OfficeOpen(path: '/x.docx', language: 'en-US'));
      final e = await h.next<OfficeError>();
      expect(e.code, 'loadFailed');
      expect(e.message, 'General input/output error');
    });

    test('HOST-OPEN-3: a second open is refused', () async {
      await h.open();
      h.send(const OfficeOpen(path: '/y.docx', language: 'en-US'));
      expect((await h.next<OfficeError>()).code, 'alreadyOpen');
    });

    test(
      'HOST-OPEN-4: requests before open are errors with their id',
      () async {
        unawaited(h.exit);
        await h.next<OfficeHello>();
        h.send(
          const OfficeRenderTile(
            id: 5,
            part: 0,
            x: 0,
            y: 0,
            w: 1,
            h: 1,
            pxW: 1,
            pxH: 1,
          ),
        );
        final e = await h.next<OfficeError>();
        expect((e.id, e.code), (5, 'notOpen'));
      },
    );

    test('HOST-OPEN-5: a lock file or EditDoc=false opens read-only', () async {
      h = Harness(lockedBy: 'Ann Other');
      final opened = await h.open();
      expect(opened.readOnly, isTrue);
      expect(opened.lockedBy, 'Ann Other');

      // LibreOffice reporting .uno:EditDoc=false after the load.
      final h2 = Harness(editStateWait: const Duration(milliseconds: 20));
      unawaited(h2.exit);
      await h2.next<OfficeHello>();
      h2.runtime.office!.forceReadOnly = true;
      h2.send(const OfficeOpen(path: '/r.docx', language: 'en-US'));
      final o2 = await h2.next<OfficeOpened>();
      expect((o2.readOnly, o2.lockedBy), (true, null));
      h2.send(const OfficeClose());
      await h2.exit;

      // Asked for in open.
      final h3 = Harness();
      unawaited(h3.exit);
      await h3.next<OfficeHello>();
      h3.send(
        const OfficeOpen(path: '/r.docx', language: 'en-US', readOnly: true),
      );
      expect((await h3.next<OfficeOpened>()).readOnly, isTrue);
      h3.send(const OfficeClose());
      await h3.exit;
    });
  });

  group('HOST-PASSWORD passwords', () {
    test('HOST-PASSWORD-1: asked, wrong, right; never logged', () async {
      h.runtime.openPassword = 'sesame';
      unawaited(h.exit);
      await h.next<OfficeHello>();
      h.send(const OfficeOpen(path: '/p.docx', language: 'en-US'));
      expect((await h.next<OfficePasswordNeeded>()).toModify, isFalse);
      h.send(const OfficePassword(password: 'wrong-one'));
      expect((await h.next<OfficePasswordNeeded>()).toModify, isFalse);
      h.send(const OfficePassword(password: 'sesame'));
      final opened = await h.next<OfficeOpened>();
      expect(opened.readOnly, isFalse);
      expect(h.runtime.office!.armed, [null, 'wrong-one', 'sesame']);
      final log = h.logLines.join('\n');
      expect(log, isNot(contains('sesame')));
      expect(log, isNot(contains('wrong-one')));
      expect(log, contains('password <redacted>'));
    });

    test('HOST-PASSWORD-2: cancel ends the open', () async {
      h.runtime.openPassword = 'sesame';
      unawaited(h.exit);
      await h.next<OfficeHello>();
      h.send(const OfficeOpen(path: '/p.docx', language: 'en-US'));
      await h.next<OfficePasswordNeeded>();
      h.send(const OfficePassword(password: null));
      expect((await h.next<OfficeError>()).code, 'passwordCancelled');
      expect(h.host.hasDocument, isFalse);
    });

    test('HOST-PASSWORD-3: to modify: cancel opens read-only, the password '
        'opens editable', () async {
      h.runtime.modifyPassword = 'edit';
      unawaited(h.exit);
      await h.next<OfficeHello>();
      h.send(const OfficeOpen(path: '/m.docx', language: 'en-US'));
      expect((await h.next<OfficePasswordNeeded>()).toModify, isTrue);
      h.send(const OfficePassword(password: 'nope'));
      expect((await h.next<OfficePasswordNeeded>()).toModify, isTrue);
      h.send(const OfficePassword(password: 'edit'));
      expect((await h.next<OfficeOpened>()).readOnly, isFalse);

      final h2 = Harness();
      h2.runtime.modifyPassword = 'edit';
      unawaited(h2.exit);
      await h2.next<OfficeHello>();
      h2.send(const OfficeOpen(path: '/m.docx', language: 'en-US'));
      await h2.next<OfficePasswordNeeded>();
      h2.send(const OfficePassword(password: null));
      expect((await h2.next<OfficeOpened>()).readOnly, isTrue);
      h2.send(const OfficeClose());
      await h2.exit;
    });

    test('HOST-PASSWORD-4: a document opened with a password saves with '
        '.uno:SaveAs and its password', () async {
      h.runtime.openPassword = 'sesame';
      unawaited(h.exit);
      await h.next<OfficeHello>();
      h.send(const OfficeOpen(path: '/docs/p.docx', language: 'en-US'));
      await h.next<OfficePasswordNeeded>();
      h.send(const OfficePassword(password: 'sesame'));
      await h.next<OfficeOpened>();
      h.doc.onUno = (command, args) async {
        h.runtime.emit(
          LokCallbackType.unoCommandResult,
          '{"commandName":"$command","success":true}',
        );
      };
      h.send(const OfficeSave(id: 3, targetPath: '/docs/.p.docx.tom-save-1'));
      final saved = await h.next<OfficeSaved>();
      expect((saved.id, saved.ok), (3, true));
      final uno = h.doc.calls.singleWhere(
        (c) => c.startsWith('uno .uno:SaveAs'),
      );
      final args = jsonDecode(uno.substring('uno .uno:SaveAs '.length)) as Map;
      expect(args['FilterName']['value'], 'MS Word 2007 XML');
      expect(args['Password']['value'], 'sesame');
      expect(args['URL']['value'], 'file:///docs/.p.docx.tom-save-1');
      expect(h.doc.calls.where((c) => c.startsWith('saveAs')), isEmpty);
    });
  });

  group('HOST-TILE tiles', () {
    test(
      'HOST-TILE-1: renderTile answers with the tile and its pixels',
      () async {
        await h.open();
        h.send(
          const OfficeRenderTile(
            id: 9,
            part: 1,
            x: 3840,
            y: 0,
            w: 3840,
            h: 3840,
            pxW: 4,
            pxH: 2,
          ),
        );
        final tile = await h.next<OfficeTile>();
        expect((tile.id, tile.part, tile.pxW, tile.pxH), (9, 1, 4, 2));
        expect(tile.format, OfficePixelFormat.bgra);
        expect(tile.pixels.length, 32);
        expect(h.doc.calls, contains('paintTile 1 4 2 3840 0 3840 3840'));
      },
    );

    test('HOST-TILE-2: queued requests for the same area coalesce', () async {
      await h.open();
      final frames = [
        for (final id in [1, 2, 3])
          ..._codec.encode(
            OfficeRenderTile(
              id: id,
              part: 0,
              x: 0,
              y: 0,
              w: 3840,
              h: 3840,
              pxW: 2,
              pxH: 2,
            ),
          ),
        ..._codec.encode(
          const OfficeRenderTile(
            id: 4,
            part: 0,
            x: 3840,
            y: 0,
            w: 3840,
            h: 3840,
            pxW: 2,
            pxH: 2,
          ),
        ),
        ..._codec.encode(const OfficePing(id: 50)),
      ];
      h.input.add(frames);
      await h.next<OfficePong>();
      final ids = h.received.whereType<OfficeTile>().map((t) => t.id).toList();
      expect(ids, [3, 4]);
      expect(h.doc.calls.where((c) => c.startsWith('paintTile')).length, 2);
    });
  });

  group('HOST-INPUT input, commands, view', () {
    test(
      'HOST-INPUT-1: keys, text, mouse and selection reach LibreOffice',
      () async {
        await h.open();
        h.send(
          const OfficeKey(
            type: OfficeKeyEventType.down,
            charCode: 72,
            keyCode: 0,
          ),
        );
        h.send(
          const OfficeKey(
            type: OfficeKeyEventType.up,
            charCode: 72,
            keyCode: 0,
          ),
        );
        h.send(
          const OfficeTextInput(type: OfficeTextInputType.end, text: 'äb'),
        );
        h.send(
          const OfficeMouse(
            type: OfficeMouseEventType.down,
            x: 10,
            y: 20,
            count: 2,
          ),
        );
        h.send(
          const OfficeSelection(
            kind: OfficeSelectionKind.text,
            type: 1,
            x: 5,
            y: 6,
          ),
        );
        h.send(
          const OfficeSelection(
            kind: OfficeSelectionKind.graphic,
            type: 0,
            x: 7,
            y: 8,
          ),
        );
        h.send(const OfficeSelection(kind: OfficeSelectionKind.reset));
        h.send(const OfficePing(id: 1));
        await h.next<OfficePong>();
        expect(h.doc.calls.skipWhile((c) => c != 'key 0 72 0').take(7), [
          'key 0 72 0',
          'key 1 72 0',
          'extText 2 äb',
          'mouse 0 10 20 2 1 0',
          'textSelection 1 5 6',
          'graphicSelection 0 7 8',
          'resetSelection',
        ]);
      },
    );

    test(
      'HOST-INPUT-2: text without postWindowExtTextInputEvent is typed',
      () async {
        await h.open();
        h.doc.hasExtTextInput = false;
        h.send(
          const OfficeTextInput(type: OfficeTextInputType.end, text: 'ab'),
        );
        h.send(const OfficePing(id: 1));
        await h.next<OfficePong>();
        expect(h.doc.calls.where((c) => c.startsWith('key')), [
          'key 0 97 0',
          'key 1 97 0',
          'key 0 98 0',
          'key 1 98 0',
        ]);
      },
    );

    test('HOST-INPUT-3: a uno command that blocks (a modal dialog) leaves '
        'the loop free', () async {
      await h.open();
      final release = Completer<void>();
      h.doc.onUno = (command, args) => release.future;
      h.send(const OfficeUno(id: 4, command: '.uno:InsertTable', args: '{}'));
      h.send(const OfficePing(id: 2));
      expect((await h.next<OfficePong>()).id, 2);
      release.complete();
      expect(h.doc.calls, contains('uno .uno:InsertTable {}'));
    });

    test('HOST-INPUT-4: commandValues, view, setPart', () async {
      await h.open();
      h.send(const OfficeCommandValues(id: 6, command: '.uno:StyleApply'));
      final values = await h.next<OfficeValues>();
      expect(
        (values.id, values.json),
        (6, '{"commandName":".uno:StyleApply"}'),
      );
      h.send(
        const OfficeView(
          part: 1,
          visibleArea: OfficeRect(0, 0, 20000, 10000),
          zoom: 256 / 3840,
        ),
      );
      h.send(const OfficeSetPart(part: 0));
      h.send(const OfficePing(id: 1));
      await h.next<OfficePong>();
      expect(
        h.doc.calls,
        containsAllInOrder([
          'setPart 1',
          'setClientZoom 256 256 3840 3840',
          'setClientVisibleArea 0 0 20000 10000',
          'setPart 0',
        ]),
      );
    });

    test(
      'HOST-INPUT-5: copy answers per MIME type, paste reports failure',
      () async {
        await h.open();
        h.send(
          const OfficeCopy(
            id: 8,
            mimeTypes: ['text/plain;charset=utf-8', 'text/html'],
          ),
        );
        final clip = await h.next<OfficeClipboard>();
        expect(clip.data, {'text/plain;charset=utf-8': 'selected'});
        h.send(const OfficePaste(mimeType: 'text/html', data: '<b>x</b>'));
        h.send(const OfficePaste(mimeType: 'image/png', data: 'x'));
        expect((await h.next<OfficeError>()).code, 'pasteFailed');
        expect(h.doc.calls, contains('paste text/html <b>x</b>'));
      },
    );
  });

  group('HOST-CB callbacks', () {
    test('HOST-CB-1: callbacks are forwarded by name; password callbacks are '
        'not', () async {
      await h.open();
      h.runtime.emit(0, '0, 0, 100, 100');
      h.runtime.emit(LokCallbackType.stateChanged, '.uno:Bold=true');
      h.runtime.emit(LokCallbackType.documentPassword, 'file:///p.docx');
      h.send(const OfficePing(id: 1));
      await h.next<OfficePong>();
      final cbs = h.received.whereType<OfficeCallback>().toList();
      expect(cbs.map((c) => '${c.type} ${c.payload}'), [
        'INVALIDATE_TILES 0, 0, 100, 100',
        'STATE_CHANGED .uno:Bold=true',
      ]);
    });

    test(
      'HOST-CB-2: WINDOW callbacks become windowOpened / windowChanged',
      () async {
        await h.open();
        h.runtime.emit(
          LokCallbackType.window,
          '{"id":"5","action":"created","type":"dialog","size":"789, 489",'
          '"title":"Format Cells"}',
        );
        final w = await h.next<OfficeWindowOpened>();
        expect(
          (w.windowId, w.kind, w.width, w.height, w.title),
          (5, 'dialog', 789, 489, 'Format Cells'),
        );
        h.runtime.emit(
          LokCallbackType.window,
          '{"id":"5","action":"invalidate","rectangle":"1, 2, 30, 40"}',
        );
        final c = await h.next<OfficeWindowChanged>();
        expect(
          (c.action, c.rectangle),
          ('invalidate', const OfficeRect(1, 2, 30, 40)),
        );
        h.runtime.emit(LokCallbackType.window, '{"id":"5","action":"close"}');
        expect((await h.next<OfficeWindowChanged>()).rectangle, isNull);
        expect(h.received.whereType<OfficeCallback>(), isEmpty);
      },
    );

    test('HOST-CB-4: a child window\'s position, size, title and cursor '
        'visibility', () async {
      await h.open();
      h.runtime.emit(
        LokCallbackType.window,
        '{"id":"7","action":"created","type":"child","size":"120, 200",'
        '"parentId":"5","position":"300, 54"}',
      );
      final w = await h.next<OfficeWindowOpened>();
      expect((w.kind, w.parentId, w.x, w.y), ('child', 5, 300, 54));
      h.runtime.emit(
        LokCallbackType.window,
        '{"id":"5","action":"size_changed","size":"800, 500"}',
      );
      final size = await h.next<OfficeWindowChanged>();
      expect((size.width, size.height), (800, 500));
      h.runtime.emit(
        LokCallbackType.window,
        '{"id":"5","action":"title_changed","title":"Pick a Color"}',
      );
      expect((await h.next<OfficeWindowChanged>()).title, 'Pick a Color');
      h.runtime.emit(
        LokCallbackType.window,
        '{"id":"5","action":"cursor_visible","visible":"false"}',
      );
      expect((await h.next<OfficeWindowChanged>()).visible, isFalse);
    });

    test('HOST-CB-3: JSDIALOG is forwarded as jsDialog', () async {
      await h.open();
      h.runtime.emit(LokCallbackType.jsDialog, '{"jsontype":"dialog"}');
      expect((await h.next<OfficeJsDialog>()).json, '{"jsontype":"dialog"}');
    });
  });

  group('HOST-DIALOG dialog windows', () {
    test('HOST-DIALOG-1: paintWindow, window input and close', () async {
      await h.open();
      h.send(
        const OfficePaintWindow(
          id: 11,
          windowId: 5,
          x: 0,
          y: 0,
          w: 3,
          h: 2,
          dpiScale: 2,
        ),
      );
      final px = await h.next<OfficeWindowPixels>();
      expect((px.id, px.windowId, px.pixels.length), (11, 5, 24));
      h.send(
        const OfficeWindowMouse(
          windowId: 5,
          type: OfficeMouseEventType.up,
          x: 1,
          y: 2,
        ),
      );
      h.send(
        const OfficeWindowKey(
          windowId: 5,
          type: OfficeKeyEventType.down,
          charCode: 0,
          keyCode: 1282,
        ),
      );
      h.send(
        const OfficeWindowTextInput(
          windowId: 5,
          type: OfficeTextInputType.input,
          text: 'ab',
        ),
      );
      h.send(const OfficeWindowClose(windowId: 5));
      h.send(const OfficePing(id: 1));
      await h.next<OfficePong>();
      expect(
        h.doc.calls,
        containsAllInOrder([
          'paintWindow 5 0 0 3 2 2.0',
          'windowMouse 5 1 1 2 1 1 0',
          'windowKey 5 0 0 1282',
          'windowText 5 0 ab',
          'postWindow 5 0',
        ]),
      );
    });

    test(
      'HOST-DIALOG-2: JSON dialogs are unavailable; window mode is fine',
      () async {
        await h.open();
        h.send(const OfficeDialogModeMessage(mode: OfficeDialogMode.window));
        h.send(const OfficeDialogModeMessage(mode: OfficeDialogMode.json));
        expect((await h.next<OfficeError>()).code, 'jsonDialogsUnavailable');
        h.send(const OfficeDialogEvent(windowId: 5, json: '{}'));
        expect((await h.next<OfficeError>()).code, 'jsonDialogsUnavailable');
        expect(h.received.whereType<OfficeError>(), isEmpty);
      },
    );
  });

  group('HOST-SAVE saving', () {
    test('HOST-SAVE-1: to the target, in the file\'s own format, with '
        'TakeOwnership', () async {
      await h.open('/docs/report.xlsx');
      h.send(
        const OfficeSave(id: 1, targetPath: '/docs/.report.xlsx.tom-save-1'),
      );
      final saved = await h.next<OfficeSaved>();
      expect((saved.id, saved.ok), (1, true));
      expect(
        h.doc.calls,
        contains('saveAs /docs/.report.xlsx.tom-save-1 xlsx TakeOwnership'),
      );
    });

    test('HOST-SAVE-2: another format, filter options kept; a failure is '
        'reported', () async {
      await h.open('/docs/report.xlsx');
      h.doc.saveOk = false;
      h.send(
        const OfficeSave(
          id: 2,
          targetPath: '/docs/x.pdf',
          format: 'pdf',
          filterOptions: 'A=1',
        ),
      );
      final saved = await h.next<OfficeSaved>();
      expect(saved.ok, isFalse);
      expect(saved.error, isNotNull);
      // An export: no TakeOwnership (LibreOffice refuses it for a PDF).
      expect(h.doc.calls, contains('saveAs /docs/x.pdf pdf A=1'));
    });
  });

  group('HOST-END ending', () {
    test('HOST-END-1: close destroys, deletes the profile, sends closed, '
        'exit 0', () async {
      await h.open();
      final doc = h.doc;
      expect(h.profileDir.existsSync(), isTrue);
      h.send(const OfficeClose());
      expect(await h.exit, 0);
      expect(h.profileDir.existsSync(), isFalse);
      expect(await h.next<OfficeClosed>(), isA<OfficeClosed>());
      expect(doc.destroyed, isTrue);
      expect(h.runtime.office!.destroyed, isTrue);
    });

    test('HOST-END-2: the end of stdin ends the helper the same way', () async {
      await h.open();
      await h.input.close();
      expect(await h.exit, 0);
      expect(h.runtime.office!.destroyed, isTrue);
      expect(h.logLines, contains('end of stdin'));
    });

    test(
      'HOST-END-3: a refused frame is an error and ends the helper',
      () async {
        unawaited(h.exit);
        await h.next<OfficeHello>();
        h.input.add([0, 0, 0, 2, 250, 10]);
        expect((await h.next<OfficeError>()).code, 'protocol');
        expect(await h.exit, 2);
      },
    );

    test('HOST-END-4: a message sent by the helper is refused', () async {
      unawaited(h.exit);
      await h.next<OfficeHello>();
      h.input.add(_codec.encode(const OfficePong(id: 1)));
      expect((await h.next<OfficeError>()).code, 'wrongDirection');
    });
  });

  test('HOST-PROFILE-1: a clean close deletes the profile folder', () async {
    final dir = Directory('.dart_tool/test_scratch/host_test').absolute
      ..createSync(recursive: true);
    final profile = dir.createTempSync('own-profile-');
    final runtime = FakeRuntime();
    final input = StreamController<List<int>>();
    final host = OfficeHost(
      runtime: runtime,
      program: '/p',
      profileUrl: profile.uri.toString(),
      output: (_) {},
      log: (_) {},
    );
    final exit = host.serve(input.stream);
    await input.close();
    expect(await exit, 0);
    expect(profile.existsSync(), isFalse);
  });
}
