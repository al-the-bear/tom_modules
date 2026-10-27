/// The editing session, over both file systems: opening never writes, a save
/// writes the encoding back, the disk is checked before every save, a file's
/// history is its own, and a file that is too large or binary is not edited.
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_file_system/io.dart';
import 'package:tom_file_session/tom_file_session.dart';

const _todos =
    'todos:\n  - id: a\n    title: Water\n  - id: b\n    title: Weed\n';

/// One file system under test, with a way to change a file behind the
/// session's back.
class _Setup {
  _Setup(this.name, this.fs, this.writeBehind, this.deleteBehind, this.close);
  final String name;
  final TomFileSystem fs;
  final Future<void> Function(String path, List<int> bytes) writeBehind;
  final Future<void> Function(String path) deleteBehind;
  final Future<void> Function() close;
}

_Setup _memory() {
  final fs = TomMemoryFileSystem(root: Uri.directory('/work/'));
  return _Setup(
    'memory',
    fs,
    (path, bytes) async => fs.write(fs.uriOf(path), Uint8List.fromList(bytes)),
    (path) => fs.delete(fs.uriOf(path)),
    fs.dispose,
  );
}

_Setup _local() {
  final dir = Directory.systemTemp.createTempSync('forge_session_');
  final fs = TomLocalFileSystem(dir.path);
  File file(String path) => File(p.join(dir.path, path));
  return _Setup(
    'local',
    fs,
    (path, bytes) async => file(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes),
    (path) async => file(path).deleteSync(),
    () async {
      await fs.dispose();
      dir.deleteSync(recursive: true);
    },
  );
}

void main() {
  for (final make in [_memory, _local]) {
    late _Setup s;
    Future<ForgeFileSession> open(String path) async {
      final session = ForgeFileSession(fileSystem: s.fs, path: path);
      await session.load();
      return session;
    }

    Future<String> onDisk(String path) async =>
        (await s.fs.readText(s.fs.uriOf(path)));

    group('SESSION-${make == _memory ? 'M' : 'L'} session', () {
      setUp(() async {
        s = make();
        await s.writeBehind('q/todos.yaml', utf8.encode(_todos));
      });
      tearDown(() => s.close());

      test('SESSION-1: opening never writes, and an edit saves only its '
          'text', () async {
        final before = (await s.fs.stat(s.fs.uriOf('q/todos.yaml')))!;
        final session = await open('q/todos.yaml');
        expect(session.dirty, isFalse);
        final after = (await s.fs.stat(s.fs.uriOf('q/todos.yaml')))!;
        expect(after.modified, before.modified);
        session.edit(session.text.replaceFirst('Water', 'Plant'), 'Retitle');
        expect(session.dirty, isTrue);
        expect(await session.save(), ForgeFileSaveOutcome.saved);
        expect(
          await onDisk('q/todos.yaml'),
          _todos.replaceFirst('Water', 'Plant'),
        );
        expect(session.dirty, isFalse);
      });

      test(
        'SESSION-2: a BOM and UTF-16 are written back as they were',
        () async {
          await s.writeBehind('bom.yaml', [
            0xEF,
            0xBB,
            0xBF,
            ...utf8.encode('todos: []\n'),
          ]);
          final utf16 = <int>[0xFF, 0xFE];
          for (final unit in 'todos: []\n'.codeUnits) {
            utf16.addAll([unit & 0xFF, unit >> 8]);
          }
          await s.writeBehind('wide.yaml', utf16);
          for (final name in ['bom.yaml', 'wide.yaml']) {
            final session = await open(name);
            session.edit('todos: [a]\n', 'Add');
            await session.save();
            final decoded = tomDecodeTextBytes(
              (await s.fs.read(s.fs.uriOf(name))).bytes,
            );
            expect(decoded.text, 'todos: [a]\n');
            expect(
              decoded.encoding,
              name == 'bom.yaml'
                  ? TomTextEncoding.utf8Bom
                  : TomTextEncoding.utf16le,
            );
          }
        },
      );

      test('SESSION-3: undo and redo walk the file\'s own history, one entry '
          'per edit', () async {
        final session = await open('q/todos.yaml');
        final original = session.text;
        session.edit(session.text.replaceFirst('Water', 'Plant'), 'Retitle');
        final afterFirst = session.text;
        session.edit(session.text.replaceFirst('Weed', 'Hoe'), 'Second');
        expect(session.history.map((e) => e.label), ['Retitle', 'Second']);
        await session.undo();
        expect(session.text, afterFirst);
        await session.undo();
        expect(session.text, original);
        expect(session.dirty, isFalse);
        await session.redo();
        expect(session.text, afterFirst);
      });

      test('SESSION-4: a clean session reloads a file changed on disk; a '
          'dirty one is asked, and save does not write over it', () async {
        final session = await open('q/todos.yaml');
        final changed = _todos.replaceFirst('Water', 'Water well');
        await s.writeBehind('q/todos.yaml', utf8.encode(changed));
        await session.checkExternal();
        expect(session.text, changed);
        expect(session.takeNotice(), 'Reloaded: changed on disk');

        session.edit('${session.text}# mine\n', 'Mine');
        await s.writeBehind('q/todos.yaml', utf8.encode('$changed# theirs\n'));
        expect(await session.save(), ForgeFileSaveOutcome.conflict);
        expect(session.external?.theirs, '$changed# theirs\n');
        expect(await onDisk('q/todos.yaml'), '$changed# theirs\n');

        expect(
          await session.saveMerged('$changed# both\n'),
          ForgeFileSaveOutcome.saved,
        );
        expect(await onDisk('q/todos.yaml'), '$changed# both\n');
      });

      test('SESSION-5: take theirs drops mine; a deleted file is marked and '
          'recreated by save', () async {
        final session = await open('q/todos.yaml');
        session.edit('${session.text}# mine\n', 'Mine');
        await s.writeBehind('q/todos.yaml', utf8.encode('todos: []\n'));
        await session.checkExternal();
        session.takeTheirs();
        expect(session.text, 'todos: []\n');
        expect(session.canUndo, isFalse);

        await s.deleteBehind('q/todos.yaml');
        await session.checkExternal();
        expect(session.deletedOnDisk, isTrue);
        expect(session.dirty, isFalse);
        expect(await session.save(), ForgeFileSaveOutcome.saved);
        expect(await onDisk('q/todos.yaml'), 'todos: []\n');
      });

      test('SESSION-6: a large file opens read-only, a binary one does not '
          'open, and the caller decides what binary means', () async {
        await s.writeBehind(
          'big.txt',
          utf8.encode('a' * (forgeReadOnlyAbove + 1)),
        );
        await s.writeBehind('blob.bin', [1, 0, 2, 0]);
        final big = await open('big.txt');
        expect(big.readOnlyReason, contains('2 MiB'));
        expect(() => big.edit('b', 'x'), throwsStateError);
        final blob = await open('blob.bin');
        expect(blob.state, ForgeFileSessionState.refused);
        expect(blob.refusal, isNot(contains('Webwork')));

        final strict = ForgeFileSession(
          fileSystem: s.fs,
          path: 'q/todos.yaml',
          isBinary: (name, _) => name.endsWith('.yaml'),
        );
        await strict.load();
        expect(strict.state, ForgeFileSessionState.refused);
      });

      test('SESSION-8: a burst of typing is one history entry; another '
          'group starts the next, and undo walks them back', () async {
        await s.writeBehind('t.md', utf8.encode('ab\n'));
        final session = await open('t.md');
        session
          ..edit('abc\n', 'Edit', group: 'typing')
          ..edit('abcd\n', 'Edit', group: 'typing')
          ..edit('abcde\n', 'Edit', group: 'typing');
        expect(session.history, hasLength(1));
        session.edit('Xabcde\n', 'Other', group: 'other');
        expect(session.history, hasLength(2));
        await session.undo();
        await session.undo();
        expect(session.text, 'ab\n');
      });

      test('SESSION-7: listeners hear an edit, and stop hearing after '
          'removal', () async {
        final session = await open('q/todos.yaml');
        var heard = 0;
        void listener() => heard++;
        session.addListener(listener);
        session.edit('x\n', 'X');
        expect(heard, 1);
        session.removeListener(listener);
        session.edit('y\n', 'Y');
        expect(heard, 1);
      });
    });
  }
}
