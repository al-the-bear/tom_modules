/// A todo file edited as text: every byte outside the edit kept, the ids, the
/// journal and the relocation plan.
library;

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';
import 'package:yaml/yaml.dart';

import 'support/todo_fixtures.dart';

void main() {
  group('WONETESTA11-Y reading', () {
    test('WONETESTA11-Y1: todos, header, schema line and unknown keys are '
        'read [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      expect(file.entries.map((e) => e.id), [
        'gx1_ajka-plant',
        'gx2_ajka-water',
        'gx3_ajka-harvest',
      ]);
      expect(file.quest, 'garden');
      expect(file.schemaRef, '../schemas/todo.schema.json');
      expect(file.entries[1].unknownKeys, {'x_note'});
      expect(
        file.entries[1].todo!.description,
        'Twice a week.\nMore in summer.',
      );
      expect(file.entries[2].todo!.status, TomTodoStatus.completed);
      expect(file.entries[2].todo!.decisions.single.decision, 'Mornings.');
    });

    test('WONETESTA11-Y2: an item the model refuses is kept, with the reason '
        '[1011]', () {
      final file = TomTodoFile.parse(
        'todos:\n  - id: a\n    status: sleeping\n',
      );
      expect(file.entries.single.todo, isNull);
      expect(file.entries.single.error, isNotNull);
    });

    test(
      'WONETESTA11-Y3: not a todo file is refused with the reason [1011]',
      () {
        expect(
          () => TomTodoFile.parse('todos: [a: b'),
          throwsA(isA<TomTodoFileFormatException>()),
        );
        expect(
          () => TomTodoFile.parse('- a\n'),
          throwsA(isA<TomTodoFileFormatException>()),
        );
      },
    );
  });

  group('WONETESTA11-E byte-preserving edits', () {
    /// Every byte of [before] outside the text of todo [index] is in
    /// [after], in place.
    void onlyTodoChanged(String before, String after, int index) {
      final a = TomTodoFile.parse(before);
      final b = TomTodoFile.parse(after);
      expect(
        after.substring(0, b.entries[index].lineStart),
        before.substring(0, a.entries[index].lineStart),
      );
      expect(
        after.substring(b.entries[index].end),
        before.substring(a.entries[index].end),
      );
    }

    test('WONETESTA11-E1: a status change rewrites one line [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final todo = file.entries[0].todo!.copy()
        ..status = TomTodoStatus.inProgress;
      final after = file.withTodo(0, todo);
      onlyTodoChanged(questTodoFile, after, 0);
      expect(
        after,
        questTodoFile.replaceFirst(
          'status: not-started   # first',
          'status: in-progress',
        ),
      );
    });

    test('WONETESTA11-E2: an edit in the middle of the file keeps the block '
        'scalars, comments and unknown keys of its own todo [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final todo = file.entries[1].todo!.copy()
        ..priority = TomTodoPriority.high
        ..tags = ['outdoor', 'weekly'];
      final after = file.withTodo(1, todo);
      onlyTodoChanged(questTodoFile, after, 1);
      expect(after, contains('    description: |-\n      Twice a week.\n'));
      expect(after, contains('    x_note: kept as written\n'));
      expect(after, contains('    priority: high\n'));
      expect(after, contains('    tags:\n      - outdoor\n      - weekly\n'));
      final re = TomTodoFile.parse(after);
      expect(re.entries[1].todo!.priority, TomTodoPriority.high);
      expect(re.entries[1].unknownKeys, {'x_note'});
    });

    test('WONETESTA11-E3: a new key goes after its schema predecessor; a '
        'removed key takes nothing else with it [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final todo = file.entries[0].todo!.copy()
        ..estimate = 'PT2H'
        ..notes = null;
      final after = file.withTodo(0, todo);
      onlyTodoChanged(questTodoFile, after, 0);
      final lines = after.split('\n');
      final status = lines.indexWhere((l) => l.contains('status: not-started'));
      expect(lines[status + 1], '    estimate: PT2H');
      expect(after, isNot(contains('Soil first.')));
      expect(TomTodoFile.parse(after).entries[0].todo!.notes, isNull);
    });

    test('WONETESTA11-E4: dates, numbers and booleans are quoted; multi-line '
        'text is a literal block [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final todo = file.entries[0].todo!.copy()
        ..title = 'yes'
        ..due = DateTime.utc(2026, 11, 2)
        ..notes = 'Line one\nLine two';
      final after = file.withTodo(0, todo);
      expect(after, contains('title: "yes"'));
      expect(after, contains('due: "2026-11-02"'));
      expect(
        after,
        contains('    notes: |-\n      Line one\n      Line two\n'),
      );
      final read = loadYaml(after) as YamlMap;
      final item = (read['todos'] as YamlList)[0] as YamlMap;
      expect(item['title'], 'yes');
      expect(item['notes'], 'Line one\nLine two');
    });

    test(
      'WONETESTA11-E5: an edit that changes nothing writes nothing [1011]',
      () {
        final file = TomTodoFile.parse(questTodoFile);
        expect(file.withTodo(1, file.entries[1].todo!.copy()), questTodoFile);
      },
    );

    test('WONETESTA11-E6: CRLF stays CRLF, a missing final newline stays '
        'missing [1011]', () {
      final crlf = questTodoFile.replaceAll('\n', '\r\n');
      final file = TomTodoFile.parse(crlf);
      final todo = file.entries[0].todo!.copy()..tags = ['a'];
      final after = file.withTodo(0, todo);
      expect(after.replaceAll('\r\n', ''), isNot(contains('\n')));
      final bare = questTodoFile.trimRight();
      final appended = TomTodoFile.parse(
        bare,
      ).withInserted(TomTodo(id: 'gx4_ajka-rest', title: 'Rest'));
      expect(appended.endsWith('\n'), isFalse);
      expect(TomTodoFile.parse(appended).entries.last.id, 'gx4_ajka-rest');
    });
  });

  group('WONETESTA11-L list operations', () {
    test('WONETESTA11-L1: a new todo is appended at the list\'s indentation '
        '[1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final after = file.withInserted(
        TomTodo(
          id: 'gx4_ajka-rest',
          title: 'Rest',
          description: 'Let the beds rest.',
        ),
      );
      expect(after.startsWith(questTodoFile.trimRight()), isTrue);
      expect(after, contains('  - id: gx4_ajka-rest\n    title: Rest\n'));
      expect(TomTodoFile.parse(after).entries, hasLength(4));
    });

    test('WONETESTA11-L2: an empty list, flow or bare, becomes a block list '
        '[1011]', () {
      for (final empty in ['quest: q\ntodos: []\n', 'quest: q\ntodos:\n']) {
        final after = TomTodoFile.parse(
          empty,
        ).withInserted(TomTodo(id: 'a_ajka', title: 'A'));
        expect(
          after,
          'quest: q\ntodos:\n  - id: a_ajka\n    title: A\n'
          '    status: not-started\n',
        );
      }
    });

    test('WONETESTA11-L3: remove and move keep every other byte [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final removed = file.withoutTodo(1);
      expect(removed, questTodoFile.replaceFirst(file.blockOf(1), ''));
      final moved = file.withMoved(2, 0);
      final m = TomTodoFile.parse(moved);
      expect(m.entries.map((e) => e.id), [
        'gx3_ajka-harvest',
        'gx1_ajka-plant',
        'gx2_ajka-water',
      ]);
      expect(m.blockOf(0), file.blockOf(2));
      expect(m.blockOf(2), file.blockOf(1));
    });

    test('WONETESTA11-L4: a file-level key is set in place, or added before '
        'todos below the header comments [1011]', () {
      final file = TomTodoFile.parse(questTodoFile);
      final updated = file.withFileKey('updated', '2026-10-12');
      expect(
        updated,
        questTodoFile.replaceFirst(
          'updated: "2026-10-01"',
          'updated: "2026-10-12"',
        ),
      );
      final authored = file.withFileKey('author', 'me');
      expect(authored, contains('updated: "2026-10-01"\nauthor: me\n'));
      expect(authored, contains('# ACTIVE SET'));
    });
  });

  group('WONETESTA11-I ids', () {
    test('WONETESTA11-I1: the date code is the id-prefix tool\'s [1011]', () {
      expect(tomTodoDateCode(DateTime(2026, 10, 11, 19)), 'ajkt');
      expect(tomTodoDateCode(DateTime(2027, 1, 27, 0)), 'baäa');
      expect(tomTodoDateCode(DateTime(2026, 12, 31, 23)), 'alüx');
      expect(
        tomMintTodoId(
          'wonetestb16',
          DateTime(2026, 10, 11, 19),
          slug: 'Fix the Board!',
        ),
        'wonetestb16_ajkt-fix-the-board',
      );
    });

    test('WONETESTA11-I2: a reused stem is warned about, never refused '
        '[1011]', () {
      final reuse = tomTodoStemReuse('scc5_ajkt-x', [
        'scc5_agnd-y',
        'scc6_ajkt-z',
        'scc5_ajkt-w',
      ]);
      expect(reuse, ['scc5_agnd-y']);
      expect(
        tomTodoStemReuseWarning('scc5_ajkt-x', reuse),
        '`scc5` is used by `scc5_agnd-y`; a `scc5*` iteration will take both.',
      );
    });

    test('WONETESTA11-I3: the next base continues the series [1011]', () {
      expect(
        tomNextTodoBase('wonetestb3_ajkn-x', [
          'wonetestb15_ajkt-y',
          'wonetesta22_ajkn',
        ]),
        'wonetestb16',
      );
      expect(tomNextTodoBase('plain', const []), 'plain');
    });
  });

  group('WONETESTA11-J journal', () {
    test('WONETESTA11-J1: an entry is in the tooling\'s format [1011]', () {
      final todo = TomTodo(
        id: 'gx3_ajka-harvest',
        title: 'Harvest',
        decisions: [
          TomTodoDecision(
            summary: 'When',
            decisionNeeded: 'Morning or\nevening?',
            decision: 'Mornings.',
          ),
          TomTodoDecision(summary: 'Who', decisionNeeded: ''),
        ],
      );
      expect(
        tomDecisionJournalEntry(
          todo,
          DateTime.utc(2026, 10, 11, 19, 5, 3, 7, 9),
        ),
        '## 2026-10-11T19:05:03.007Z — `gx3_ajka-harvest` — Harvest\n'
        '\n'
        '1. **When**\n'
        '   - **Needed:** Morning or\n'
        '     evening?\n'
        '   - **Decided:** Mornings.\n'
        '2. **Who**\n'
        '   - **Decided:** _(not decided)_\n',
      );
    });
  });
}
