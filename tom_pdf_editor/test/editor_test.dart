// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The editor against the fake engine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_editor/testing.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';

const _path = '/docs/sample.pdf';
const _a4 = PdfPageSize(595, 842);

const _page0 =
    'Chain of thought prompting\nelicits reasoning in models\n'
    'chain CHAIN chained';
const _page1 = 'Second page about reasoning\nand a link here';

FakePdfDocument _textDoc({
  int pages = 5,
  String? password,
  int permissions = 0xFFFFFFFF,
  int securityRevision = -1,
  Set<(int, int)> unmapped = const {},
  List<PdfOutlineEntry> outline = const [],
  Map<int, List<PdfAnnotation>>? annotations,
}) => FakePdfDocument(
  pages: List.filled(pages, _a4),
  texts: [
    _page0,
    _page1,
    for (var i = 2; i < pages; i++) 'Page ${i + 1} reasoning text',
  ],
  links: {
    1: [
      (
        fakeCharRect(_page1, 34).union(fakeCharRect(_page1, 37)),
        const PdfLink.uri('https://example.org/'),
      ),
      (
        fakeCharRect(_page1, 28).union(fakeCharRect(_page1, 30)),
        const PdfLink.page(3),
      ),
    ],
  },
  password: password,
  permissions: permissions,
  securityRevision: securityRevision,
  unmapped: unmapped,
  outline: outline,
  annotations: annotations,
);

extension on PdfRect {
  PdfRect union(PdfRect o) => PdfRect(
    left < o.left ? left : o.left,
    top < o.top ? top : o.top,
    right > o.right ? right : o.right,
    bottom > o.bottom ? bottom : o.bottom,
  );
}

/// One editor over the fake.
class _Rig {
  _Rig(
    FakePdfDocument doc, {
    bool readOnlyFile = false,
    TomPdfEngineStatus? status,
    FakePdfEngine? shared,
  }) {
    files.write(_path, utf8.encode('%PDF-original'));
    if (readOnlyFile) files.readOnly.add(_path);
    if (shared != null) shared.documents[_path] = doc;
    engine = shared ?? FakePdfEngine({_path: doc}, files: files);
    host = FakePdfEditorHost(
      filePath: _path,
      files: files,
      engine: engine,
      engineStatus: status,
    );
    controller = TomPdfEditorController(host);
  }

  final files = MemoryBinaryFiles();
  late final FakePdfEngine engine;
  late final FakePdfEditorHost host;
  late final TomPdfEditorController controller;
  final copied = <String>[];

  /// The host's find, when the editor is given one.
  VoidCallback? onFind;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TomPdfEditor(
            controller: controller,
            onFind: onFind,
            onCopy: (text) async => copied.add(text),
            decoder: (bgra, w, h) {
              final done = Completer<ui.Image>();
              _decodes.add((bgra, w, h, done));
              return done.future;
            },
          ),
        ),
      ),
    );
    await tester.runAsync(controller.open);
    await settle(tester);
  }

  final _decodes = <(Uint8List, int, int, Completer<ui.Image>)>[];

  /// Lets renders, decoding and searches finish. Images decode outside the
  /// test's fake clock, all at once.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      if (_decodes.isNotEmpty) {
        final batch = List.of(_decodes);
        _decodes.clear();
        await tester.runAsync(() async {
          for (final (bytes, w, h, done) in batch) {
            done.complete(await decodeBgra(bytes, w, h));
          }
        });
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  PdfPageViewState view(WidgetTester tester) =>
      tester.state<PdfPageViewState>(find.byType(PdfPageView));

  /// The global position of [rect]'s centre on [page].
  Offset at(WidgetTester tester, int page, PdfRect rect) {
    final v = view(tester);
    final box = tester.renderObject<RenderBox>(find.byType(PdfPageView));
    final width = box.size.width;
    final r = v.layout.toColumn(page, rect, width);
    return box.localToGlobal(
      r.center -
          Offset(
            v.horizontal.hasClients ? v.horizontal.offset : 0,
            v.vertical.offset,
          ),
    );
  }
}

void main() {
  group('PDF-OPEN opening', () {
    testWidgets('PDF-OPEN-1: opens, lays out every page, renders the visible '
        'ones and paints them', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      expect(rig.controller.state, TomPdfEditorState.open);
      expect(find.text('5 pages'), findsOneWidget);
      // The view's renders (the page list's thumbnails are 120 px wide).
      final rendered = rig.engine.renders
          .where((r) => r.$2 > 1) // the thumbnails render at about 0.6
          .map((r) => r.$1)
          .toSet();
      expect(rendered, contains(0));
      expect(
        rendered.length,
        lessThan(5),
        reason: 'only the visible pages and a prefetch',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(rig.host.engineStarts, 1);
    });

    testWidgets('PDF-OPEN-2: an engine that cannot be started (its library '
        'missing or of another release) shows why in the tab', (tester) async {
      final rig = _Rig(
        _textDoc(),
        status: const FakePdfEngineStatus.problem(
          'Engine version mismatch: /b/libengine is chromium/7000',
        ),
      );
      await rig.pump(tester);
      expect(rig.controller.state, TomPdfEditorState.failed);
      expect(find.textContaining('Engine version mismatch'), findsOneWidget);
      expect(rig.host.engineStarts, 0);
    });

    testWidgets('PDF-OPEN-3: a large document opens without rendering it all', (
      tester,
    ) async {
      final rig = _Rig(FakePdfDocument(pages: List.filled(4211, _a4)));
      await rig.pump(tester);
      expect(find.text('4211 pages'), findsOneWidget);
      final pages = rig.engine.renders.map((r) => r.$1).toSet();
      expect(pages.where((p) => p > 50), isEmpty);
    });

    testWidgets('PDF-OPEN-4: a non-writable file opens read-only with Save as '
        'copy', (tester) async {
      final rig = _Rig(_textDoc(), readOnlyFile: true);
      await rig.pump(tester);
      expect(rig.controller.isReadOnly, isTrue);
      expect(find.textContaining('Read-only'), findsOneWidget);
      await tester.tap(find.text('Save as copy'));
      await rig.settle(tester);
      expect(rig.files.paths, contains('/docs/sample (copy).pdf'));
    });
  });

  group('PDF-VIEW scrolling and zoom', () {
    testWidgets('PDF-VIEW-1: scrolling renders the pages that come into view', (
      tester,
    ) async {
      final rig = _Rig(_textDoc(pages: 40));
      await rig.pump(tester);
      final v = rig.view(tester);
      v.vertical.jumpTo(v.layout.pageTop(30));
      await rig.settle(tester);
      expect(rig.engine.renders.map((r) => r.$1), contains(30));
    });

    testWidgets('PDF-VIEW-2: Cmd + zooms in, Cmd 0 resets; above 2048 px a '
        'page renders as 512-px tiles', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      final start = rig.view(tester).widget.zoom;
      await tester.tap(find.byType(PdfPageView));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await rig.settle(tester);
      expect(rig.view(tester).widget.zoom, greaterThan(start));
      // Zoom to 400 %: 595 pt × 4 × 96/72 ≈ 3173 px, above the limit.
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
      }
      await rig.settle(tester);
      expect(rig.view(tester).widget.zoom, 400);
      final big = rig.engine.renders.where((r) => r.$2 > 4);
      expect(big, isNotEmpty);
      expect(
        big.every((r) => r.$5 <= kPdfTileSize && r.$6 <= kPdfTileSize),
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(rig.view(tester).widget.zoom, 100);
    });

    testWidgets('PDF-VIEW-3: the page list jumps to a page', (tester) async {
      final rig = _Rig(_textDoc(pages: 12));
      await rig.pump(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pdf-thumb-9')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('pdf-thumb-9')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-thumb-9')));
      await rig.settle(tester);
      final v = rig.view(tester);
      expect(v.layout.pageAt(v.vertical.offset + 20), 9);
    });

    testWidgets('PDF-VIEW-4: the outline shows and jumps', (tester) async {
      final rig = _Rig(
        _textDoc(
          outline: const [
            PdfOutlineEntry('Introduction', 0, []),
            PdfOutlineEntry('Results', 3, [PdfOutlineEntry('Tables', 4, [])]),
          ],
        ),
      );
      await rig.pump(tester);
      await tester.tap(find.text('Outline'));
      await tester.pump();
      await tester.tap(find.text('Tables'));
      await rig.settle(tester);
      final v = rig.view(tester);
      expect(v.layout.pageAt(v.vertical.offset + 20), 4);
    });
  });

  group('PDF-FIND search', () {
    testWidgets('PDF-FIND-1: hits stream in, the count shows, next and '
        'previous move, the view jumps', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      rig.controller.showFind();
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('pdf-find-field')),
        'reasoning',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await rig.settle(tester);
      expect(rig.controller.hits.length, 5);
      expect(find.text('1 / 5'), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      await tester.pump();
      expect(find.text('2 / 5'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous'));
      await tester.tap(find.byTooltip('Previous'));
      await tester.pump();
      expect(find.text('5 / 5'), findsOneWidget);
      expect(rig.controller.scrollRequest.value!.$1, 4);
      // The search term is never logged.
      expect(rig.engine.calls.last, 'find 9 chars');
    });

    testWidgets('PDF-FIND-2: match case and whole word', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      rig.controller.find('chain');
      await rig.settle(tester);
      expect(rig.controller.hits.length, 4); // Chain, chain, CHAIN, chain(ed)
      rig.controller.find('chain', matchCase: true);
      await rig.settle(tester);
      expect(rig.controller.hits.length, 2);
      rig.controller.find('chain', wholeWord: true);
      await rig.settle(tester);
      expect(rig.controller.hits.length, 3);
    });
  });

  group('PDF-SEL selection and copy', () {
    testWidgets('PDF-SEL-1: a drag selects, Cmd+C copies the text', (
      tester,
    ) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      final from = rig.at(tester, 0, fakeCharRect(_page0, 0));
      final to = rig.at(tester, 0, fakeCharRect(_page0, 4));
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(from + const Offset(3, 0));
      await gesture.moveTo(to);
      await gesture.up();
      await rig.settle(tester);
      expect(rig.controller.selection.single.count, 5);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await rig.settle(tester);
      expect(rig.copied.single, 'Chain');
    });

    testWidgets('PDF-SEL-2: double-click selects a word, triple-click a line', (
      tester,
    ) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      final p = rig.at(tester, 0, fakeCharRect(_page0, 10)); // "thought"
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(p);
      await rig.settle(tester);
      final word = await rig.controller.selectedText();
      expect(word, 'thought');
      await tester.tapAt(p);
      await rig.settle(tester);
      expect(await rig.controller.selectedText(), 'Chain of thought prompting');
    });

    testWidgets(
      'PDF-SEL-3: a selection across pages joins them with a newline',
      (tester) async {
        final rig = _Rig(_textDoc());
        await rig.pump(tester);
        await tester.runAsync(
          () => rig.controller.selectBetween(
            0,
            (x: 111, y: 69), // in "chained"
            1,
            (x: 40, y: 40),
          ),
        );
        expect(rig.controller.selection.length, 2);
        final text = (await tester.runAsync(rig.controller.selectedText))!;
        expect(text, 'chained\nS');
      },
    );

    testWidgets('PDF-SEL-4: no copy permission refuses with a notice; '
        'unmapped characters are skipped with a notice', (tester) async {
      final noCopy = _Rig(
        _textDoc(permissions: 0xFFFFFFFF & ~PdfPermission.copy),
      );
      await noCopy.pump(tester);
      await tester.runAsync(
        () => noCopy.controller.selectAround(0, 40, 40, line: false),
      );
      expect(await tester.runAsync(noCopy.controller.selectedText), isNull);
      await noCopy.settle(tester);
      expect(
        noCopy.host.notices.map((n) => n.$2),
        contains(contains('does not allow copying')),
      );

      final unmapped = _Rig(_textDoc(unmapped: {(0, 1), (0, 2)}));
      await unmapped.pump(tester);
      await tester.runAsync(
        () => unmapped.controller.selectBetween(
          0,
          (x: 37, y: 40),
          0,
          (x: 63, y: 40),
        ),
      );
      final text = (await tester.runAsync(unmapped.controller.selectedText))!;
      expect(text, 'Cin');
      await unmapped.settle(tester);
      expect(
        unmapped.host.notices.map((n) => n.$2),
        contains(contains('could not be copied')),
      );
    });
  });

  group('PDF-LINK links', () {
    testWidgets(
      'PDF-LINK-1: a URI goes to the host, an internal link scrolls',
      (tester) async {
        final rig = _Rig(_textDoc());
        await rig.pump(tester);
        final v = rig.view(tester);
        v.vertical.jumpTo(v.layout.pageTop(1) - 10);
        await rig.settle(tester);
        await tester.tapAt(rig.at(tester, 1, fakeCharRect(_page1, 35)));
        await rig.settle(tester);
        expect(rig.host.links, ['https://example.org/']);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tapAt(rig.at(tester, 1, fakeCharRect(_page1, 29)));
        await rig.settle(tester);
        expect(
          rig.view(tester).layout.pageAt(rig.view(tester).vertical.offset + 20),
          3,
        );
      },
    );
  });

  group('PDF-SEC encrypted and scanned', () {
    testWidgets('PDF-SEC-1: a password is asked, a wrong one again, then it '
        'opens; the password never shows in a notice', (tester) async {
      final rig = _Rig(_textDoc(password: 'sesame', securityRevision: 3));
      await rig.pump(tester);
      expect(rig.controller.state, TomPdfEditorState.password);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        'wrong',
      );
      await tester.tap(find.text('Open'));
      await rig.settle(tester);
      expect(find.textContaining('password was wrong'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        'sesame',
      );
      await tester.tap(find.text('Open'));
      await rig.settle(tester);
      expect(rig.controller.state, TomPdfEditorState.open);
      // Encrypted: annotations are off (DPPF-3).
      expect(rig.controller.canAnnotate, isFalse);
      expect(
        rig.host.notices.map((n) => n.$2),
        contains(contains('encrypted')),
      );
      expect(rig.host.notices.any((n) => n.$2.contains('sesame')), isFalse);
    });

    testWidgets('PDF-SEC-2: three wrong passwords, or a cancel, end in could '
        'not open', (tester) async {
      final rig = _Rig(_textDoc(password: 'sesame'));
      await rig.pump(tester);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => rig.controller.answerPassword('nope'));
      }
      await rig.settle(tester);
      expect(rig.controller.state, TomPdfEditorState.failed);
      expect(find.textContaining('three times'), findsOneWidget);

      final cancel = _Rig(_textDoc(password: 'sesame'));
      await cancel.pump(tester);
      await tester.tap(find.text('Cancel'));
      await cancel.settle(tester);
      expect(find.textContaining('could not open'), findsOneWidget);
    });

    testWidgets('PDF-SEC-3: a scanned PDF says it has no text layer; search '
        'is refused', (tester) async {
      final rig = _Rig(FakePdfDocument(pages: List.filled(3, _a4)));
      await rig.pump(tester);
      expect(rig.controller.hasTextLayer, isFalse);
      expect(
        rig.host.notices.map((n) => n.$2),
        contains(contains('no text layer')),
      );
      rig.controller.showFind();
      await tester.pump();
      expect(rig.controller.findVisible, isFalse);
    });
  });

  group('PDF-EXT external changes and saving', () {
    testWidgets('PDF-EXT-1: a clean document reopens when the file changed; a '
        'deleted file is marked', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      rig.files.write(_path, utf8.encode('%PDF-changed'));
      await tester.runAsync(rig.controller.checkExternal);
      await rig.settle(tester);
      expect(rig.controller.generation, 1);
      expect(
        rig.host.notices.map((n) => n.$2),
        contains(contains('changed on disk')),
      );
      rig.files.delete(_path);
      await tester.runAsync(rig.controller.checkExternal);
      await rig.settle(tester);
      expect(rig.controller.isDeleted, isTrue);
      expect(find.textContaining('deleted on disk'), findsOneWidget);
    });

    testWidgets('PDF-EXT-2: a save over a changed file shows the conflict '
        'banner; Take theirs reopens', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      rig.controller.pushEdit(_NoopEdit());
      expect(rig.controller.isDirty, isTrue);
      rig.files.write(_path, utf8.encode('%PDF-theirs'));
      await tester.runAsync(rig.controller.save);
      await rig.settle(tester);
      expect(
        find.textContaining('changed on disk since it was opened'),
        findsOneWidget,
      );
      await tester.tap(find.text('Take theirs'));
      await rig.settle(tester);
      expect(rig.controller.conflict, isNull);
      expect(rig.controller.isDirty, isFalse);
    });

    testWidgets('PDF-EXT-3: a save over an unchanged file replaces it, clears '
        'dirty and reopens', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      rig.controller.pushEdit(_NoopEdit());
      await tester.runAsync(rig.controller.save);
      await rig.settle(tester);
      expect(utf8.decode(rig.files.read(_path)!), '%PDF-saved');
      expect(rig.controller.isDirty, isFalse);
      expect(rig.controller.generation, 1);
      expect(rig.host.historyChanges, greaterThan(0));
    });
  });

  group('PDF-ANNOT annotations', () {
    /// Drags from [from] to [to] with the mouse, through [via].
    Future<void> drag(
      WidgetTester tester,
      Offset from,
      Offset to, {
      List<Offset> via = const [],
    }) async {
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await g.moveTo(from + const Offset(3, 0));
      for (final p in via) {
        await g.moveTo(p);
      }
      await g.moveTo(to);
      await g.up();
    }

    Future<void> key(
      WidgetTester tester,
      LogicalKeyboardKey k, {
      bool meta = false,
      bool shift = false,
    }) async {
      if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    }

    testWidgets('PDF-ANNOT-W1: a highlight drag is one history entry; undo, '
        'redo and dirty follow it; the page renders again', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      final c = rig.controller;
      expect(c.canAnnotate, isTrue);
      await tester.tap(find.byKey(const ValueKey('pdf-tool-highlight')));
      await rig.settle(tester);
      expect(c.tool, PdfAnnotationTool.highlight);
      final renders = rig.engine.renders.where((r) => r.$1 == 0).length;
      await drag(
        tester,
        rig.at(tester, 0, fakeCharRect(_page0, 0)),
        rig.at(tester, 0, fakeCharRect(_page0, 4)),
      );
      await rig.settle(tester);
      var list = c.annotationsOn(0);
      expect(list, hasLength(1));
      final h = list.single;
      expect(h.kind, PdfAnnotationKind.highlight);
      expect(h.quads, isNotEmpty);
      expect(h.author, 'Test Author');
      expect(h.modified, startsWith('D:'));
      expect(h.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(c.selection, isEmpty);
      expect(c.isDirty, isTrue);
      expect(c.canUndo, isTrue);
      expect(c.undoLabel, 'Highlight');
      expect(c.pageVersion(0), 1);
      expect(
        rig.engine.renders.where((r) => r.$1 == 0).length,
        greaterThan(renders),
        reason: 'the edited page renders again',
      );
      // Undo with Cmd+Z, redo with Cmd+Shift+Z.
      await key(tester, LogicalKeyboardKey.keyZ, meta: true);
      await rig.settle(tester);
      expect(c.annotationsOn(0), isEmpty);
      expect(c.isDirty, isFalse);
      expect(c.canRedo, isTrue);
      await key(tester, LogicalKeyboardKey.keyZ, meta: true, shift: true);
      await rig.settle(tester);
      list = c.annotationsOn(0);
      expect(list.single.id, h.id);
      expect(c.isDirty, isTrue);
      // A selection over two pages is highlighted as one entry.
      await tester.runAsync(
        () => c.selectBetween(0, (x: 60, y: 60), 1, (x: 80, y: 60)),
      );
      await tester.runAsync(c.highlightSelection);
      await rig.settle(tester);
      expect(c.annotationsOn(0), hasLength(2));
      expect(c.annotationsOn(1), hasLength(1));
      await tester.runAsync(c.undo);
      await rig.settle(tester);
      expect(c.annotationsOn(0), hasLength(1));
      expect(c.annotationsOn(1), isEmpty);
    });

    testWidgets('PDF-ANNOT-W2: the note tool places a note with its text; '
        'editing the text is undone in one step', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      final c = rig.controller;
      // A click gives the view the focus; N chooses the note tool.
      await tester.tapAt(rig.at(tester, 0, const PdfRect(500, 200, 500, 200)));
      await rig.settle(tester);
      await key(tester, LogicalKeyboardKey.keyN);
      await rig.settle(tester);
      expect(c.tool, PdfAnnotationTool.note);
      await tester.tapAt(rig.at(tester, 0, const PdfRect(300, 400, 300, 400)));
      await rig.settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-note-text')),
        'First thought',
      );
      await tester.tap(find.byKey(const ValueKey('pdf-note-ok')));
      await rig.settle(tester);
      final note = c.annotationsOn(0).single;
      expect(note.kind, PdfAnnotationKind.note);
      expect(note.contents, 'First thought');
      expect(note.rect.left, closeTo(290, 0.5));
      expect(c.selectedAnnotation?.id, note.id);
      await tester.tap(find.byKey(const ValueKey('pdf-edit-note')));
      await rig.settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-note-text')),
        'Second thought',
      );
      await tester.tap(find.byKey(const ValueKey('pdf-note-ok')));
      await rig.settle(tester);
      expect(c.annotationsOn(0).single.contents, 'Second thought');
      expect(c.undoLabel, 'Note text');
      await tester.tap(find.byKey(const ValueKey('pdf-undo')));
      await rig.settle(tester);
      expect(c.annotationsOn(0).single.contents, 'First thought');
      await tester.tap(find.byKey(const ValueKey('pdf-undo')));
      await rig.settle(tester);
      expect(c.annotationsOn(0), isEmpty);
      expect(c.isDirty, isFalse);
    });

    testWidgets('PDF-ANNOT-W3: ink is drawn by a drag, moved by a drag, '
        'deleted with Backspace; each is one entry', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      final c = rig.controller;
      await tester.tap(find.byKey(const ValueKey('pdf-tool-ink')));
      await rig.settle(tester);
      Offset p(double x, double y) => rig.at(tester, 0, PdfRect(x, y, x, y));
      await drag(
        tester,
        p(100, 500),
        p(200, 500),
        via: [
          for (var x = 104.0; x < 200; x += 4)
            p(x, 500 + (x % 8 == 0 ? 0.1 : 0)),
        ],
      );
      await rig.settle(tester);
      final ink = c.annotationsOn(0).single;
      expect(ink.kind, PdfAnnotationKind.ink);
      expect(ink.strokes.single.length, lessThan(6), reason: 'thinned');
      expect(ink.strokes.single.first.x, closeTo(100, 1));
      expect(ink.strokes.single.last.x, closeTo(200, 1));
      // Select tool: drag the ink 50 points down.
      await tester.tap(find.byKey(const ValueKey('pdf-tool-select')));
      await rig.settle(tester);
      await drag(tester, p(150, 500), p(150, 550));
      await rig.settle(tester);
      final moved = c.annotationsOn(0).single;
      expect(moved.strokes.single.first.y, closeTo(550, 1.5));
      expect(c.undoLabel, 'Move');
      expect(c.selectedAnnotation?.id, ink.id);
      await key(tester, LogicalKeyboardKey.backspace);
      await rig.settle(tester);
      expect(c.annotationsOn(0), isEmpty);
      await tester.runAsync(c.undo);
      await rig.settle(tester);
      expect(
        c.annotationsOn(0).single.strokes.single.first.y,
        closeTo(550, 1.5),
      );
      await tester.runAsync(c.undo);
      await rig.settle(tester);
      expect(c.annotationsOn(0).single.strokes.single.first.y, closeTo(500, 1));
      await tester.runAsync(c.undo);
      await rig.settle(tester);
      expect(c.annotationsOn(0), isEmpty);
      expect(c.isDirty, isFalse);
    });

    testWidgets('PDF-ANNOT-W4: an annotation of the file without NM is '
        'recoloured and gets one; dirty against the saved state', (
      tester,
    ) async {
      final rig = _Rig(
        _textDoc(
          annotations: {
            0: [
              const PdfAnnotation(
                id: '',
                kind: PdfAnnotationKind.ink,
                rect: PdfRect(100, 300, 200, 340),
                color: 0xFFE53935,
                strokes: [
                  [(x: 101, y: 320), (x: 199, y: 320)],
                ],
              ),
            ],
          },
        ),
      );
      await rig.pump(tester);
      final c = rig.controller;
      expect(c.annotationsOn(0).single.id, '#0');
      await tester.tapAt(rig.at(tester, 0, const PdfRect(150, 320, 150, 320)));
      await rig.settle(tester);
      expect(c.selectedAnnotation?.id, '#0');
      await tester.tap(find.byKey(const ValueKey('pdf-color-ff42a5f5')));
      await rig.settle(tester);
      final named = c.annotationsOn(0).single;
      expect(named.unnamed, isFalse);
      expect(named.color, 0xFF42A5F5);
      expect(c.selectedAnnotation?.id, named.id);
      expect(rig.engine.calls, contains('updateAnnotation 0 #0'));
      // Saved: clean; an undo after the save makes it dirty again and finds
      // the annotation by its NM in the reopened document.
      await tester.runAsync(c.save);
      await rig.settle(tester);
      expect(c.isDirty, isFalse);
      await tester.runAsync(c.undo);
      await rig.settle(tester);
      expect(c.isDirty, isTrue);
      final back = c.annotationsOn(0).single;
      expect(back.color, 0xFFE53935);
      expect(back.id, named.id);
      await tester.runAsync(c.redo);
      await rig.settle(tester);
      expect(c.isDirty, isFalse);
    });

    testWidgets('PDF-ANNOT-W5: an encrypted document has the tools disabled; '
        'Save as copy writes an unencrypted copy only after the warning', (
      tester,
    ) async {
      final rig = _Rig(_textDoc(password: 'sesame', securityRevision: 3));
      await rig.pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        'sesame',
      );
      await tester.tap(find.text('Open'));
      await rig.settle(tester);
      final c = rig.controller;
      expect(c.canAnnotate, isFalse);
      final ink = tester.widget<IconButton>(
        find.byKey(const ValueKey('pdf-tool-ink')),
      );
      expect(ink.onPressed, isNull);
      await key(tester, LogicalKeyboardKey.keyI);
      expect(c.tool, PdfAnnotationTool.select);
      // Cancelled: nothing written.
      await tester.tap(find.byKey(const ValueKey('pdf-save-unencrypted')));
      await rig.settle(tester);
      expect(find.text('Save an unencrypted copy?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await rig.settle(tester);
      expect(rig.files.paths, isNot(contains('/docs/sample (copy).pdf')));
      // Confirmed: the copy has no security.
      await tester.tap(find.byKey(const ValueKey('pdf-save-unencrypted')));
      await rig.settle(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-save-unencrypted-ok')));
      await rig.settle(tester);
      expect(
        utf8.decode(rig.files.read('/docs/sample (copy).pdf')!),
        '%PDF-unencrypted',
      );
      expect(utf8.decode(rig.files.read(_path)!), '%PDF-original');
    });
  });

  group('PDF-FORM form filling', () {
    FakePdfDocument formDoc({String? password, int securityRevision = -1}) =>
        FakePdfDocument(
          pages: List.filled(2, _a4),
          texts: const ['A form', 'Page two'],
          formType: PdfFormType.acroForm,
          password: password,
          securityRevision: securityRevision,
          fields: [
            FakeFormField(
              page: 0,
              name: 'first',
              type: PdfFieldType.text,
              rect: const PdfRect(100, 100, 300, 120),
              value: 'old',
            ),
            FakeFormField(
              page: 0,
              name: 'second',
              type: PdfFieldType.text,
              rect: const PdfRect(100, 140, 300, 160),
            ),
            FakeFormField(
              page: 0,
              name: 'agree',
              type: PdfFieldType.checkbox,
              rect: const PdfRect(100, 180, 112, 192),
            ),
            for (var i = 0; i < 2; i++)
              FakeFormField(
                page: 0,
                name: 'pick',
                index: i,
                type: PdfFieldType.radio,
                rect: PdfRect(100 + i * 40.0, 210, 112 + i * 40.0, 222),
                checked: i == 0,
              ),
            FakeFormField(
              page: 0,
              name: 'choice',
              type: PdfFieldType.comboBox,
              rect: const PdfRect(100, 240, 300, 260),
            ),
          ],
        );

    Offset centre(_Rig rig, WidgetTester tester, PdfRect r) => rig.at(
      tester,
      0,
      PdfRect(
        (r.left + r.right) / 2,
        (r.top + r.bottom) / 2,
        (r.left + r.right) / 2,
        (r.top + r.bottom) / 2,
      ),
    );

    FakeFormField field(_Rig rig, String name, [int index = 0]) => rig
        .engine
        .documents[_path]!
        .fields
        .firstWhere((f) => f.name == name && f.index == index);

    Future<void> type(WidgetTester tester, String text) async {
      for (final ch in text.split('')) {
        // The key is any letter key; the character is what counts.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ, character: ch);
      }
    }

    testWidgets('PDF-FORM-W1: typed text is committed when the field loses '
        'the focus (Tab), as one history entry; undo and redo', (tester) async {
      final rig = _Rig(formDoc());
      await rig.pump(tester);
      final c = rig.controller;
      expect(c.canFill, isTrue);
      await tester.tapAt(centre(rig, tester, field(rig, 'first').rect));
      await rig.settle(tester);
      expect(c.formFocus?.name, 'first');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await type(tester, 'Tom 42x');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await rig.settle(tester);
      expect(c.formFocus?.value, 'Tom 42');
      // Nothing committed yet: not dirty, no entry.
      expect(c.canUndo, isFalse);
      expect(field(rig, 'first').value, 'old');
      // The page renders again as the field changes.
      expect(c.pageVersion(0), greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await rig.settle(tester);
      expect(c.formFocus?.name, 'second');
      expect(field(rig, 'first').value, 'Tom 42');
      expect(c.canUndo, isTrue);
      expect(c.undoLabel, 'Text field');
      expect(c.isDirty, isTrue);
      // Undo releases the focus and restores the old text.
      await tester.tap(find.byKey(const ValueKey('pdf-undo')));
      await rig.settle(tester);
      expect(c.formFocus, isNull);
      expect(field(rig, 'first').value, 'old');
      expect(c.isDirty, isFalse);
      expect(rig.engine.calls, contains('formSetValue 0 first old'));
      await tester.tap(find.byKey(const ValueKey('pdf-redo')));
      await rig.settle(tester);
      expect(field(rig, 'first').value, 'Tom 42');
      expect(c.isDirty, isTrue);
    });

    testWidgets('PDF-FORM-W2: a checkbox and a radio button change at the '
        'click, each one entry; Cmd+Z in a field undoes its typing first', (
      tester,
    ) async {
      final rig = _Rig(formDoc());
      await rig.pump(tester);
      final c = rig.controller;
      await tester.tapAt(centre(rig, tester, field(rig, 'agree').rect));
      await rig.settle(tester);
      expect(field(rig, 'agree').checked, isTrue);
      expect(c.undoLabel, 'Checkbox');
      await tester.tapAt(centre(rig, tester, field(rig, 'pick', 1).rect));
      await rig.settle(tester);
      expect(field(rig, 'pick', 1).checked, isTrue);
      expect(field(rig, 'pick').checked, isFalse);
      expect(c.undoLabel, 'Radio button');
      // Typing in a field, then Cmd+Z: the field's own undo.
      await tester.tapAt(centre(rig, tester, field(rig, 'second').rect));
      await rig.settle(tester);
      await type(tester, 'ab');
      await rig.settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await rig.settle(tester);
      expect(c.formFocus?.value, 'a');
      expect(c.undoLabel, 'Radio button', reason: 'no entry for typing');
      // Escape commits the field: an entry; then two undos take back the
      // text and the radio button, a third the checkbox.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await rig.settle(tester);
      expect(c.formFocus, isNull);
      expect(field(rig, 'second').value, 'a');
      expect(c.undoLabel, 'Text field');
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(c.undo);
        await rig.settle(tester);
      }
      expect(field(rig, 'second').value, '');
      expect(field(rig, 'pick').checked, isTrue);
      expect(field(rig, 'pick', 1).checked, isFalse);
      await tester.runAsync(c.undo);
      await rig.settle(tester);
      expect(field(rig, 'agree').checked, isFalse);
      expect(c.isDirty, isFalse);
      // Redo walks forward through all three.
      for (var i = 0; i < 3; i++) {
        expect(c.canRedo, isTrue, reason: 'redo ${i + 1}');
        await tester.runAsync(c.redo);
        await rig.settle(tester);
      }
      expect(field(rig, 'agree').checked, isTrue);
      expect(field(rig, 'pick', 1).checked, isTrue);
      expect(field(rig, 'second').value, 'a');
      expect(c.canRedo, isFalse);
    });

    testWidgets('PDF-FORM-W3: choosing a tool or saving releases the focus '
        'and commits; a combo box takes no click', (tester) async {
      final rig = _Rig(formDoc());
      await rig.pump(tester);
      final c = rig.controller;
      await tester.tapAt(centre(rig, tester, field(rig, 'second').rect));
      await rig.settle(tester);
      await type(tester, 'one');
      await rig.settle(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-tool-ink')));
      await rig.settle(tester);
      expect(c.formFocus, isNull);
      expect(field(rig, 'second').value, 'one');
      expect(c.undoLabel, 'Text field');
      await tester.tap(find.byKey(const ValueKey('pdf-tool-select')));
      await rig.settle(tester);
      // Saving commits the focused field first.
      await tester.tapAt(centre(rig, tester, field(rig, 'first').rect));
      await rig.settle(tester);
      await type(tester, '!');
      await rig.settle(tester);
      await tester.runAsync(c.save);
      await rig.settle(tester);
      expect(field(rig, 'first').value, 'old!');
      expect(c.isDirty, isFalse);
      // The combo box is drawn but not filled.
      await tester.tapAt(centre(rig, tester, field(rig, 'choice').rect));
      await rig.settle(tester);
      expect(c.formFocus, isNull);
    });

    testWidgets('PDF-FORM-W4: an encrypted document is not filled (DPPF-3)', (
      tester,
    ) async {
      final rig = _Rig(formDoc(password: 'sesame', securityRevision: 3));
      await rig.pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        'sesame',
      );
      await tester.tap(find.text('Open'));
      await rig.settle(tester);
      final c = rig.controller;
      expect(c.canFill, isFalse);
      await tester.tapAt(centre(rig, tester, field(rig, 'agree').rect));
      await rig.settle(tester);
      expect(field(rig, 'agree').checked, isFalse);
      expect(rig.engine.calls.where((x) => x.startsWith('formClick')), isEmpty);
      expect(
        find.textContaining('annotations and form filling are not'),
        findsOneWidget,
      );
    });
  });

  testWidgets('PDF-VIEW-6: a position the host gives back is applied at '
      'the first layout; the view reports where it stands', (tester) async {
    final rig = _Rig(_textDoc(pages: 12));
    rig.controller.restoreView(
      const PdfViewPosition(page: 6, offset: 0.5, zoom: 150),
    );
    await rig.pump(tester);
    expect(find.text('150 %'), findsOneWidget);
    final v = rig.view(tester);
    expect(v.position!.$1, 6);
    expect(v.position!.$2, closeTo(0.5, 0.01));
    v.vertical.jumpTo(v.layout.pageTop(2));
    await rig.settle(tester);
    final p = rig.controller.viewPosition!;
    expect(p.page, 2);
    expect(p.zoom, 150);
    // Round trip through JSON, as Forge keeps it.
    expect(PdfViewPosition.fromJson(p.toJson()), p);
    expect(PdfViewPosition.fromJson(const {'page': 'x'}), isNull);
  });

  testWidgets('PDF-VIEW-7: with a host find, Cmd+F and the find button call '
      'it; the editor\'s own find bar stays hidden', (tester) async {
    final rig = _Rig(_textDoc());
    var asked = 0;
    rig.onFind = () => asked++;
    await rig.pump(tester);
    await tester.tap(find.byTooltip('Find'));
    await rig.settle(tester);
    expect(asked, 1);
    await tester.tapAt(rig.at(tester, 0, fakeCharRect(_page0, 0)));
    await rig.settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await rig.settle(tester);
    expect(asked, 2);
    expect(rig.controller.findVisible, isFalse);
  });

  testWidgets('PDF-VIEW-5: in a narrow pane (a split copy) the bars scroll '
      'instead of overflowing', (tester) async {
    final rig = _Rig(_textDoc());
    await rig.pump(tester);
    await tester.binding.setSurfaceSize(const Size(360, 600));
    await rig.settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pdf-undo')), findsOneWidget);
  });

  testWidgets('PDF-CLOSE-2: closing the controller under a mounted editor '
      'reports nothing: renders, thumbnails and text requests of the closed '
      'document are dropped quietly', (tester) async {
    final rig = _Rig(_textDoc(pages: 40));
    await rig.pump(tester);
    expect(rig.controller.state, TomPdfEditorState.open);
    // Closed while the editor is still shown (the engine lets the document
    // go at once), then the view and the page list asked for more.
    final view = tester.state<PdfPageViewState>(find.byType(PdfPageView));
    final target = view.layout.pageTop(20);
    final rendersBefore = rig.engine.renders.length;
    rig.controller.find('reasoning');
    view.vertical.jumpTo(target);
    for (final s in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    )) {
      final p = s.position;
      if (p.maxScrollExtent > 0 && p.axis == Axis.vertical) {
        p.jumpTo(p.maxScrollExtent);
      }
    }
    // The frame asks for the new pages and thumbnails; the controller is
    // closed after it, before the engine has answered them (as PDFium's
    // worker answers queued renders after a close).
    late Future<void> closing;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => closing = rig.controller.close(),
    );
    await tester.pump();
    await rig.settle(tester);
    await tester.runAsync(() => closing);
    await rig.settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      rig.engine.renders.length,
      rendersBefore,
      reason: 'no render of the closed document was answered',
    );
    expect(rig.controller.state, TomPdfEditorState.closed);
    expect(find.byKey(const ValueKey('pdf-failure')), findsOneWidget);
  });

  testWidgets('PDF-CLOSE-1: closing gives the engine share up', (tester) async {
    final rig = _Rig(_textDoc());
    await rig.pump(tester);
    await tester.runAsync(rig.controller.close);
    expect(rig.engine.releases, 1);
    expect(rig.engine.calls, contains('close 1'));
  });

  group('PDF-DRAW the first page is drawn', () {
    /// Answers the password panel with [password].
    Future<void> unlock(WidgetTester tester, _Rig rig, String password) async {
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        password,
      );
      await tester.tap(find.text('Open'));
      await rig.settle(tester);
    }

    testWidgets('PDF-DRAW-1: a cancel sent after its render ran is not kept: '
        'the next document on the same engine, opened with a password, draws '
        'page 1', (tester) async {
      final first = _Rig(_textDoc());
      await first.pump(tester);
      expect(first.view(tester).hasCurrentImages(0), isTrue);
      final used = first.engine.tickets.whereType<int>().toList();
      expect(used, isNotEmpty);
      // The cancels of a view closed while its renders were answered: they
      // arrive after the renders ran.
      used.forEach(first.engine.cancel);
      await tester.pumpWidget(const SizedBox());
      await first.controller.close();

      final second = _Rig(
        _textDoc(password: 'sesame', securityRevision: 3),
        shared: first.engine,
      );
      await second.pump(tester);
      expect(second.controller.state, TomPdfEditorState.password);
      await unlock(tester, second, 'sesame');
      expect(second.controller.state, TomPdfEditorState.open);
      expect(second.view(tester).hasCurrentImages(0), isTrue);
      final later = second.engine.tickets.skip(used.length);
      expect(
        later.where(used.contains),
        isEmpty,
        reason: 'two views on one engine never send the same ticket',
      );
    });

    testWidgets('PDF-DRAW-2: a render the engine drops without a cancel is '
        'asked for again', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester);
      expect(rig.view(tester).hasCurrentImages(0), isTrue);
      // The next zoom's first renders answer null, nobody having cancelled
      // them; nothing else asks the view to render meanwhile.
      rig.engine.dropNextRenders = 3;
      await tester.tap(find.byTooltip('Zoom in'));
      await rig.settle(tester);
      await rig.settle(tester);
      expect(rig.engine.dropNextRenders, 0);
      expect(rig.view(tester).hasCurrentImages(0), isTrue);
    });

    testWidgets('PDF-DRAW-3: a re-layout while the first render is in flight '
        'ends with page 1 drawn at the new size', (tester) async {
      final rig = _Rig(_textDoc(password: 'sesame', securityRevision: 3));
      await rig.pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        'sesame',
      );
      await tester.tap(find.text('Open'));
      // The document opens and page 1 is asked for; its image is not
      // decoded yet when the editor is laid out narrower.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(rig.controller.state, TomPdfEditorState.open);
      expect(rig._decodes, isNotEmpty, reason: 'a render in flight');
      await tester.binding.setSurfaceSize(const Size(700, 600));
      await tester.pump();
      await rig.settle(tester);
      expect(rig.view(tester).hasCurrentImages(0), isTrue);
    });
  });

  group('PDF-NARROW the editor at its narrowest', () {
    // ForgePdfEditor.sizeHints.minSize: the narrowest the shell lays an
    // editor out at. Overflow errors are not suppressed: one fails the test.
    const narrow = Size(240, 200);
    const narrowTall = Size(240, 480);

    testWidgets('PDF-NARROW-1: opening, the password panel and could not '
        'open fit 240 x 200', (tester) async {
      final opening = _Rig(_textDoc());
      await tester.binding.setSurfaceSize(narrow);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TomPdfEditor(controller: opening.controller)),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'opening');

      final locked = _Rig(_textDoc(password: 'sesame', securityRevision: 3));
      await locked.pump(tester, size: narrow);
      expect(locked.controller.state, TomPdfEditorState.password);
      expect(tester.takeException(), isNull, reason: 'password');

      final missing = _Rig(
        _textDoc(),
        status: const FakePdfEngineStatus.problem(
          'Engine version mismatch: /nowhere/libengine is chromium/7000',
        ),
      );
      await missing.pump(tester, size: narrow);
      expect(missing.controller.state, TomPdfEditorState.failed);
      expect(tester.takeException(), isNull, reason: 'failed');
    });

    testWidgets('PDF-NARROW-2: the open document with its zoom, annotation '
        'and find bars fits 240 x 200', (tester) async {
      final rig = _Rig(_textDoc());
      await rig.pump(tester, size: narrow);
      expect(rig.controller.state, TomPdfEditorState.open);
      rig.controller.showFind();
      await rig.settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PDF-NARROW-3: the read-only, encrypted, deleted and conflict '
        'bars fit 240 px wide', (tester) async {
      final readOnly = _Rig(_textDoc(), readOnlyFile: true);
      await readOnly.pump(tester, size: narrowTall);
      expect(readOnly.controller.isReadOnly, isTrue);
      expect(tester.takeException(), isNull, reason: 'read-only');

      final encrypted = _Rig(_textDoc(password: 'sesame', securityRevision: 3));
      await encrypted.pump(tester, size: narrowTall);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-field')),
        'sesame',
      );
      await tester.tap(find.text('Open'));
      await encrypted.settle(tester);
      expect(encrypted.controller.state, TomPdfEditorState.open);
      expect(tester.takeException(), isNull, reason: 'encrypted');

      final deleted = _Rig(_textDoc());
      await deleted.pump(tester, size: narrowTall);
      deleted.files.delete(_path);
      await tester.runAsync(deleted.controller.checkExternal);
      await deleted.settle(tester);
      expect(deleted.controller.isDeleted, isTrue);
      expect(tester.takeException(), isNull, reason: 'deleted');

      final conflict = _Rig(_textDoc());
      await conflict.pump(tester, size: narrowTall);
      conflict.controller.pushEdit(_NoopEdit());
      conflict.files.write(_path, utf8.encode('%PDF-theirs'));
      await tester.runAsync(conflict.controller.save);
      await conflict.settle(tester);
      expect(conflict.controller.conflict, isNotNull);
      expect(tester.takeException(), isNull, reason: 'conflict');
    });
    testWidgets('PDF-NARROW-4: the trail line of a Flutter error names the '
        'widget it came from', (tester) async {
      final seen = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = seen.add;
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 50,
              child: Row(children: [SizedBox(width: 80, height: 10)]),
            ),
          ),
        ),
      );
      FlutterError.onError = previous;
      expect(seen, isNotEmpty);
      final line = pdfErrorSummary(seen.first);
      expect(line, startsWith('A RenderFlex overflowed by 30 pixels'));
      expect(line, contains('library: rendering library'));
      expect(line, contains('Row'), reason: line);
      expect(line, isNot(contains('\n')));
    });
  });
}

class _NoopEdit implements TomPdfEdit {
  @override
  String get label => 'noop';

  @override
  Future<void> apply(TomPdfEditorController controller) async {}

  @override
  Future<void> revert(TomPdfEditorController controller) async {}
}
