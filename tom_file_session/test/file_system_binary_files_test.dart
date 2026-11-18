import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_system/tom_file_system.dart' show TomMemoryFileSystem;

void main() {
  late TomMemoryFileSystem memory;
  late TomFileSystemBinaryFiles files;

  setUp(() {
    memory = TomMemoryFileSystem();
    files = TomFileSystemBinaryFiles(memory);
  });

  Future<void> put(String path, String text) =>
      memory.write(memory.uriOf(path), Uint8List.fromList(utf8.encode(text)));

  Future<String?> get(String path) async {
    final bytes = await files.readBytes(path);
    return bytes == null ? null : utf8.decode(bytes);
  }

  test(
    'FSBF-1: bytes, revision and writable; none for a missing file',
    () async {
      await put('docs/a.pdf', '%PDF-a');
      expect(await get('docs/a.pdf'), '%PDF-a');
      final r = (await files.revisionOf('docs/a.pdf'))!;
      expect(r.size, 6);
      expect(await files.isWritable('docs/a.pdf'), isTrue);
      expect(await files.readBytes('docs/none.pdf'), isNull);
      expect(await files.revisionOf('docs/none.pdf'), isNull);
      expect(await files.isWritable('docs/none.pdf'), isFalse);
    },
  );

  test('FSBF-2: save over the unchanged file replaces it; the temporary '
      'file is gone', () async {
    await put('docs/a.pdf', '%PDF-a');
    final before = await files.revisionOf('docs/a.pdf');
    final r = await files.save('docs/a.pdf', utf8.encode('%PDF-b'), before);
    expect(r.replaced, isTrue);
    expect(await get('docs/a.pdf'), '%PDF-b');
    expect(r.revision!.size, 6);
    expect(await files.removeTemporaryFiles('docs/a.pdf'), isEmpty);
  });

  test(
    'FSBF-3: save over a changed file is a conflict that keeps the '
    'temporary file; keep mine forces it, Save as copy keeps it beside',
    () async {
      await put('docs/a.pdf', '%PDF-a');
      final before = await files.revisionOf('docs/a.pdf');
      await put('docs/a.pdf', '%PDF-theirs');
      final r = await files.save(
        'docs/a.pdf',
        utf8.encode('%PDF-mine'),
        before,
      );
      expect(r.replaced, isFalse);
      expect(r.revision!.size, 11);
      expect(await get('docs/a.pdf'), '%PDF-theirs');
      expect(await get(r.temporary), '%PDF-mine');
      final copy = await files.keepAsCopy(r.temporary, 'docs/a.pdf');
      expect(copy, 'docs/a (copy).pdf');
      expect(await get(copy), '%PDF-mine');

      final again = await files.save(
        'docs/a.pdf',
        utf8.encode('%PDF-mine2'),
        before,
      );
      expect(again.replaced, isFalse);
      final forced = await files.replace(
        'docs/a.pdf',
        again.temporary,
        null,
        force: true,
      );
      expect(forced.replaced, isTrue);
      expect(await get('docs/a.pdf'), '%PDF-mine2');
    },
  );

  test('FSBF-4: a file deleted since it was read is a conflict; a save where '
      'none was expected creates it; stale temporaries are removed', () async {
    await put('docs/a.pdf', '%PDF-a');
    final before = await files.revisionOf('docs/a.pdf');
    await memory.delete(memory.uriOf('docs/a.pdf'));
    final r = await files.save('docs/a.pdf', utf8.encode('%PDF-b'), before);
    expect(r.replaced, isFalse);
    expect(r.revision, isNull);
    final created = await files.save(
      'docs/new.pdf',
      utf8.encode('%PDF-n'),
      null,
    );
    expect(created.replaced, isTrue);
    expect(await get('docs/new.pdf'), '%PDF-n');
    await files.temporaryTarget('docs/new.pdf');
    expect(await files.removeTemporaryFiles('docs/new.pdf'), [
      'docs/.new.pdf.tom-save-1',
    ]);
    expect(await files.removeTemporaryFiles('docs/a.pdf'), [
      'docs/.a.pdf.tom-save-1',
    ]);
  });
}
