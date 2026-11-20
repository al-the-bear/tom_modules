/// The todo-file editor over a host the test plays, with no board and no
/// transfer: the list draws the file's todos, a checkbox is one edit of the
/// session and undoes, the Board segment and the transfer bar are absent, the
/// All files segment lists every todo file and opens a row through the host,
/// archive moves a todo to the `-archived` sibling, and the file is checked
/// against the schema it names; a file the model cannot read opens in its
/// source.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_file_editors/tom_file_editors.dart';
import 'package:tom_todo_ui/tom_todo_ui.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

const String todoFile = '''quest: garden
todos:
  - id: gx1_ajka-plant
    title: Plant the beds
    description: Tomatoes south.
    status: not-started
  - id: gx3_ajka-harvest
    title: Harvest
    description: In autumn.
    status: completed
    completed_date: "2026-10-01"
''';

const String otherFile = '''quest: garden
todos:
  - id: sx1_ajka-ask
    title: Ask about seeds
    description: d
    status: not-started
''';

class _Aggregate implements TomTodoAggregateSource {
  _Aggregate(this.tree);

  @override
  final TomFileSystem tree;

  final List<String> opened = [];

  @override
  bool get includeSiblings => true;

  @override
  void openTodo(String path, String id) => opened.add('$path#$id');
}

class _Host implements TomTodoFileEditorHost {
  _Host(this.session, {this.aggregate});

  @override
  final ForgeFileSession session;

  @override
  final TomTodoAggregateSource? aggregate;

  final List<String> notices = [];

  @override
  String get name => session.path.split('/').last;

  @override
  String get filePath => session.path;

  @override
  late final TomSchemaCache schemas = TomSchemaCache(read: (path) async {
    final fs = session.fileSystem;
    final uri = fs.uriOf(path);
    if (await fs.stat(uri) == null) return null;
    return fs.readText(uri);
  });

  @override
  late final TomTodoFileValidator validator =
      TomTodoFileValidator(schemas: schemas);

  @override
  late final TomTodoRelocator relocator = TomTodoRelocator(clock: clock);

  @override
  DateTime Function() get clock => () => DateTime.utc(2026, 11, 4, 10);

  @override
  String? author() => 'tester';

  @override
  String? takeSelection() => null;

  @override
  Future<bool> save(BuildContext context) async =>
      await session.save() != ForgeFileSaveOutcome.conflict;

  @override
  TomTodoFileTransfer? get transfer => null;

  @override
  Widget Function(BuildContext, TomTodoFileController)? get board => null;

  @override
  Future<void> undo(BuildContext context) => session.undo();

  @override
  Future<void> redo(BuildContext context) => session.redo();

  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      notices.add(message);

  @override
  Future<void> copyProtected(String value) async {}
}

late TomMemoryFileSystem _fs;

Finder _row(String id) =>
    find.byWidgetPredicate((w) => w is TomTodoRow && w.item.id == id);

Future<void> _real(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<_Host> _open(WidgetTester tester, {bool aggregate = false}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = ForgeFileSession(
      fileSystem: _fs, path: 'quest/todos.garden.todo.yaml');
  await tester.runAsync(session.load);
  addTearDown(session.dispose);
  final host =
      _Host(session, aggregate: aggregate ? _Aggregate(_fs) : null);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: TomTodoFileEditor(host: host)),
  ));
  await _real(tester);
  return host;
}

Future<String> _text(String path) async =>
    _fs.readText(_fs.uriOf(path));

void main() {
  setUp(() {
    _fs = TomMemoryFileSystem(root: Uri.directory('/work/'), seed: {
      '/work/quest/todos.garden.todo.yaml': todoFile,
      '/work/other/session-todo.mbp.garden.todo.yaml': otherFile,
    });
  });

  testWidgets('TODOFILE-1: the file\'s todos are rows, with its validity; '
      'without a board or a transfer neither is offered', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('tom-todo-file-editor')), findsOneWidget);
    expect(_row('gx1_ajka-plant'), findsOneWidget);
    expect(_row('gx3_ajka-harvest'), findsOneWidget);
    expect(find.byKey(const Key('tom-todo-file-validity')), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Board'), findsNothing);
    expect(find.text('All files'), findsNothing);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
  });

  testWidgets('TODOFILE-2: a checkbox is one edit of the session, which '
      'Undo reverts', (tester) async {
    final host = await _open(tester);
    await tester.tap(find.byKey(const Key('todo-done-gx1_ajka-plant')));
    await tester.pump();
    expect(host.session.dirty, isTrue);
    final edited = TomTodoFile.parse(host.session.text);
    expect(edited.entries[0].item!.status, TomTodoStatus.completed);
    expect(edited.blockOf(1), TomTodoFile.parse(todoFile).blockOf(1));
    await tester.runAsync(host.session.undo);
    await tester.pump();
    expect(host.session.text, todoFile);
  });

  testWidgets('TODOFILE-3: All files lists every todo file under the root '
      'and opens a row through the host', (tester) async {
    final host = await _open(tester, aggregate: true);
    await tester.tap(find.text('All files'));
    await _real(tester);
    expect(find.byKey(const Key('tom-todo-aggregate')), findsOneWidget);
    final row =
        find.byKey(const Key('tom-todo-aggregate-row-sx1_ajka-ask'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    final source = host.aggregate! as _Aggregate;
    expect(source.opened.single, endsWith('#sx1_ajka-ask'));
    expect(source.opened.single,
        contains('other/session-todo.mbp.garden.todo.yaml'));
  });

  testWidgets('TODOFILE-4: Archive moves a todo to the -archived sibling '
      'after confirming', (tester) async {
    await _open(tester);
    await tester.tap(find.descendant(
        of: _row('gx3_ajka-harvest'),
        matching: find.byIcon(Icons.more_horiz)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tom-todo-archive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tom-todo-file-relocate')));
    await _real(tester);
    expect(_row('gx3_ajka-harvest'), findsNothing);
    final archived = await tester
        .runAsync(() => _text('quest/todos-archived.garden.todo.yaml'));
    expect(archived, contains('gx3_ajka-harvest'));
    expect(archived, contains('archived: "2026-11-04"'));
    final remaining =
        await tester.runAsync(() => _text('quest/todos.garden.todo.yaml'));
    expect(remaining, isNot(contains('gx3_ajka-harvest')));
  });

  testWidgets('TODOFILE-5: a file that breaks the schema it names reports '
      'the problem at its todo', (tester) async {
    _fs = TomMemoryFileSystem(root: Uri.directory('/work/'), seed: {
      '/work/quest/todos.garden.todo.yaml':
          '# yaml-language-server: \$schema=../todo.schema.json\n$todoFile',
      '/work/todo.schema.json': '{"type": "object", "properties": {"todos": '
          '{"type": "array", "items": {"type": "object", '
          '"required": ["priority"]}}}}',
    });
    await _open(tester);
    await _real(tester);
    expect(find.textContaining(' problems'), findsOneWidget);
    expect(find.byKey(const Key('tom-todo-file-issue-0')), findsWidgets);
    expect(find.byKey(const Key('tom-todo-file-issue-1')), findsWidgets);
  });

  testWidgets('TODOFILE-6: a file the model cannot read opens in its source '
      'below the reason, and an edit there is an edit of the session',
      (tester) async {
    _fs = TomMemoryFileSystem(root: Uri.directory('/work/'), seed: {
      '/work/quest/todos.garden.todo.yaml': 'todos: [unclosed\n',
    });
    final host = await _open(tester);
    expect(find.byKey(const Key('tom-todo-file-unreadable')), findsOneWidget);
    expect(find.byType(TomTodoFileSource), findsOneWidget);
    final field = find.descendant(
        of: find.byType(TomTodoFileSource), matching: find.byType(EditableText));
    await tester.enterText(field.first, todoFile);
    await _real(tester);
    expect(host.session.text, todoFile);
    expect(_row('gx1_ajka-plant'), findsOneWidget);
  });
}
