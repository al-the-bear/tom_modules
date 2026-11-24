// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The editor in a real macOS window on the real PDFium library, over the
/// tom_forge samples: open, scroll, zoom, search and copy.
///
///   cd example && flutter test integration_test -d macos
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfium_example/main.dart';

final _samples =
    Platform.environment['TOM_PDF_SAMPLES'] ??
    '${Directory.current.path}/../../../../_ai/quests/tom_forge/ideas/'
        'office_and_pdf_integration_prototype/samples/files';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() done, {
    String what = 'condition',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<TomPdfEditorController> openSample(
    WidgetTester tester,
    String name,
  ) async {
    final path = '$_samples/$name';
    expect(File(path).existsSync(), isTrue, reason: path);
    final c = TomPdfEditorController(DesktopPdfHost(path));
    await tester.pumpWidget(PdfExampleApp(controller: c));
    await c.open();
    await tester.pump();
    return c;
  }

  PdfPageViewState view(WidgetTester tester) =>
      tester.state<PdfPageViewState>(find.byType(PdfPageView));

  int pageInView(WidgetTester tester) {
    final v = view(tester);
    return v.layout.pageAt(v.vertical.offset + 20);
  }

  testWidgets('PDF-MAC-1: pdf-text opens, scrolls, zooms, searches and '
      'copies', (tester) async {
    final c = await openSample(tester, 'pdf-text.pdf');
    await waitFor(
      tester,
      () => c.state == TomPdfEditorState.open,
      what: 'open',
    );
    await waitFor(
      tester,
      () => view(tester).hasCurrentImages(0),
      what: 'page 1 rendered',
    );

    // Scroll.
    final v = view(tester);
    v.vertical.jumpTo(v.layout.pageTop(20));
    await tester.pump();
    await waitFor(
      tester,
      () => view(tester).hasCurrentImages(20),
      what: 'page 21 rendered',
    );

    // Zoom to 400 % (tiles) and back.
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    expect(view(tester).widget.zoom, 400);
    final page = pageInView(tester);
    await waitFor(
      tester,
      () => view(tester).hasCurrentImages(page),
      what: 'page at 400 %',
    );
    await tester.tap(find.text('Fit width'));
    await tester.pump();

    // Search.
    await tester.tap(find.byTooltip('Find'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('pdf-find-field')),
      'reasoning',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(
      tester,
      () => !c.searching && c.hits.isNotEmpty,
      what: 'search',
    );
    expect(c.hits.length, greaterThan(20));
    expect(find.textContaining('1 / '), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    final hit = c.hits[c.currentHit];
    expect(pageInView(tester), inInclusiveRange(hit.page - 1, hit.page));

    // Select the hit's word and copy it with Cmd+C.
    final r = hit.rects.first;
    await c.selectAround(
      hit.page,
      (r.left + r.right) / 2,
      (r.top + r.bottom) / 2,
      line: false,
    );
    await tester.pump();
    await tester.tap(find.byType(PdfPageView), warnIfMissed: false);
    await c.selectAround(
      hit.page,
      (r.left + r.right) / 2,
      (r.top + r.bottom) / 2,
      line: false,
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump(const Duration(milliseconds: 300));
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clip?.text?.toLowerCase(), 'reasoning');
    await c.close();
  });

  testWidgets('PDF-MAC-2: pdf-scan renders and says it has no text layer', (
    tester,
  ) async {
    final c = await openSample(tester, 'pdf-scan.pdf');
    await waitFor(
      tester,
      () => c.hasTextLayer != null,
      what: 'text layer check',
    );
    expect(c.hasTextLayer, isFalse);
    await waitFor(
      tester,
      () => view(tester).hasCurrentImages(0),
      what: 'scan rendered',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('no text layer'), findsOneWidget);
    await c.close();
  });

  testWidgets('PDF-MAC-3: pdf-long scrolls to a far page', (tester) async {
    final c = await openSample(tester, 'pdf-long.pdf');
    await waitFor(
      tester,
      () => c.state == TomPdfEditorState.open,
      what: 'open',
    );
    expect(find.text('4211 pages'), findsOneWidget);
    final v = view(tester);
    v.vertical.jumpTo(v.layout.pageTop(4000));
    await tester.pump();
    await waitFor(
      tester,
      () => view(tester).hasCurrentImages(4000),
      what: 'page 4001',
    );
    await c.close();
  });

  testWidgets('PDF-MAC-4: pdf-encrypted opens with its password', (
    tester,
  ) async {
    final c = await openSample(tester, 'pdf-encrypted.pdf');
    await waitFor(
      tester,
      () => c.state == TomPdfEditorState.password,
      what: 'password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('pdf-password-field')),
      'ELXRTQWS',
    );
    await tester.tap(find.text('Open'));
    await waitFor(
      tester,
      () => c.state == TomPdfEditorState.open,
      what: 'open',
    );
    await waitFor(
      tester,
      () => view(tester).hasCurrentImages(0),
      what: 'rendered',
    );
    expect(c.canAnnotate, isFalse);
    await c.close();
  });
}
