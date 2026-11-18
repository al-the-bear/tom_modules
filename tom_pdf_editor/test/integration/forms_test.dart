// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Form filling on the real PDFium over the `pdf-form` sample (pdf.js's
/// `resetform.pdf`: six text fields, four checkboxes, a radio group, a combo
/// box, a list box, two push buttons): filled, undone, saved incrementally,
/// reopened; the saved values read by macOS PDFKit (Preview's engine).
/// Tagged `pdfium`.
@Tags(['pdfium'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_pdf_editor/io.dart';
import 'package:tom_pdf_editor/pdfium.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';

import '../samples.dart';

/// The widgets PDFKit reads on page 0 of [path], as `name=value` (text
/// fields) and `name:on` / `name:off` (buttons), or `null` when it refuses
/// the file.
List<String>? pdfKitFields(String path) {
  final r = Process.runSync('swift', [
    '-e',
    'import PDFKit; '
        'guard let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else { print("refused"); exit(0) }; '
        'let p = d.page(at: 0)!; '
        'print(p.annotations.filter { \$0.type == "Widget" }.map { a in '
        'a.widgetFieldType == .text ? (a.fieldName ?? "?") + "=" + (a.widgetStringValue ?? "") '
        ': (a.fieldName ?? "?") + ":" + (a.buttonWidgetState == .onState ? "on" : "off") }.joined(separator: "|"))',
    path,
  ]);
  final out = '${r.stdout}'.trim();
  if (out == 'refused') return null;
  return out.isEmpty ? [] : out.split('|');
}

PdfRect _centre(PdfFormField f) {
  final x = (f.rect.left + f.rect.right) / 2;
  final y = (f.rect.top + f.rect.bottom) / 2;
  return PdfRect(x, y, x, y);
}

void main() {
  final library = const TomPdfiumLocator().locate();
  final skip = library.isUsable ? samplesSkipReason : library.message;
  late PdfiumEngine engine;
  late Directory dir;

  setUpAll(() async {
    if (skip != null) return;
    engine = await PdfiumEngine.acquire(library.path!);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await engine.release();
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('pdf-form-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('PDF-FORM-1: a text field and a checkbox are filled, the changes '
      'reported once committed, undone, saved and reopened', () async {
    final source = '${dir.path}/pdf-form.pdf';
    File(samplePath('pdf-form.pdf')).copySync(source);
    final info = (await engine.open(source)).info!;
    expect(info.formType, PdfFormType.acroForm);
    final doc = info.handle;
    final fields = await engine.formFields(doc, 0);
    final types = fields.map((f) => f.type).toSet();
    expect(
      types,
      containsAll([
        PdfFieldType.text,
        PdfFieldType.checkbox,
        PdfFieldType.radio,
        PdfFieldType.comboBox,
        PdfFieldType.listBox,
        PdfFieldType.pushButton,
      ]),
    );
    final texts = fields.where((f) => f.type == PdfFieldType.text).toList();
    final boxes = fields.where((f) => f.type == PdfFieldType.checkbox).toList();
    final text = texts.first;
    final second = texts[1];
    final box = boxes.first;
    expect(
      (await engine.formFieldAt(
        doc,
        0,
        _centre(text).left,
        _centre(text).top,
      ))?.name,
      text.name,
    );

    // Click into the text field and type: nothing committed yet.
    var r = await engine.formClick(
      doc,
      0,
      _centre(text).left,
      _centre(text).top,
    );
    expect(r.handled, isTrue);
    expect(r.focused?.name, text.name);
    expect(r.changes, isEmpty);
    r = await engine.formKey(doc, PdfFormKey.selectAll);
    r = await engine.formText(doc, 'Tom 42');
    expect(r.dirtyPages, contains(0), reason: 'FFI_Invalidate named the page');
    expect(r.changes, isEmpty);
    // The field's own undo takes back typing while it has the focus.
    r = await engine.formText(doc, 'x');
    r = await engine.formUndo(doc);
    expect(r.handled, isTrue);
    // Tab moves to the next field and commits the text.
    r = await engine.formKey(doc, PdfFormKey.tab);
    expect(r.changes, [
      PdfFormChange(0, text.name, PdfFieldType.text, text.value, 'Tom 42'),
    ]);
    expect(r.focused, isNotNull);
    r = await engine.formKillFocus(doc);
    expect(r.focused, isNull);
    expect(r.changes, isEmpty, reason: '${second.name} was not changed');

    // A click toggles the checkbox: one change at once.
    r = await engine.formClick(doc, 0, _centre(box).left, _centre(box).top);
    expect(r.changes, [
      PdfFormChange(
        0,
        box.name,
        PdfFieldType.checkbox,
        box.checked ? 'on' : 'off',
        box.checked ? 'off' : 'on',
      ),
    ]);
    await engine.formKillFocus(doc);

    // A radio button: the group's button that is on.
    final radios = fields.where((f) => f.type == PdfFieldType.radio).toList();
    final radio = radios.firstWhere((f) => !f.checked);
    r = await engine.formClick(doc, 0, _centre(radio).left, _centre(radio).top);
    expect(r.changes.single.type, PdfFieldType.radio);
    expect(r.changes.single.after, '${radio.index}');
    final radioChange = r.changes.single;
    await engine.formKillFocus(doc);

    // A combo box, a list box and a push button are not filled.
    for (final t in [
      PdfFieldType.comboBox,
      PdfFieldType.listBox,
      PdfFieldType.pushButton,
    ]) {
      final f = fields.firstWhere((f) => f.type == t);
      r = await engine.formClick(doc, 0, _centre(f).left, _centre(f).top);
      expect(r.handled, isFalse, reason: t.name);
      expect(r.focused, isNull, reason: t.name);
    }

    // Undo and redo through formSetValue.
    await engine.formSetValue(doc, 0, text.name, PdfFieldType.text, text.value);
    await engine.formSetValue(
      doc,
      0,
      radio.name,
      PdfFieldType.radio,
      radioChange.before,
    );
    var now = await engine.formFields(doc, 0);
    expect(now.firstWhere((f) => f.name == text.name).value, text.value);
    if (radioChange.before.isNotEmpty) {
      expect(
        now
            .where((f) => f.name == radio.name && f.checked)
            .map((f) => '${f.index}'),
        [radioChange.before],
      );
    }
    await engine.formSetValue(doc, 0, text.name, PdfFieldType.text, 'Tom 42');
    now = await engine.formFields(doc, 0);
    expect(now.firstWhere((f) => f.name == text.name).value, 'Tom 42');
    expect(now.firstWhere((f) => f.name == box.name).checked, !box.checked);

    // Saved incrementally, reopened.
    final target = '${dir.path}/filled.pdf';
    expect(await engine.saveIncremental(doc, target), isNull);
    await engine.close(doc);
    final original = File(source).readAsBytesSync();
    final saved = File(target).readAsBytesSync();
    expect(saved.sublist(0, original.length), original, reason: 'not a prefix');
    final reopened = (await engine.open(target)).info!;
    final back = await engine.formFields(reopened.handle, 0);
    expect(back.firstWhere((f) => f.name == text.name).value, 'Tom 42');
    expect(back.firstWhere((f) => f.name == box.name).checked, !box.checked);
    await engine.close(reopened.handle);

    if (Platform.isMacOS) {
      final kit = pdfKitFields(target);
      expect(kit, isNotNull, reason: 'PDFKit refuses the saved file');
      expect(kit, contains('${text.name}=Tom 42'));
      expect(kit, contains('${box.name}:${box.checked ? 'off' : 'on'}'));
    }
  }, skip: skip);
}
