// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The pdf.js view against a fake webview channel: the content site, the
/// host pages, the bridge both ways and the save path (the page's bytes
/// POSTed to the real local server, written through TomBinaryFiles).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/pdfjs.dart';
import 'package:tom_pdf_editor/testing.dart';

const _path = '/docs/sample.pdf';

Future<({int status, String type, List<int> body})> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(uri)).close();
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (
      status: response.statusCode,
      type: response.headers.contentType?.mimeType ?? '',
      body: body,
    );
  } finally {
    client.close(force: true);
  }
}

Future<int> _post(Uri uri, List<int> bytes) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// One pdf.js view over the fake channel.
class _Rig {
  _Rig({this.mode = TomPdfJsMode.components, bool readOnlyFile = false}) {
    files.write(_path, utf8.encode('%PDF-original'));
    if (readOnlyFile) files.readOnly.add(_path);
    host = FakePdfEditorHost(
      filePath: _path,
      files: files,
      engine: FakePdfEngine(const {}),
    );
    controller = TomPdfJsController(host, mode: mode, server: server);
    channel = FakePdfJsChannel(onCall: _answer);
  }

  final TomPdfJsMode mode;
  final files = MemoryBinaryFiles();
  final server = TomLocalContentServer();
  late final FakePdfEditorHost host;
  late final TomPdfJsController controller;
  late final FakePdfJsChannel channel;

  /// The bytes the fake page "saves".
  List<int> saveBytes = utf8.encode('%PDF-original%annotated');

  /// Whether the fake page answers `save` (else it never does).
  bool answerSave = true;

  Future<void> _answer(String function, List<Object?> args) async {
    if (function == 'save' && answerSave) {
      // The page POSTs saveDocument()'s bytes, then reports.
      final status = await _post(Uri.parse(args.first! as String), saveBytes);
      channel.send({
        'type': 'saved',
        'ok': status == 200,
        'status': status,
        'size': saveBytes.length,
        'ms': 1,
      });
    }
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The server runs in the real zone, not the test's fake clock: started
    // here, before the view attaches.
    await tester.runAsync(controller.start);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TomPdfJsView(
            controller: controller,
            channelForTesting: channel,
          ),
        ),
      ),
    );
    await settle(tester);
    addTearDown(() async {
      await tester.runAsync(controller.close);
    });
  }

  /// Lets the real server and the bridge run.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// The page came up and opened the document.
  Future<void> open(WidgetTester tester, {int pages = 3}) async {
    channel.send({'type': 'ready', 'mode': mode.name});
    await settle(tester);
    channel.send({'type': 'loaded', 'pageCount': pages, 'ms': 5});
    await settle(tester);
  }
}

void main() {
  // flutter_test answers every HttpClient request with 400; these tests talk
  // to the real local server.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('PDFJS-SITE the content site and the pages', () {
    testWidgets('PDFJS-SITE-1: each mode loads its page; the host pages are '
        'made from viewer.html; pdf.js and the forge files are served', (
      tester,
    ) async {
      for (final mode in TomPdfJsMode.values) {
        final rig = _Rig(mode: mode);
        await rig.pump(tester);
        final page = rig.channel.loads.single;
        expect(page.host, '127.0.0.1');
        expect(page.queryParameters['readonly'], '0');
        expect(
          page.path,
          endsWith(switch (mode) {
            TomPdfJsMode.integrated => '/pdfjs/web/forge-integrated.html',
            TomPdfJsMode.full => '/pdfjs/web/forge-full.html',
            TomPdfJsMode.components => '/pdfjs/web/forge/components.html',
          }),
        );
        final answer = (await tester.runAsync(() => _get(page)))!;
        expect(answer.status, 200, reason: mode.name);
        expect(answer.type, 'text/html');
        final html = utf8.decode(answer.body);
        if (mode == TomPdfJsMode.components) {
          expect(html, contains('components.mjs'));
        } else {
          expect(html, contains('<script src="forge/options.js"></script>'));
          expect(html, contains('forge/generic.mjs'));
          // Everything else is pdf.js's viewer.html as it is.
          expect(html, contains('<script src="viewer.mjs" type="module">'));
          expect(
            html.contains('forge/integrated.css'),
            mode == TomPdfJsMode.integrated,
          );
          expect(
            html.indexOf('forge/options.js'),
            lessThan(html.indexOf('viewer.mjs')),
            reason: 'the options are set before the viewer starts',
          );
        }
        await tester.runAsync(rig.controller.close);
      }
    });

    testWidgets('PDFJS-SITE-2: the vendored files and the document are '
        'served; unknown paths are 404', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      final site = rig.controller.site!;
      final pdf = (await tester.runAsync(
        () => _get(site.uriOf('pdfjs/build/pdf.mjs')),
      ))!;
      expect(pdf.status, 200);
      expect(pdf.type, 'text/javascript');
      expect(utf8.decode(pdf.body), contains('pdfjsVersion = 6.5.438'));
      final viewer = (await tester.runAsync(
        () => _get(site.uriOf('pdfjs/components/pdf_viewer.mjs')),
      ))!;
      expect(viewer.status, 200);
      final bridge = (await tester.runAsync(
        () => _get(site.uriOf('pdfjs/web/forge/bridge.mjs')),
      ))!;
      expect(utf8.decode(bridge.body), contains('installBridge'));
      final css = (await tester.runAsync(
        () => _get(site.uriOf('pdfjs/web/forge/integrated.css')),
      ))!;
      expect(utf8.decode(css.body), contains('#printButton'));
      final missing = (await tester.runAsync(
        () => _get(site.uriOf('pdfjs/web/nothing.js')),
      ))!;
      expect(missing.status, 404);
      expect(rig.controller.documentUri.path, contains('/doc/0/sample.pdf'));
    });
  });

  group('PDFJS-BRIDGE messages both ways', () {
    testWidgets('PDFJS-BRIDGE-1: ready opens the document; loaded, history, '
        'modified, findCount and links come back', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      final c = rig.controller;
      rig.channel.send({'type': 'ready', 'mode': 'components'});
      await rig.settle(tester);
      expect(rig.channel.calls.single.$1, 'open');
      expect(rig.channel.calls.single.$2.single, '${c.documentUri}');
      expect(c.state, TomPdfJsState.opening);
      rig.channel.send({'type': 'loaded', 'pageCount': 43, 'ms': 5});
      rig.channel.send({'type': 'textLayer', 'value': true});
      await rig.settle(tester);
      expect(c.state, TomPdfJsState.open);
      expect(find.text('43 pages'), findsOneWidget);
      // Tools go to the page.
      await tester.tap(find.byKey(const ValueKey('pdfjs-tool-ink')));
      await rig.settle(tester);
      expect(rig.channel.calls.last.$1, 'setTool');
      expect(rig.channel.calls.last.$2, [TomPdfJsTool.ink]);
      // History enables undo; the tap calls the page's undo.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('pdfjs-undo')))
            .onPressed,
        isNull,
      );
      rig.channel.send({'type': 'history', 'canUndo': true, 'canRedo': false});
      rig.channel.send({'type': 'modified', 'value': true});
      await rig.settle(tester);
      expect(c.canUndo, isTrue);
      expect(c.isDirty, isTrue);
      expect(rig.host.historyChanges, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('pdfjs-undo')));
      await rig.settle(tester);
      expect(rig.channel.callNames.last, 'undo');
      // A link goes to the host; Cmd+F in the page shows the find bar.
      rig.channel.send({'type': 'openLink', 'url': 'https://example.org/'});
      rig.channel.send({'type': 'shortcut', 'key': 'find'});
      await rig.settle(tester);
      expect(rig.host.links, ['https://example.org/']);
      await tester.enterText(
        find.byKey(const ValueKey('pdfjs-find-field')),
        'reasoning',
      );
      await rig.settle(tester);
      final (fn, args) = rig.channel.calls.last;
      expect(fn, 'find');
      expect(args.first, 'reasoning');
      rig.channel.send({'type': 'findCount', 'current': 1, 'total': 12});
      await rig.settle(tester);
      expect(find.text('1 of 12'), findsOneWidget);
    });

    testWidgets('PDFJS-BRIDGE-2: an error opening shows could not open; a '
        'scanned PDF says it has no text layer', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.open(tester);
      rig.channel.send({'type': 'textLayer', 'value': false});
      await rig.settle(tester);
      expect(
        rig.host.notices.map((n) => n.$2),
        contains(contains('no text layer')),
      );
      rig.channel.send({
        'type': 'error',
        'kind': 'open',
        'message': 'Invalid PDF structure.',
      });
      await rig.settle(tester);
      expect(rig.controller.state, TomPdfJsState.failed);
      expect(find.textContaining('Invalid PDF structure'), findsOneWidget);
    });

    testWidgets('PDFJS-BRIDGE-3: a read-only file loads the page read-only; '
        'tools and save are refused, Save as copy is offered', (tester) async {
      final rig = _Rig(readOnlyFile: true);
      await rig.pump(tester);
      expect(rig.channel.loads.single.queryParameters['readonly'], '1');
      await rig.open(tester);
      expect(find.text('Read-only.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('pdfjs-tool-ink')))
            .onPressed,
        isNull,
      );
      await tester.runAsync(rig.controller.save);
      expect(rig.channel.callNames, isNot(contains('save')));
      await tester.tap(find.text('Save as copy'));
      await rig.settle(tester);
      await rig.settle(tester);
      expect(
        utf8.decode(rig.files.read('/docs/sample (copy).pdf')!),
        '%PDF-original%annotated',
      );
    });
  });

  group('PDFJS-SAVE the save path', () {
    testWidgets('PDFJS-SAVE-1: Cmd+S in the page saves: the bytes are POSTed, '
        'written over the unchanged file, the page reset and the document '
        'reopened', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.open(tester);
      rig.channel.send({'type': 'modified', 'value': true});
      await rig.settle(tester);
      rig.channel.send({'type': 'shortcut', 'key': 'save'});
      for (var i = 0; i < 4; i++) {
        await rig.settle(tester);
      }
      expect(utf8.decode(rig.files.read(_path)!), '%PDF-original%annotated');
      final names = rig.channel.callNames;
      expect(names.sublist(names.indexOf('save')), [
        'save',
        'resetModified',
        'open',
      ]);
      expect(rig.channel.calls.last.$2.single, contains('/doc/1/'));
      expect(rig.controller.isDirty, isFalse);
      expect(rig.controller.generation, 1);
      expect(rig.controller.conflict, isNull);
    });

    testWidgets('PDFJS-SAVE-2: a save over a changed file shows the conflict '
        'banner; Save as copy keeps the saved bytes beside it, Take theirs '
        'reopens', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.open(tester);
      rig.channel.send({'type': 'modified', 'value': true});
      await rig.settle(tester);
      rig.files.write(_path, utf8.encode('%PDF-theirs'));
      await tester.runAsync(rig.controller.save);
      await rig.settle(tester);
      expect(
        find.textContaining('changed on disk since it was opened'),
        findsOneWidget,
      );
      expect(utf8.decode(rig.files.read(_path)!), '%PDF-theirs');
      await tester.tap(find.text('Save as copy'));
      await rig.settle(tester);
      expect(
        utf8.decode(rig.files.read('/docs/sample (copy).pdf')!),
        '%PDF-original%annotated',
      );
      expect(rig.controller.conflict, isNull);
      await tester.runAsync(rig.controller.takeTheirs);
      await rig.settle(tester);
      expect(rig.controller.isDirty, isFalse);
      expect(rig.channel.callNames.last, 'open');
    });

    testWidgets('PDFJS-SAVE-3: a save the page reports failed ends with a '
        'notice; nothing is written', (tester) async {
      final rig = _Rig()..answerSave = false;
      await rig.pump(tester);
      await rig.open(tester);
      final saving = rig.controller.save();
      await rig.settle(tester);
      expect(rig.controller.state, TomPdfJsState.saving);
      rig.channel.send({
        'type': 'error',
        'kind': 'save',
        'message': 'saveDocument failed',
      });
      await rig.settle(tester);
      await tester.runAsync(() => saving);
      expect(rig.controller.state, TomPdfJsState.open);
      expect(utf8.decode(rig.files.read(_path)!), '%PDF-original');
      expect(
        rig.host.notices.map((n) => n.$2),
        contains(contains('saveDocument failed')),
      );
    });
  });

  testWidgets('PDFJS-SWAP-1: a new controller takes the webview over; the '
      'old one no longer hears the page', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.open(tester);
    final second = TomPdfJsController(
      rig.host,
      mode: TomPdfJsMode.components,
      server: rig.server,
    );
    await tester.runAsync(second.start);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TomPdfJsView(
            controller: second,
            channelForTesting: rig.channel,
          ),
        ),
      ),
    );
    await rig.settle(tester);
    expect(rig.channel.loads, hasLength(2));
    final before = rig.channel.callNames.length;
    rig.channel.send({'type': 'ready', 'mode': 'components'});
    await rig.settle(tester);
    // One open, from the new controller only.
    expect(rig.channel.callNames.sublist(before), ['open']);
    expect(second.state, TomPdfJsState.opening);
    expect(rig.controller.state, TomPdfJsState.open);
    await tester.runAsync(second.close);
  });

  testWidgets('PDFJS-CLOSE-1: closing closes the page and the site', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.open(tester);
    final site = rig.controller.site!;
    await tester.runAsync(rig.controller.close);
    expect(rig.channel.callNames.last, 'close');
    expect(site.isClosed, isTrue);
    expect(rig.controller.state, TomPdfJsState.closed);
    // The token is refused, or the server stopped with its last site.
    final refused = await tester.runAsync(() async {
      try {
        return (await _get(site.uriOf('pdfjs/build/pdf.mjs'))).status;
      } on SocketException {
        return -1;
      }
    });
    expect(refused, isNot(200));
  });
}
