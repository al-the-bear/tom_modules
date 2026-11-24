// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The pdf.js view's WebKit content process killed under an open document:
/// the tab says so, and reload brings the document back. Also: closing the
/// controller after its view has left the tree reports nothing.
///
///   cd example && flutter test integration_test/pdfjs_content_process_test.dart -d macos
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tom_pdf_pdfjs/tom_pdf_pdfjs.dart';
import 'package:tom_pdf_pdfjs_example/main.dart';

final _samples =
    Platform.environment['TOM_PDF_SAMPLES'] ??
    '${Directory.current.path}/../../../../_ai/quests/tom_forge/ideas/'
        'office_and_pdf_integration_prototype/samples/files';

/// The pids of every WebKit content process now running.
Set<int> _webContent() {
  final r = Process.runSync('ps', ['-axo', 'pid=,comm=']);
  return {
    for (final line in LineSplitter.split('${r.stdout}'))
      if (line.contains('com.apple.WebKit.WebContent'))
        int.parse(line.trim().split(RegExp(r'\s+')).first),
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('PDFJS-MAC-CRASH-1: the content process killed under pdf-text: '
      'the tab says so, reload brings the document back', (tester) async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() {
      FlutterError.onError = previous;
      expect(reported.map((d) => d.exceptionAsString()), isEmpty);
    });
    final before = _webContent();
    final c = TomPdfJsController(DesktopPdfHost('$_samples/pdf-text.pdf'));
    await tester.pumpWidget(PdfJsExampleApp(controller: c));
    await waitFor(
      tester,
      () => c.state == TomPdfJsState.open,
      what: 'pdf-text open',
    );
    expect(c.pageCount, 43);
    final mine = _webContent().difference(before);
    expect(mine, isNotEmpty, reason: 'a content process of this view');
    for (final p in mine) {
      Process.killPid(p, ProcessSignal.sigkill);
    }
    await waitFor(
      tester,
      () => c.state == TomPdfJsState.failed,
      what: 'the tab to notice the ended content process',
    );
    expect(c.failure, contains('web content process ended'));
    // The failure is shown without the webview: let the old one leave.
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await c.reload();
    await waitFor(
      tester,
      () => c.state == TomPdfJsState.open,
      what: 'the document back after reload',
    );
    expect(c.pageCount, 43);
    expect(c.failure, isNull);
    await c.close();
  });

  testWidgets('PDFJS-MAC-CLOSE-1: closing after the view has left the tree '
      'reports nothing', (tester) async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      final c = TomPdfJsController(DesktopPdfHost('$_samples/pdf-text.pdf'));
      await tester.pumpWidget(PdfJsExampleApp(controller: c));
      await waitFor(
        tester,
        () => c.state == TomPdfJsState.open,
        what: 'pdf-text open',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await c.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.state, TomPdfJsState.closed);
    } finally {
      FlutterError.onError = previous;
    }
    expect(reported.map((d) => d.exceptionAsString()), isEmpty);
  });

  testWidgets('PDFJS-MAC-CLOSE-2: closing after a failed open (the webview '
      'gone with the failure) reports nothing', (tester) async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      final c = TomPdfJsController(
        DesktopPdfHost('$_samples/damaged-pdf-truncated.pdf'),
      );
      await tester.pumpWidget(PdfJsExampleApp(controller: c));
      await waitFor(
        tester,
        () => c.state == TomPdfJsState.failed,
        what: 'the damaged file refused',
      );
      final end = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await c.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.state, TomPdfJsState.closed);
    } finally {
      FlutterError.onError = previous;
    }
    expect(reported.map((d) => d.exceptionAsString()), isEmpty);
  });
}
