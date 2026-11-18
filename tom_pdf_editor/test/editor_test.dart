// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The editor against the fake engine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
    TomPdfiumLibrary? library,
  }) {
    files.write(_path, utf8.encode('%PDF-original'));
    if (readOnlyFile) files.readOnly.add(_path);
    engine = FakePdfEngine({_path: doc}, files: files);
    host = FakePdfEditorHost(
      filePath: _path,
      files: files,
      engine: engine,
      pdfium: library,
    );
    controller = TomPdfEditorController(host);
  }

  final files = MemoryBinaryFiles();
  late final FakePdfEngine engine;
  late final FakePdfEditorHost host;
  late final TomPdfEditorController controller;
  final copied = <String>[];

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TomPdfEditor(
            controller: controller,
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

    testWidgets('PDF-OPEN-2: the library missing or of another release shows '
        'in the tab', (tester) async {
      final rig = _Rig(
        _textDoc(),
        library: const TomPdfiumLibrary.problem(
          TomPdfiumProblem.versionMismatch,
          '/b/libpdfium.dylib',
          tag: 'chromium/7000',
        ),
      );
      await rig.pump(tester);
      expect(rig.controller.state, TomPdfEditorState.failed);
      expect(find.textContaining('PDFium version mismatch'), findsOneWidget);
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

  testWidgets('PDF-CLOSE-1: closing gives the engine share up', (tester) async {
    final rig = _Rig(_textDoc());
    await rig.pump(tester);
    await tester.runAsync(rig.controller.close);
    expect(rig.engine.releases, 1);
    expect(rig.engine.calls, contains('close 1'));
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
