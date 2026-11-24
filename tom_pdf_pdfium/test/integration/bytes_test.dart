// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// A PDF without a path on this machine, on the real PDFium: opened from its
/// bytes, annotated, saved incrementally into memory and written through
/// the file access of a (memory) file system, reopened from the saved bytes.
/// Tagged `pdfium`.
@Tags(['pdfium'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_system/tom_file_system.dart' show TomMemoryFileSystem;
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfium/tom_pdf_pdfium.dart';

import '../samples.dart';

class _Host implements TomPdfEditorHost {
  _Host(this.filePath, this.files);

  @override
  final String filePath;

  @override
  final TomBinaryFiles files;

  @override
  String get name => filePath.split('/').last;

  @override
  String get authorName => 'Test';

  @override
  TomPdfiumLibrary get engineStatus => const TomPdfiumLocator().locate();

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

  test('PDF-BYTES-1: the engine opens bytes and saves into memory; the '
      'original bytes stay a prefix and the saved bytes reopen', () async {
    final engine = await PdfiumEngine.acquire(library.path!);
    addTearDown(engine.release);
    final original = File(samplePath('pdf-text.pdf')).readAsBytesSync();
    final info = (await engine.openBytes(original)).info!;
    expect(info.pageCount, 43);
    await engine.addAnnotation(
      info.handle,
      0,
      const PdfAnnotation(
        id: 'b1',
        kind: PdfAnnotationKind.note,
        rect: PdfRect(50, 50, 70, 70),
        contents: 'from bytes',
      ),
    );
    final saved = await engine.saveIncrementalBytes(info.handle);
    await engine.close(info.handle);
    expect(saved.sublist(0, original.length), original);
    // The cross-reference fix is applied to the bytes as to a file.
    final tail = String.fromCharCodes(saved.sublist(original.length));
    if (tail.contains('/XRef') || tail.contains('/W[')) {
      expect(tail, contains('/Type/XRef'));
    }
    final again = (await engine.openBytes(saved)).info!;
    final notes = await engine.annotations(again.handle, 0);
    expect(notes.map((a) => a.contents), contains('from bytes'));
    // A full copy without security, also into memory.
    final copy = await engine.saveCopyBytes(again.handle, removeSecurity: true);
    expect(String.fromCharCodes(copy.sublist(0, 5)), '%PDF-');
    await engine.close(again.handle);
    expect(
      (await engine.openBytes(Uint8List.fromList([1, 2, 3]))).error,
      PdfOpenError.format,
    );
  }, skip: skip);

  test('PDF-BYTES-2: the controller over a file system without local paths '
      'opens, saves an annotation through it, reopens; a changed file is a '
      'conflict', () async {
    final memory = TomMemoryFileSystem();
    await memory.write(
      memory.uriOf('remote/pdf-text.pdf'),
      File(samplePath('pdf-text.pdf')).readAsBytesSync(),
    );
    final files = TomFileSystemBinaryFiles(memory);
    final c = TomPdfEditorController(_Host('remote/pdf-text.pdf', files));
    addTearDown(c.dispose);
    await c.open();
    expect(c.state, TomPdfEditorState.open, reason: '${c.failure}');
    await c.addNote(0, 60, 60, 'saved remotely');
    expect(c.isDirty, isTrue);
    await c.save();
    expect(c.conflict, isNull);
    expect(c.isDirty, isFalse);
    expect(c.generation, 1, reason: 'reopened from the saved bytes');
    final notes = await c.loadAnnotations(0);
    expect(notes.map((a) => a.contents), contains('saved remotely'));
    expect(await files.removeTemporaryFiles('remote/pdf-text.pdf'), isEmpty);

    // Someone else writes the file: the next save is a conflict.
    await c.addNote(0, 90, 60, 'mine');
    await memory.write(
      memory.uriOf('remote/pdf-text.pdf'),
      File(samplePath('pdf-text.pdf')).readAsBytesSync(),
    );
    await c.save();
    expect(c.conflict, isNotNull);
    final copy = await c.saveAsCopy();
    expect(copy, 'remote/pdf-text (copy).pdf');
    expect(await memory.exists(memory.uriOf(copy!)), isTrue);
  }, skip: skip);
}
