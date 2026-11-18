// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The pdf.js view in a real macOS window (WKWebView, the workspace's fork)
/// in each of its three modes, over the tom_forge samples: a highlight, ink
/// and free text made with pdf.js's own editors, a form field filled, saved
/// through the bridge and the local server, reopened; the saved file read
/// back with PDFium. Also the time to open a document right after a large
/// one.
///
///   cd example && flutter test integration_test/pdfjs_test.dart -d macos
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/io.dart';
import 'package:tom_pdf_editor/pdfium.dart';
import 'package:tom_pdf_editor/pdfjs.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_editor_example/main.dart';

final _samples =
    Platform.environment['TOM_PDF_SAMPLES'] ??
    '${Directory.current.path}/../../../../_ai/quests/tom_forge/ideas/'
        'office_and_pdf_integration_prototype/samples/files';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('pdfjs-mac-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> waitFor(
    WidgetTester tester,
    Future<bool> Function() done, {
    required String what,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!await done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String copy(String name) {
    final target = '${dir.path}/$name';
    File('$_samples/$name').copySync(target);
    return target;
  }

  Future<(TomPdfJsController, TomPdfJsViewState)> open(
    WidgetTester tester,
    String path,
    TomPdfJsMode mode,
  ) async {
    final c = TomPdfJsController(DesktopPdfHost(path), mode: mode);
    await tester.pumpWidget(PdfJsExampleApp(controller: c));
    await waitFor(
      tester,
      () async => c.state == TomPdfJsState.open,
      what: '${mode.name}: open',
    );
    return (c, tester.state<TomPdfJsViewState>(find.byType(TomPdfJsView)));
  }

  Future<bool> js(TomPdfJsViewState view, String source) async =>
      await view.evaluate(source) == true;

  Future<void> saved(
    WidgetTester tester,
    TomPdfJsController c,
    String what,
  ) async {
    final before = c.generation;
    await c.save();
    expect(c.conflict, isNull, reason: what);
    await waitFor(
      tester,
      () async => c.generation > before && c.state == TomPdfJsState.open,
      what: '$what: reopened after the save',
    );
    expect(c.isDirty, isFalse, reason: what);
  }

  for (final mode in TomPdfJsMode.values) {
    testWidgets('PDFJS-MAC-${mode.name}: pdf-text takes a highlight, ink and '
        'free text, saves and reopens with them; pdf-form is filled, saved '
        'and reopened', (tester) async {
      final path = copy('pdf-text.pdf');
      final original = File(path).readAsBytesSync();
      final (c, view) = await open(tester, path, mode);
      expect(c.pageCount, 43);
      if (mode != TomPdfJsMode.components) {
        // integrated hides what the shell does itself; full shows it.
        for (final id in ['printButton', 'downloadButton', 'findbar']) {
          final hidden = await js(
            view,
            'getComputedStyle(document.getElementById("$id")).display '
            '=== "none"',
          );
          expect(
            hidden,
            mode == TomPdfJsMode.integrated || id == 'findbar',
            reason: '${mode.name}: #$id',
          );
        }
        expect(
          await js(
            view,
            'getComputedStyle(document.getElementById("editorInkButton"))'
            '.display !== "none"',
          ),
          isTrue,
          reason: 'the annotation tools stay',
        );
      }
      const page = '.page[data-page-number="1"]';
      await waitFor(
        tester,
        () => js(view, '!!document.querySelector(\'$page .textLayer span\')'),
        what: 'the text layer of page 1',
      );

      // Highlight: the tool chosen, text selected, then pdf.js's own
      // "highlight selection" (what a mouse-up over text does).
      await c.setTool(TomPdfJsTool.highlight);
      await tester.pump(const Duration(milliseconds: 300));
      expect(await js(view, 'forgeBridge.test.selectText(1, 40)'), isTrue);
      await js(view, 'forgeBridge.test.highlightSelection(); true');
      await waitFor(
        tester,
        () async => c.canUndo,
        what: 'the highlight in the history',
      );

      // Ink: one stroke with the pointer.
      await c.setTool(TomPdfJsTool.ink);
      await waitFor(
        tester,
        () => js(
          view,
          '!!document.querySelector(\'$page .annotationEditorLayer\')',
        ),
        what: 'the editor layer',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await js(view, 'forgeBridge.test.pointer(1, "pointerdown", 0.2, 0.55)');
      for (var i = 1; i <= 10; i++) {
        await js(
          view,
          'forgeBridge.test.pointer(1, "pointermove", ${0.2 + i * 0.03}, '
          '${0.55 + (i.isEven ? 0.02 : -0.02)})',
        );
      }
      await js(view, 'forgeBridge.test.pointer(1, "pointerup", 0.5, 0.55)');
      await tester.pump(const Duration(milliseconds: 300));

      // Free text: a click places it, then text is typed and committed.
      await c.setTool(TomPdfJsTool.freeText);
      await tester.pump(const Duration(milliseconds: 300));
      await js(view, 'forgeBridge.test.pointer(1, "pointerdown", 0.6, 0.2)');
      await js(view, 'forgeBridge.test.pointer(1, "pointerup", 0.6, 0.2)');
      await waitFor(
        tester,
        () => js(view, '!!document.querySelector(".freeTextEditor .internal")'),
        what: 'the free text editor',
      );
      await js(view, 'forgeBridge.test.typeFreeText("pdf.js free text")');
      await c.setTool(TomPdfJsTool.none);
      await waitFor(
        tester,
        () => js(
          view,
          '(() => { const t = forgeBridge.test.storage().types; '
          'return [3, 9, 15].every((k) => t.includes(k)); })()',
        ),
        what: 'highlight, ink and free text in the annotation storage',
      );
      expect(c.isDirty, isTrue);

      await saved(tester, c, '${mode.name} pdf-text');
      final bytes = File(path).readAsBytesSync();
      expect(
        bytes.sublist(0, original.length),
        original,
        reason: 'pdf.js saved incrementally',
      );
      // PDFium reads them from the file.
      final engine = await PdfiumEngine.acquire(
        const TomPdfiumLocator().locate().path!,
      );
      final doc = (await engine.open(path)).info!.handle;
      final subtypes = {
        for (final a in await engine.annotations(doc, 0)) a.subtype,
      };
      await engine.close(doc);
      expect(
        subtypes,
        containsAll([3, 9, 15]),
        reason: 'FreeText, Highlight, Ink',
      );
      // pdf.js shows them again after the reopen.
      await waitFor(
        tester,
        () => js(
          view,
          'document.querySelectorAll(\'$page :is(.highlightAnnotation, '
          '.inkAnnotation, .freeTextAnnotation, .highlightEditor, '
          '.inkEditor, .freeTextEditor)\').length >= 3',
        ),
        what: 'the saved annotations shown after the reopen',
      );

      // A form: a text field filled and a checkbox ticked.
      final formPath = copy('pdf-form.pdf');
      final (f, formView) = await open(tester, formPath, mode);
      await waitFor(
        tester,
        () => js(
          formView,
          '!!document.querySelector(\'.annotationLayer [name="Text1"]\')',
        ),
        what: 'the form fields',
      );
      expect(
        await js(formView, 'forgeBridge.test.fillField("Text1", "pdf.js 42")'),
        isTrue,
      );
      await js(
        formView,
        'document.querySelector(\'.annotationLayer input[type="checkbox"]\')'
        '.click(); true',
      );
      await waitFor(tester, () async => f.isDirty, what: 'the form modified');
      await saved(tester, f, '${mode.name} pdf-form');
      final formDoc = (await engine.open(formPath)).info!.handle;
      final fields = await engine.formFields(formDoc, 0);
      await engine.close(formDoc);
      await engine.release();
      expect(fields.firstWhere((x) => x.name == 'Text1').value, 'pdf.js 42');
      expect(
        fields.firstWhere((x) => x.type == PdfFieldType.checkbox).checked,
        isTrue,
      );
      await waitFor(
        tester,
        () => js(
          formView,
          'document.querySelector(\'.annotationLayer [name="Text1"]\')'
          '?.value === "pdf.js 42"',
        ),
        what: 'the saved value shown after the reopen',
      );
      await f.close();
      await c.close();
    });
  }

  testWidgets('PDFJS-MAC-FONTS: the vendored Liberation Sans (OFL, in place '
      'of pdf.js\'s GPL copy) loads and renders a non-embedded Helvetica', (
    tester,
  ) async {
    final (c, view) = await open(
      tester,
      copy('pdf-text.pdf'),
      TomPdfJsMode.components,
    );
    final requests = <TomContentRequest>[];
    c.site!.onRequest = requests.add;
    // A one-page PDF whose Helvetica is not embedded; pdf.js told not to use
    // the system's fonts, so it takes its standard fonts from the site.
    final result = await view.evaluateAsync(r'''
      const src = "%PDF-1.4\n1 0 obj <</Type/Catalog/Pages 2 0 R>> endobj\n"
        + "2 0 obj <</Type/Pages/Kids[3 0 R]/Count 1>> endobj\n"
        + "3 0 obj <</Type/Page/Parent 2 0 R/MediaBox[0 0 300 60]"
        + "/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>> endobj\n"
        + "4 0 obj <</Type/Font/Subtype/Type1/BaseFont/Helvetica>> endobj\n"
        + "5 0 obj <</Length 47>> stream\n"
        + "BT /F1 24 Tf 10 20 Td (Liberation 2.1.5) Tj ET\n"
        + "endstream endobj\ntrailer <</Root 1 0 R>>\n%%EOF\n";
      const lib = globalThis.pdfjsLib;
      const task = lib.getDocument({
        data: new TextEncoder().encode(src),
        useSystemFonts: false,
        standardFontDataUrl: new URL("../../web/standard_fonts/", location.href).href,
      });
      const doc = await task.promise;
      const page = await doc.getPage(1);
      const viewport = page.getViewport({ scale: 2 });
      const canvas = document.createElement("canvas");
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      const ctx = canvas.getContext("2d");
      await page.render({ canvasContext: ctx, canvas, viewport }).promise;
      const px = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let dark = 0;
      for (let i = 0; i < px.length; i += 4) if (px[i + 3] > 128 && px[i] < 100) dark++;
      const text = (await page.getTextContent()).items.map((t) => t.str).join("");
      await task.destroy();
      return { dark, text };
    ''');
    final r = (result! as Map).cast<String, Object?>();
    expect(r['text'], 'Liberation 2.1.5');
    expect((r['dark']! as num).toInt(), greaterThan(500), reason: 'drawn');
    expect(
      requests.where(
        (q) =>
            q.path.endsWith('standard_fonts/LiberationSans-Regular.ttf') &&
            q.status == 200,
      ),
      isNotEmpty,
      reason: 'pdf.js fetched the vendored Liberation Sans',
    );
    await c.close();
  });

  testWidgets('PDFJS-MAC-SECOND: a document opens quickly right after the '
      '16.8 MB pdf-long', (tester) async {
    final long = copy('pdf-long.pdf');
    final text = copy('pdf-text.pdf');
    final (c, view) = await open(tester, long, TomPdfJsMode.components);
    expect(c.pageCount, 4211);
    // Somewhere deep in it, so range requests are under way.
    await view.evaluate(
      'forgeBridge.test.adapter.zoom("page-fit"); '
      'document.getElementById("viewerContainer").scrollTop = 1e7; true',
    );
    await tester.pump(const Duration(seconds: 2));
    c.site!.mount('second', TomContentMount.file(text));
    final watch = Stopwatch()..start();
    await view.evaluate(
      'forgeBridge.open(${'"${c.site!.uriOf('second/pdf-text.pdf')}"'}); true',
    );
    await waitFor(
      tester,
      () async => c.pageCount == 43,
      what: 'the second document',
      timeout: const Duration(seconds: 90),
    );
    watch.stop();
    // ignore: avoid_print
    print(
      'PDFJS-MAC-SECOND: opened after pdf-long in '
      '${watch.elapsedMilliseconds} ms',
    );
    expect(watch.elapsedMilliseconds, lessThan(5000));
    await c.close();
  });
}
