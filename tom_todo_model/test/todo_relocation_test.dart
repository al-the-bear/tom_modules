/// A todo file's name, and archive and delete as relocation: the sibling,
/// what is refused, and the three files afterwards.
library;

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

const _source = """# yaml-language-server: \$schema=../schemas/todo.schema.json
quest: garden
todos:
  - id: g1
    title: Done
    description: Done.
    status: completed
    decisions:
      - summary: When?
        decision_needed: Morning or evening.
        decision: Mornings.
  - id: g2
    title: Open
    description: Open.
    status: not-started
""";

void main() {
  group('the file name', () {
    test('WONETESTA10-K3: todo file families and siblings, the suffix on the '
        'first dot-segment [1011]', () {
      final quest = TomTodoFileName.parse('todos.webwork.todo.yaml')!;
      expect(quest.family, TomTodoFileFamily.quest);
      expect(quest.sibling, TomTodoFileSibling.live);
      expect(quest.quest, 'webwork');
      final archived = TomTodoFileName.parse(
        'todos-archived.webwork.todo.yaml',
      )!;
      expect(archived.sibling, TomTodoFileSibling.archived);
      final session = TomTodoFileName.parse(
        'session-todo-deleted.mbp.webwork.todo.yaml',
      )!;
      expect(session.family, TomTodoFileFamily.session);
      expect(session.sibling, TomTodoFileSibling.deleted);
      expect(session.host, 'mbp');
      expect(session.quest, 'webwork');
      expect(
        TomTodoFileName.parse('review.todo.yaml')!.family,
        TomTodoFileFamily.other,
      );
      expect(TomTodoFileName.parse('todos.yaml'), isNull);
    });
  });

  group('relocation', () {
    final now = DateTime.utc(2026, 10, 21, 9, 30);

    test('the sibling suffixes the first dot-segment', () {
      expect(
        tomTodoSiblingName(
          'todos.garden.todo.yaml',
          TomTodoRelocationKind.archive,
        ),
        'todos-archived.garden.todo.yaml',
      );
      expect(
        tomTodoSiblingName('review.todo.yaml', TomTodoRelocationKind.delete),
        'review-deleted.todo.yaml',
      );
    });

    test('only a completed todo is archived, a completed one is not deleted, '
        'and a sibling file keeps its todos', () {
      final file = TomTodoFile.parse(_source);
      const name = 'todos.garden.todo.yaml';
      expect(
        tomTodoRelocationRefusal(file, name, 0, TomTodoRelocationKind.archive),
        isNull,
      );
      expect(
        tomTodoRelocationRefusal(file, name, 1, TomTodoRelocationKind.archive),
        contains('Only a completed'),
      );
      expect(
        tomTodoRelocationRefusal(file, name, 0, TomTodoRelocationKind.delete),
        contains('archived, not deleted'),
      );
      expect(
        tomTodoRelocationRefusal(
          file,
          'todos-archived.garden.todo.yaml',
          0,
          TomTodoRelocationKind.archive,
        ),
        contains('stay here'),
      );
    });

    test('archiving writes a new sibling, journals the decisions and leaves '
        'the other todo', () {
      final source = TomTodoFile.parse(_source);
      const name = 'todos.garden.todo.yaml';
      expect(
        tomTodoRelocationJournalName(
          source,
          name,
          0,
          TomTodoRelocationKind.archive,
        ),
        'decisions.garden.md',
      );
      final plan = tomPlanTodoRelocation(
        source: source,
        fileName: name,
        index: 0,
        kind: TomTodoRelocationKind.archive,
        now: now,
      );
      final target = TomTodoFile.parse(plan.targetText);
      expect(
        plan.targetText,
        startsWith(
          '# yaml-language-server: \$schema=../schemas/todo.schema.json\nquest: garden\n',
        ),
      );
      expect(target.todos.single.id, 'g1');
      expect(target.todos.single.archived, DateTime.utc(2026, 10, 21));
      expect(TomTodoFile.parse(plan.sourceText).todos.map((t) => t.id), ['g2']);
      expect(plan.sourceText, contains('updated: "2026-10-21"'));
      expect(plan.journalText, startsWith('# Decisions — garden'));
      expect(plan.journalText, contains('**Decided:** Mornings.'));
    });

    test('an existing sibling holding the id is replaced, not doubled', () {
      final source = TomTodoFile.parse(_source);
      final first = tomPlanTodoRelocation(
        source: source,
        fileName: 'todos.garden.todo.yaml',
        index: 0,
        kind: TomTodoRelocationKind.archive,
        now: now,
      );
      final again = tomPlanTodoRelocation(
        source: source,
        fileName: 'todos.garden.todo.yaml',
        index: 0,
        kind: TomTodoRelocationKind.archive,
        now: now,
        target: first.targetText,
        journal: first.journalText,
      );
      expect(TomTodoFile.parse(again.targetText).todos.map((t) => t.id), [
        'g1',
      ]);
    });

    test('deleting a todo writes no journal entry', () {
      final plan = tomPlanTodoRelocation(
        source: TomTodoFile.parse(_source),
        fileName: 'todos.garden.todo.yaml',
        index: 1,
        kind: TomTodoRelocationKind.delete,
        now: now,
      );
      expect(plan.journalText, isNull);
      expect(
        TomTodoFile.parse(plan.targetText).todos.single.deleted,
        DateTime.utc(2026, 10, 21),
      );
    });
  });
}
