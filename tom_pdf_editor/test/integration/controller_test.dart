// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The controller on the real engine and file access, over the samples.
/// Tagged `pdfium`.
@Tags(['pdfium'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/io.dart';
import 'package:tom_pdf_editor/pdfium.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';

import '../samples.dart';
import 'forms_test.dart' show pdfKitFields;

/// A desktop host: the real locator, engine and file access.
class _Host implements TomPdfEditorHost {
  _Host(this.filePath);

  @override
  final String filePath;

  final notices = <String>[];

  @override
  String get name => filePath.split('/').last;

  @override
  String get authorName => 'Test';

  @override
  TomBinaryFiles get files => const TomBinaryFileAccess();

  @override
  TomPdfiumLibrary get pdfium => const TomPdfiumLocator().locate();

  @override
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library) =>
      PdfiumEngine.acquire(library.path!);

  @override
  void notice(BuildContext context, String message, {required String kind}) {}

  @override
  void openLink(String url) {}

  @override
  void historyChanged() {}
}

void main() {
  final library = const TomPdfiumLocator().locate();
  final skip = library.isUsable ? samplesSkipReason : library.message;

  Future<TomPdfEditorController> open(
    String name, {
    List<String>? notices,
  }) async {
    final c = TomPdfEditorController(_Host(samplePath(name)));
    c.notices.listen((n) => notices?.add(n.$2));
    await c.open();
    return c;
  }

  Future<void> settled(TomPdfEditorController c) async {
    for (var i = 0; i < 100 && (c.searching || c.hasTextLayer == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('PDF-REAL-1: pdf-text: open, search streams hits, select a word and '
      'copy it', () async {
    final c = await open('pdf-text.pdf');
    expect(c.state, TomPdfEditorState.open);
    expect(c.info!.pageCount, 43);
    await settled(c);
    expect(c.hasTextLayer, isTrue);
    c.find('reasoning');
    await settled(c);
    expect(c.hits.length, greaterThan(20));
    expect(c.scrollRequest.value!.$1, 0);
    final hit = c.hits.first;
    final r = hit.rects.first;
    await c.selectAround(
      hit.page,
      (r.left + r.right) / 2,
      (r.top + r.bottom) / 2,
      line: false,
    );
    expect((await c.selectedText())!.toLowerCase(), 'reasoning');
    await c.close();
  }, skip: skip);

  test('PDF-REAL-2: pdf-scan has no text layer; search is refused', () async {
    final notices = <String>[];
    final c = await open('pdf-scan.pdf', notices: notices);
    await settled(c);
    expect(c.hasTextLayer, isFalse);
    expect(notices, contains(contains('no text layer')));
    c.showFind();
    expect(c.findVisible, isFalse);
    await c.close();
  }, skip: skip);

  test('PDF-REAL-3: pdf-long opens with all its pages; a search finds hits '
      'on far pages while running', () async {
    final watch = Stopwatch()..start();
    final c = await open('pdf-long.pdf');
    expect(c.info!.pageCount, 4211);
    expect(watch.elapsedMilliseconds, lessThan(5000));
    c.find('the', fromPage: 4000);
    for (var i = 0; i < 200 && c.hits.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.hits.first.page, greaterThanOrEqualTo(4000));
    c.hideFind();
    await c.close();
  }, skip: skip);

  test('PDF-REAL-4: pdf-encrypted asks for its password and then opens for '
      'viewing; annotations are off', () async {
    final c = await open('pdf-encrypted.pdf');
    expect(c.state, TomPdfEditorState.password);
    await c.answerPassword('wrong');
    expect(c.state, TomPdfEditorState.password);
    expect(c.passwordWrong, isTrue);
    await c.answerPassword(kEncryptedPassword);
    expect(c.state, TomPdfEditorState.open);
    expect(c.info!.encrypted, isTrue);
    expect(c.canAnnotate, isFalse);
    await c.close();
  }, skip: skip);
  test('PDF-REAL-5: pdf-form through the controller: a text field and a '
      'checkbox filled (one history entry each), one undone and redone, '
      'saved over the file, reopened; PDFKit reads the values', () async {
    final dir = Directory.systemTemp.createTempSync('pdf-form-real-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/pdf-form.pdf';
    File(samplePath('pdf-form.pdf')).copySync(path);
    final c = TomPdfEditorController(_Host(path));
    await c.open();
    addTearDown(c.dispose);
    expect(c.canFill, isTrue);
    final engine = c.engine!;
    final fields = await engine.formFields(c.info!.handle, 0);
    final text = fields.firstWhere((f) => f.type == PdfFieldType.text);
    final box = fields.firstWhere((f) => f.type == PdfFieldType.checkbox);
    double cx(PdfFormField f) => (f.rect.left + f.rect.right) / 2;
    double cy(PdfFormField f) => (f.rect.top + f.rect.bottom) / 2;

    expect(await c.formClick(0, cx(text), cy(text)), isTrue);
    await c.formKey(PdfFormKey.selectAll);
    await c.formText('Filled on mbp');
    expect(c.canUndo, isFalse, reason: 'not committed yet');
    expect(await c.formClick(0, cx(box), cy(box)), isTrue);
    // Two entries: the text (committed by the click elsewhere), the box.
    expect(c.undoLabel, 'Checkbox');
    expect(c.isDirty, isTrue);
    await c.undo();
    expect(c.undoLabel, 'Text field');
    var now = await engine.formFields(c.info!.handle, 0);
    expect(now.firstWhere((f) => f.name == box.name).checked, box.checked);
    expect(now.firstWhere((f) => f.name == text.name).value, 'Filled on mbp');
    await c.redo();
    now = await engine.formFields(c.info!.handle, 0);
    expect(now.firstWhere((f) => f.name == box.name).checked, !box.checked);

    final original = File(path).readAsBytesSync();
    await c.save();
    expect(c.conflict, isNull);
    expect(c.isDirty, isFalse);
    final saved = File(path).readAsBytesSync();
    expect(saved.sublist(0, original.length), original, reason: 'not a prefix');
    // Reopened after the save: the values are in the file.
    now = await c.engine!.formFields(c.info!.handle, 0);
    expect(now.firstWhere((f) => f.name == text.name).value, 'Filled on mbp');
    expect(now.firstWhere((f) => f.name == box.name).checked, !box.checked);
    if (Platform.isMacOS) {
      final kit = pdfKitFields(path);
      expect(kit, isNotNull, reason: 'PDFKit refuses the saved file');
      expect(kit, contains('${text.name}=Filled on mbp'));
      expect(kit, contains('${box.name}:${box.checked ? 'off' : 'on'}'));
    }
  }, skip: skip);
}
