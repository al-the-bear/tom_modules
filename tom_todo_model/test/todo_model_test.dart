/// The shared todo model: the workspace schema's field set, emitted in the
/// schema's order, read back exactly, and the decision rule.
library;

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

/// An item carrying every one of the schema's 28 fields.
TomTodo everyField() => TomTodo(
  id: 'launch-plan',
  title: 'Plan the launch',
  description: 'Venue, budget and the guest list.',
  status: TomTodoStatus.decisionNeeded,
  priority: TomTodoPriority.high,
  due: DateTime.utc(2026, 11, 1),
  estimate: 'PT6H',
  tags: ['launch', 'q4'],
  scope: TomTodoScope(
    project: 'tom_webwork_app',
    projects: ['tom_webwork_ui'],
    module: 'shell',
    area: 'ui',
    files: ['lib/main.dart'],
    path: 'app_webwork',
  ),
  decisions: [
    TomTodoDecision(
      summary: 'Which venue?',
      decisionNeeded: 'Hall A seats 80, Hall B 120.',
    ),
    TomTodoDecision(
      summary: 'Catering?',
      decisionNeeded: 'In-house or external.',
      decision: 'External.',
    ),
  ],
  references: const [
    TomTodoReference(path: 'doc/launch.md', lines: '1-20'),
    TomTodoReference(url: 'https://example.com', type: 'url'),
    TomTodoReference(description: 'The board minutes'),
  ],
  dependencies: ['budget'],
  blockedBy: ['legal-review', 'other_quest/its-todo'],
  blockedUntil: ['tom_basics >= 1.2.0'],
  notes: 'Ask Ada first.',
  created: DateTime.utc(2026, 10, 1),
  updated: DateTime.utc(2026, 10, 11),
  completedDate: DateTime.utc(2026, 10, 12),
  author: 'alexis',
  completedBy: 'ada',
  archived: DateTime.utc(2026, 10, 13),
  deleted: DateTime.utc(2026, 10, 14),
  executionRole: 'implementer',
  qaRole: 'reviewer',
  orchestrationRole: 'lead',
  bundleId: 'launch',
  derivedFrom: 'venue-search',
  feedbackSource: 'retro-2026-10',
);

void main() {
  group('WONETESTA5-A the codec', () {
    test('WONETESTA5-01: the closed field set is the schema\'s 28 fields, '
        'emitted in the schema\'s order [1011]', () {
      expect(TomTodo.fields, hasLength(28));
      expect(everyField().toMap().keys.toList(), [
        'id',
        'title',
        'description',
        'status',
        'priority',
        'due',
        'estimate',
        'tags',
        'scope',
        'decisions',
        'references',
        'dependencies',
        'blocked_by',
        'blocked_until',
        'notes',
        'created',
        'updated',
        'completed_date',
        'author',
        'completed_by',
        'archived',
        'deleted',
        'execution_role',
        'qa_role',
        'orchestration_role',
        'bundle_id',
        'derived_from',
        'feedback_source',
      ]);
    });

    test('WONETESTA5-02: every field survives toMap → fromMap [1011]', () {
      final original = everyField();
      final read = TomTodo.fromMap(original.toMap());
      expect(read, original);
      expect(read.decisions.first.isOpen, isTrue);
      expect(read.decisions.last.decision, 'External.');
      expect(read.scope!.files, ['lib/main.dart']);
      expect(read.references[1].url, 'https://example.com');
      expect(read.bundleId, 'launch');
      expect(read.feedbackSource, 'retro-2026-10');
    });

    test('WONETESTA5-03: copy() is detached and complete [1011]', () {
      final original = everyField();
      final copy = original.copy()
        ..decisions.first.decision = 'Hall B'
        ..scope!.area = 'api';
      expect(copy, isNot(original));
      expect(original.decisions.first.isOpen, isTrue);
      expect(original.scope!.area, 'ui');
    });

    test(
      'WONETESTA5-04: what the schema refuses, the codec refuses [1011]',
      () {
        final base = everyField().toMap();
        expect(
          () => TomTodo.fromMap({...base, 'effort': 3}),
          throwsFormatException,
        );
        expect(
          () => TomTodo.fromMap({
            ...base,
            'decisions': [
              {'summary': 's', 'decision_needed': 'q', 'why': 'x'},
            ],
          }),
          throwsFormatException,
        );
        expect(
          () => TomTodo.fromMap({
            ...base,
            'references': [
              {'lines': '1-2'},
            ],
          }),
          throwsFormatException,
          reason: 'a reference needs a path, a url or a description',
        );
        expect(
          () => TomTodo.fromMap({...base, 'created': '2026-10'}),
          throwsFormatException,
        );
        expect(
          () => TomTodo(id: 'x', title: 'x', blockedUntil: ['tom_basics soon']),
          throwsFormatException,
        );
      },
    );
  });

  group('WONETESTA5-C the decision rule', () {
    TomTodo open() => TomTodo(
      id: 'x',
      title: 'x',
      decisions: [TomTodoDecision(summary: 's', decisionNeeded: 'q')],
    );

    test('WONETESTA5-09: an edit that opens a question makes the todo '
        'decision-needed [1011]', () {
      final before = TomTodo(id: 'x', title: 'x');
      final after = open();
      expect(tomApplyDecisionRule(after, previous: before), isTrue);
      expect(after.status, TomTodoStatus.decisionNeeded);
    });

    test('WONETESTA5-10: answering the last open question moves it back to '
        'not-started [1011]', () {
      final before = open()..status = TomTodoStatus.decisionNeeded;
      final after = before.copy()..decisions.single.decision = 'Yes';
      expect(tomApplyDecisionRule(after, previous: before), isTrue);
      expect(after.status, TomTodoStatus.notStarted);
    });

    test('WONETESTA5-11: a done todo keeps its status, and a hand-set '
        'decision-needed with no question change is left alone [1011]', () {
      final done = open()..status = TomTodoStatus.completed;
      expect(
        tomApplyDecisionRule(
          done,
          previous: TomTodo(id: 'x', title: 'x'),
        ),
        isFalse,
      );
      expect(done.status, TomTodoStatus.completed);

      final byHand = TomTodo(
        id: 'x',
        title: 'x',
        status: TomTodoStatus.decisionNeeded,
      );
      expect(
        tomApplyDecisionRule(
          byHand,
          previous: TomTodo(id: 'x', title: 'x'),
        ),
        isFalse,
      );
      expect(byHand.status, TomTodoStatus.decisionNeeded);
    });
  });

  group('the status and the completion facts', () {
    test(
      'entering completed records the date and who, leaving clears them',
      () {
        final todo = TomTodo(id: 'x', title: 'x');
        final on = DateTime.utc(2026, 10, 21, 15);
        todo.changeStatus(TomTodoStatus.completed, on: on, by: 'ada');
        expect(todo.completedDate, DateTime.utc(2026, 10, 21));
        expect(todo.completedBy, 'ada');
        expect(todo.updated, DateTime.utc(2026, 10, 21));
        todo.changeStatus(TomTodoStatus.inProgress, on: on);
        expect(todo.completedDate, isNull);
        expect(todo.completedBy, isNull);
      },
    );

    test('every status and priority reads back from its wire name', () {
      for (final s in TomTodoStatus.values) {
        expect(TomTodoStatus.fromWire(s.wire), s);
      }
      for (final p in TomTodoPriority.values) {
        expect(TomTodoPriority.fromWire(p.wire), p);
      }
      expect(() => TomTodoStatus.fromWire('done'), throwsFormatException);
    });
  });

  group('TODOMODEL-D a date is the calendar day it names', () {
    // A date field is a calendar day. The model used to turn an incoming
    // DateTime into its UTC day, so a local value moved by a day wherever the
    // machine is not on UTC: east of it, 00:30 local became yesterday; west of
    // it, 23:30 local became tomorrow. Both are asserted, so the test fails on
    // any machine off UTC, whichever side it is on.
    test('TODOMODEL-D1: a local DateTime keeps its own day [1021]', () {
      for (final hour in [0, 23]) {
        final when = DateTime(2026, 10, 21, hour, 30);
        final todo = TomTodo(id: 'd1', title: 'Dated', due: when, completedDate: when);
        expect(todo.toMap()['due'], '2026-10-21', reason: '$hour:30 local');
        expect(todo.toMap()['completed_date'], '2026-10-21', reason: '$hour:30 local');
        expect(TomTodo.encodeDate(when), '2026-10-21', reason: '$hour:30 local');
      }
    });

    test('TODOMODEL-D2: a UTC DateTime keeps its UTC day; a stored date reads back unchanged [1021]', () {
      expect(TomTodo.encodeDate(DateTime.utc(2026, 10, 21, 23, 30)), '2026-10-21');
      final read = TomTodo.fromMap({'id': 'd2', 'title': 'Read', 'status': 'completed', 'completed_date': '2026-10-21'});
      expect(read.toMap()['completed_date'], '2026-10-21');
      expect(read.completedDate, DateTime.utc(2026, 10, 21));
    });
  });
}
