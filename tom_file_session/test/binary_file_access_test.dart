@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_file_session/io.dart';

void main() {
  const access = TomBinaryFileAccess();
  late Directory dir;
  late String doc;

  setUp(() {
    dir = Directory('.dart_tool/test_scratch').absolute
      ..createSync(recursive: true);
    dir = dir.createTempSync('binary-');
    doc = '${dir.path}/report.docx';
    File(doc).writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDown(() {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+w', dir.path]);
    }
    dir.deleteSync(recursive: true);
  });

  group('BINARY-REV revisionOf', () {
    test('BINARY-REV-1: size, modification time and SHA-256', () async {
      final r = (await access.revisionOf(doc))!;
      expect(r.size, 4);
      expect(r.modified, File(doc).statSync().modified);
      // sha256 of 01 02 03 04
      expect(
        r.sha256,
        '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
      );
    });

    test('BINARY-REV-2: a change of the bytes changes the revision', () async {
      final before = (await access.revisionOf(doc))!;
      File(doc).writeAsBytesSync([1, 2, 3, 5]);
      final after = (await access.revisionOf(doc))!;
      expect(after.sameContent(before), isFalse);
      expect(after, isNot(before));
    });

    test('BINARY-REV-3: a touch keeps the content, changes the time', () async {
      final before = (await access.revisionOf(doc))!;
      File(doc).setLastModifiedSync(DateTime(2001));
      final after = (await access.revisionOf(doc))!;
      expect(after.sameContent(before), isTrue);
      expect(after, before, reason: 'equal revisions are equal content');
      expect(after.modified, isNot(before.modified));
    });

    test('BINARY-REV-4: no file, no revision', () async {
      expect(await access.revisionOf('${dir.path}/missing.pdf'), isNull);
      expect(await access.revisionOf(dir.path), isNull);
    });
  });

  group('BINARY-TMP temporaryTarget', () {
    test('BINARY-TMP-1: .<name>.tom-save-<n> in the same folder, each '
        'one new', () async {
      final a = await access.temporaryTarget(doc);
      final b = await access.temporaryTarget(doc);
      expect(a, '${dir.path}/.report.docx.tom-save-1');
      expect(b, '${dir.path}/.report.docx.tom-save-2');
      expect(File(a).existsSync(), isTrue);
    });

    test('BINARY-TMP-2: a folder that cannot be written throws', () async {
      if (Platform.isWindows) return;
      Process.runSync('chmod', ['a-w', dir.path]);
      await expectLater(
        access.temporaryTarget(doc),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('BINARY-REPLACE replace', () {
    test('BINARY-REPLACE-1: an unchanged original is replaced and the new '
        'revision returned', () async {
      final read = await access.revisionOf(doc);
      final temp = await access.temporaryTarget(doc);
      File(temp).writeAsBytesSync([9, 9]);
      final result = await access.replace(doc, temp, read);
      expect(result.outcome, TomBinaryReplaceOutcome.replaced);
      expect(File(doc).readAsBytesSync(), [9, 9]);
      expect(File(temp).existsSync(), isFalse);
      expect(result.revision, await access.revisionOf(doc));
    });

    test('BINARY-REPLACE-2: a changed original is a conflict; nothing written, '
        'the temporary file kept', () async {
      final read = await access.revisionOf(doc);
      File(doc).writeAsBytesSync([7, 7, 7]);
      final temp = await access.temporaryTarget(doc);
      File(temp).writeAsBytesSync([9, 9]);
      final result = await access.replace(doc, temp, read);
      expect(result.outcome, TomBinaryReplaceOutcome.conflict);
      expect(result.replaced, isFalse);
      expect(File(doc).readAsBytesSync(), [7, 7, 7]);
      expect(File(temp).readAsBytesSync(), [9, 9]);
      expect(result.revision!.size, 3);
      expect(result.temporary, temp);
    });

    test('BINARY-REPLACE-3: a deleted original is a conflict', () async {
      final read = await access.revisionOf(doc);
      File(doc).deleteSync();
      final temp = await access.temporaryTarget(doc);
      final result = await access.replace(doc, temp, read);
      expect(result.outcome, TomBinaryReplaceOutcome.conflict);
      expect(result.revision, isNull);
      expect(File(doc).existsSync(), isFalse);
      expect(File(temp).existsSync(), isTrue);
    });

    test('BINARY-REPLACE-4: a new file is written when none appeared, and a '
        'conflict when one did', () async {
      final fresh = '${dir.path}/new.pdf';
      final first = await access.save(fresh, [1], null);
      expect(first.replaced, isTrue);
      expect(File(fresh).readAsBytesSync(), [1]);
      final second = await access.save(fresh, [2], null);
      expect(second.outcome, TomBinaryReplaceOutcome.conflict);
      expect(File(fresh).readAsBytesSync(), [1]);
    });

    test('BINARY-REPLACE-5: the original keeps its permissions', () async {
      if (Platform.isWindows) return;
      Process.runSync('chmod', ['640', doc]);
      final read = await access.revisionOf(doc);
      final result = await access.save(doc, [5, 6], read);
      expect(result.replaced, isTrue);
      expect(File(doc).statSync().mode & 0x1FF, 416); // 0640
      Process.runSync('chmod', ['755', doc]);
      final again = await access.save(doc, [5], result.revision);
      expect(again.replaced, isTrue);
      expect(File(doc).statSync().mode & 0x1FF, 493); // 0755
    });

    test(
      'BINARY-REPLACE-6: a touched but unchanged original is replaced',
      () async {
        final read = await access.revisionOf(doc);
        File(doc).setLastModifiedSync(DateTime(2001));
        final result = await access.save(doc, [8], read);
        expect(result.replaced, isTrue);
      },
    );
  });

  test('BINARY-FORCE-1: force replaces a changed original', () async {
    final read = await access.revisionOf(doc);
    File(doc).writeAsBytesSync([7]);
    final temp = await access.temporaryTarget(doc);
    File(temp).writeAsBytesSync([9]);
    final result = await access.replace(doc, temp, read, force: true);
    expect(result.replaced, isTrue);
    expect(File(doc).readAsBytesSync(), [9]);
  });

  test('BINARY-COPY-1: keepAsCopy renames the temporary file to '
      '<name> (copy).<ext>, then (copy 2)', () async {
    final t1 = await access.temporaryTarget(doc);
    File(t1).writeAsBytesSync([1]);
    expect(await access.keepAsCopy(t1, doc), '${dir.path}/report (copy).docx');
    final t2 = await access.temporaryTarget(doc);
    expect(
      await access.keepAsCopy(t2, doc),
      '${dir.path}/report (copy 2).docx',
    );
    expect(File(t1).existsSync(), isFalse);
  });

  test('BINARY-WRITABLE-1: isWritable follows the permissions', () async {
    expect(await access.isWritable(doc), isTrue);
    expect(await access.isWritable('${dir.path}/missing.docx'), isFalse);
    if (Platform.isWindows) return;
    Process.runSync('chmod', ['444', doc]);
    expect(await access.isWritable(doc), isFalse);
  });

  test('BINARY-IFACE-1: TomBinaryFileAccess is a TomBinaryFiles', () {
    expect(access, isA<TomBinaryFiles>());
  });

  test('BINARY-CLEAN-1: removeTemporaryFiles deletes only the file\'s '
      'temporary files', () async {
    final a = await access.temporaryTarget(doc);
    final b = await access.temporaryTarget(doc);
    final other = await access.temporaryTarget('${dir.path}/other.pdf');
    final lookalike = File('${dir.path}/.report.docx.tom-save-x')
      ..writeAsStringSync('');
    final removed = await access.removeTemporaryFiles(doc);
    expect(removed.toSet(), {a, b});
    expect(File(a).existsSync(), isFalse);
    expect(File(other).existsSync(), isTrue);
    expect(lookalike.existsSync(), isTrue);
    expect(File(doc).existsSync(), isTrue);
  });
}
