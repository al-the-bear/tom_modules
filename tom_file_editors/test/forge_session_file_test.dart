/// ForgeSessionFile and ForgeSessionFileFrame: the binding of an editor's
/// controller to a session, and the file's state drawn above the editor —
/// one test per state.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_editors/tom_file_editors.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_system/tom_file_system.dart';

late TomMemoryFileSystem _fs;

/// A stand-in editor: its text, and what the binding told it.
class _Editor {
  String text = '';
  var saved = 0;
  final adopted = <String>[];
}

Future<(ForgeSessionFile, _Editor)> _bind(
  WidgetTester tester,
  String path, {
  bool load = true,
}) async {
  final session = ForgeFileSession(fileSystem: _fs, path: path);
  addTearDown(session.dispose);
  if (load) await tester.runAsync(session.load);
  final editor = _Editor();
  final file = ForgeSessionFile(
    session: session,
    textOf: () => editor.text,
    adopt: (text) {
      editor.text = text;
      editor.adopted.add(text);
    },
    markSaved: () => editor.saved++,
  );
  addTearDown(file.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ForgeSessionFileFrame(
          file: file,
          child: const Text('the editor', key: Key('editor')),
        ),
      ),
    ),
  );
  return (file, editor);
}

Uri _uri(String path) => Uri.file('/work/$path');

void main() {
  setUp(() {
    _fs = TomMemoryFileSystem(
      root: Uri.directory('/work/'),
      seed: {'notes.md': 'one\r\ntwo\r\n'},
    );
  });

  testWidgets('FSF-1: loading — a spinner until the file is read', (
    tester,
  ) async {
    final (file, _) = await _bind(tester, 'notes.md', load: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('editor')), findsNothing);
    expect(file.loaded, isFalse);
    await tester.runAsync(file.session.load);
    await tester.pump();
    expect(find.byKey(const Key('editor')), findsOneWidget);
  });

  testWidgets('FSF-2: missing — the file does not exist', (tester) async {
    await _bind(tester, 'gone.md');
    expect(find.text('This file does not exist.'), findsOneWidget);
    expect(find.byKey(const Key('editor')), findsNothing);
  });

  testWidgets('FSF-3: refused — a binary file is not opened, with the reason', (
    tester,
  ) async {
    await tester.runAsync(
      () => _fs.write(_uri('image.bin'), Uint8List.fromList([0, 159, 146, 0])),
    );
    final (file, _) = await _bind(tester, 'image.bin');
    expect(file.session.state, ForgeFileSessionState.refused);
    expect(find.text(file.session.refusal!), findsOneWidget);
    expect(find.byKey(const Key('editor')), findsNothing);
  });

  testWidgets('FSF-4: ready — the editor gets the text with LF endings, and '
      'a save writes it back with the file\'s CRLF', (tester) async {
    final (file, editor) = await _bind(tester, 'notes.md');
    expect(find.byKey(const Key('editor')), findsOneWidget);
    expect(file.loaded, isTrue);
    expect(editor.adopted, ['one\ntwo\n']);
    expect(file.canSave, isTrue);

    editor.text = 'one\ntwo\nthree\n';
    final outcome = await tester.runAsync(file.save);
    expect(outcome, ForgeFileSaveOutcome.saved);
    expect(editor.saved, 1);
    final disk = await tester.runAsync(() => _fs.readText(_uri('notes.md')));
    expect(disk, 'one\r\ntwo\r\nthree\r\n');
  });

  testWidgets('FSF-5: read-only — the session\'s notice is shown above the '
      'editor and nothing is saved', (tester) async {
    await tester.runAsync(
      () => _fs.writeText(_uri('big.txt'), 'x' * (forgeReadOnlyAbove + 1)),
    );
    final (file, _) = await _bind(tester, 'big.txt');
    expect(find.text(file.session.readOnlyReason!), findsOneWidget);
    expect(find.byKey(const Key('editor')), findsOneWidget);
    expect(file.canSave, isFalse);
  });

  testWidgets('FSF-6: changed on disk — the banner offers Keep mine and Take '
      'theirs', (tester) async {
    final (file, editor) = await _bind(tester, 'notes.md');
    // An unsaved edit, then the file changes on disk.
    editor.text = 'mine\n';
    file.session.edit('mine\r\n', 'Type');
    await tester.runAsync(() => _fs.writeText(_uri('notes.md'), 'theirs\r\n'));
    await tester.runAsync(file.session.checkExternal);
    await tester.pump();
    expect(find.byKey(const Key('forge-file-changed-on-disk')), findsOneWidget);
    expect(find.text('This file changed on disk.'), findsOneWidget);

    await tester.tap(find.text('Take theirs'));
    await tester.pump();
    expect(editor.text, 'theirs\n', reason: 'their text, LF in the editor');
    expect(find.byKey(const Key('forge-file-changed-on-disk')), findsNothing);
  });

  testWidgets('FSF-7: changed on disk — Keep mine keeps the editor\'s text '
      'and the next save writes it', (tester) async {
    final (file, editor) = await _bind(tester, 'notes.md');
    editor.text = 'mine\n';
    file.session.edit('mine\r\n', 'Type');
    await tester.runAsync(() => _fs.writeText(_uri('notes.md'), 'theirs\r\n'));
    await tester.runAsync(file.session.checkExternal);
    await tester.pump();
    await tester.tap(find.text('Keep mine'));
    await tester.pump();
    expect(find.byKey(const Key('forge-file-changed-on-disk')), findsNothing);
    expect(editor.text, 'mine\n');
    await tester.runAsync(file.save);
    final disk = await tester.runAsync(() => _fs.readText(_uri('notes.md')));
    expect(disk, 'mine\r\n');
  });

  testWidgets('FSF-8: deleted on disk — the banner says so, and a save '
      'writes the file again', (tester) async {
    final (file, editor) = await _bind(tester, 'notes.md');
    await tester.runAsync(() => _fs.delete(_uri('notes.md')));
    await tester.runAsync(file.session.checkExternal);
    await tester.pump();
    expect(find.byKey(const Key('forge-file-deleted-on-disk')), findsOneWidget);
    expect(find.byKey(const Key('editor')), findsOneWidget);

    await tester.runAsync(file.save);
    await tester.pump();
    expect(find.byKey(const Key('forge-file-deleted-on-disk')), findsNothing);
    expect(
      await tester.runAsync(() => _fs.readText(_uri('notes.md'))),
      editor.text.replaceAll('\n', '\r\n'),
    );
  });
}
