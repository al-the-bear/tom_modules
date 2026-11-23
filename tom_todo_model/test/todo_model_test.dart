/// The shared todo model: the workspace schema's field set, emitted in the
/// schema's order, read back exactly, and the decision rule.
library;

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

/// An item carrying every one of the schema's 39 fields.
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
  blocking: ['launch-party', 'other_quest/press'],
  comprisedOf: ['budget', 'other_quest/venue'],
  blockedUntil: ['tom_basics >= 1.2.0'],
  userAction: true,
  repeat: TomTodoRepeat(
    rule: TomTodoRepeatRule.monthly,
    nth: -1,
    weekday: 'fri',
    time: '10:00',
  ),
  nextRepeat: '2026-11-27T10:00+01:00',
  repeatCount: 2,
  remind: TomTodoRepeat(
    rule: TomTodoRepeatRule.weekly,
    weekdays: ['mon'],
    time: '09:00',
  ),
  nextRemind: '2026-11-23T09:00+01:00',
  remindCount: 1,
  dueReminded: '2026-10-20T09:00+02:00',
  notes: 'Ask Ada first.',
  created: DateTime.utc(2026, 10, 1),
  updated: DateTime.utc(2026, 10, 11),
  completedDate: DateTime.utc(2026, 10, 12),
  author: 'alexis',
  completedBy: 'ada',
  lastAnswer: 'Done: the venue is booked.',
  archived: DateTime.utc(2026, 10, 13),
  deleted: DateTime.utc(2026, 10, 14),
  executionRole: 'implementer',
  qaRole: 'reviewer',
  orchestrationRole: 'lead',
  bundleId: 'launch',
  derivedFrom: 'venue-search',
  feedbackSource: 'retro-2026-10',
  onDone: TomTodoOnDone(
    quest: 'tom_core',
    run: 'chg7',
    todos: ['tsm_a3_akll-wire-vault'],
    action: [TomTodoOnDoneAction.unblock, TomTodoOnDoneAction.notify],
    instructions: 'Check the vault first.',
    notifyPrompt: 'The launch plan is done.',
    reportTo: 'ideas/x/x.md#todos',
  ),
  filedBy: TomTodoFiledBy(
    quest: 'al_the_bear',
    run: 'default',
    session: 'chat',
    todo: 'atb12_aklk-idea-to-todos',
    at: '2026-11-12T15:20+01:00',
  ),
  resources: ['tom_vscode', 'infra:vsix-release'],
  claimHold: true,
  claimFree: true,
);

void main() {
  group('WONETESTA5-A the codec', () {
    test('WONETESTA5-01: the closed field set is the schema\'s 64 fields; '
        'the 3.x fields are emitted in the 3.x order [1011]', () {
      expect(TomItem.fields, hasLength(64));
      final threeX = everyField().toMap().keys.toList();
      expect(
        TomItem.fields.where(threeX.contains).toList(),
        threeX,
        reason: 'the 3.x keys keep their relative order in the 4.0 field list',
      );
      expect(threeX, [
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
        'blocking',
        'comprised_of',
        'blocked_until',
        'user_action',
        'repeat',
        'next_repeat',
        'repeat_count',
        'remind',
        'next_remind',
        'remind_count',
        'due_reminded',
        'notes',
        'created',
        'updated',
        'completed_date',
        'author',
        'completed_by',
        'last_answer',
        'archived',
        'deleted',
        'execution_role',
        'qa_role',
        'orchestration_role',
        'bundle_id',
        'derived_from',
        'feedback_source',
        'on_done',
        'filed_by',
        'resources',
        'claim_hold',
        'claim_free',
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
      expect(read.userAction, isTrue);
      expect(read.blocking, ['launch-party', 'other_quest/press']);
      expect(read.comprisedOf, ['budget', 'other_quest/venue']);
      expect(read.lastAnswer, 'Done: the venue is booked.');
      expect(read.onDone!.action, [
        TomTodoOnDoneAction.unblock,
        TomTodoOnDoneAction.notify,
      ]);
      expect(read.filedBy!.at, '2026-11-12T15:20+01:00');
      expect(read.resources, ['tom_vscode', 'infra:vsix-release']);
      expect(read.claimHold && read.claimFree, isTrue);
    });

    test('TODOMODEL-LA1: last_answer is written only when set, and a string '
        'reads back [1105]', () {
      final plain = TomTodo(
        id: 'a',
        title: 'A',
        status: TomTodoStatus.completed,
      );
      expect(plain.lastAnswer, isNull);
      expect(plain.toMap().containsKey('last_answer'), isFalse);
      final answered = plain.copy()..lastAnswer = '# Done\n\nAll green.';
      expect(answered.toMap()['last_answer'], '# Done\n\nAll green.');
      expect(
        TomTodo.fromMap(answered.toMap()).lastAnswer,
        '# Done\n\nAll green.',
      );
      expect(
        answered.copy().lastAnswer,
        '# Done\n\nAll green.',
        reason: 'copy() carries it',
      );
      expect(
        () => TomTodo.fromMap({...plain.toMap(), 'last_answer': 42}),
        throwsA(anything),
      );
    });

    test('TODOMODEL-U1: user_action is written only when true, and only a '
        'boolean reads back [1027]', () {
      final plain = TomTodo(
        id: 'a',
        title: 'A',
        status: TomTodoStatus.notStarted,
      );
      expect(plain.userAction, isFalse);
      expect(
        plain.toMap().containsKey('user_action'),
        isFalse,
        reason: 'an agent\'s todo writes nothing new',
      );
      final users = plain.copy()..userAction = true;
      expect(users.toMap()['user_action'], isTrue);
      expect(TomTodo.fromMap(users.toMap()).userAction, isTrue);
      expect(
        TomTodo.fromMap({...plain.toMap(), 'user_action': false}).userAction,
        isFalse,
      );
      expect(
        () => TomTodo.fromMap({...plain.toMap(), 'user_action': 'yes'}),
        throwsFormatException,
      );
      expect(users.copy().userAction, isTrue, reason: 'copy() carries it');
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

  group('COLLAB2 on_done, filed_by and the claim fields', () {
    final plain = TomTodo(id: 'a', title: 'A');

    test(
      'COLLAB2-01: absent fields write nothing; each reads back as stored',
      () {
        final map = plain.toMap();
        for (final key in [
          'on_done',
          'filed_by',
          'resources',
          'claim_hold',
          'claim_free',
        ]) {
          expect(map.containsKey(key), isFalse, reason: key);
        }
        final stored = {
          ...map,
          'on_done': {
            'todos': ['b', 'other/c'],
            'action': ['unblock'],
          },
          'filed_by': {'session': 'chat', 'at': '2026-11-12T15:20Z'},
          'resources': ['github/al-the-bear/tom_vscode'],
          'claim_hold': true,
          'claim_free': false,
        };
        final read = TomTodo.fromMap(stored);
        expect(read.toMap(), {
          ...map,
          'on_done': {
            'todos': ['b', 'other/c'],
            'action': ['unblock'],
          },
          'filed_by': {'session': 'chat', 'at': '2026-11-12T15:20Z'},
          'resources': ['github/al-the-bear/tom_vscode'],
          'claim_hold': true,
        }, reason: 'claim_free: false is written as absent');
      },
    );

    test(
      'COLLAB2-02: resources: [] claims nothing and is kept, unlike an absent list',
      () {
        final none = TomTodo.fromMap({
          ...plain.toMap(),
          'resources': <String>[],
        });
        expect(none.resources, isEmpty);
        expect(none.toMap()['resources'], isEmpty);
        expect(none.copy().resources, isEmpty);
        expect(plain.resources, isNull);
      },
    );

    test(
      'COLLAB2-03: the actions; the retired queue and none read as nothing',
      () {
        final onDone = TomTodoOnDone.fromMap({
          'todos': ['b'],
        });
        expect(onDone.action, isEmpty);
        expect(onDone.toMap(), {
          'todos': ['b'],
        });
        expect(TomTodoOnDone().toMap(), isEmpty);
        expect(TomTodoOnDoneAction.values.map((a) => a.wire), [
          'unblock',
          'notify',
        ]);
        final old = TomTodoOnDone.fromMap({
          'action': ['none', 'queue', 'notify'],
          'instructions': 'go',
        });
        expect(old.action, [TomTodoOnDoneAction.notify]);
        expect(old.toMap(), {
          'action': ['notify'],
          'instructions': 'go',
        });
        expect(
          () => TomTodoOnDone.fromMap({
            'action': ['wake'],
          }),
          throwsFormatException,
        );
      },
    );

    test(
      'COLLAB2-05: a decision without decision_needed reads back as written',
      () {
        final stored = {'summary': 'Scope', 'decision': 'Narrowed.'};
        expect(TomTodoDecision.fromMap(stored).toMap(), stored);
        expect(TomTodoDecision(summary: 's', decisionNeeded: 'q?').toMap(), {
          'summary': 's',
          'decision_needed': 'q?',
        });
      },
    );

    test('COLLAB2-04: copy() is detached', () {
      final original = everyField();
      final copy = original.copy()
        ..onDone!.todos.add('other')
        ..filedBy!.session = 'idea'
        ..resources!.add('tom_core');
      expect(original.onDone!.todos, ['tsm_a3_akll-wire-vault']);
      expect(original.filedBy!.session, 'chat');
      expect(original.resources, ['tom_vscode', 'infra:vsix-release']);
      expect(copy, isNot(original));
    });

    test('COLLAB2-05: what the schema refuses, the codec refuses', () {
      final base = plain.toMap();
      expect(
        () => TomTodo.fromMap({
          ...base,
          'on_done': {'when': 'later'},
        }),
        throwsFormatException,
        reason: 'on_done is closed',
      );
      expect(
        () => TomTodo.fromMap({
          ...base,
          'on_done': {
            'action': ['wake'],
          },
        }),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({
          ...base,
          'on_done': {'action': 'unblock'},
        }),
        throwsFormatException,
        reason: 'action is a list',
      );
      expect(
        () => TomTodo.fromMap({
          ...base,
          'filed_by': {'host': 'mbp'},
        }),
        throwsFormatException,
        reason: 'filed_by is closed',
      );
      expect(
        () => TomTodo.fromMap({
          ...base,
          'filed_by': {'at': '2026-11-12'},
        }),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({...base, 'claim_hold': 'yes'}),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({...base, 'claim_free': 1}),
        throwsFormatException,
      );
    });

    test('COLLAB2-06: every action reads back from its wire name', () {
      for (final a in TomTodoOnDoneAction.values) {
        expect(TomTodoOnDoneAction.fromWire(a.wire), a);
      }
    });

    test('COLLAB2-07: a todo file writes and reads the new fields', () {
      const text =
          'todos:\n  - id: a\n    title: A\n    description: D\n    status: not-started\n';
      final file = TomTodoFile.parse(text);
      final todo = file.entries.single.todo!.copy()
        ..onDone = TomTodoOnDone(
          todos: ['b'],
          action: [TomTodoOnDoneAction.unblock],
        )
        ..filedBy = TomTodoFiledBy(quest: 'q', at: '2026-11-12T15:20+01:00')
        ..resources = []
        ..claimHold = true;
      final written = TomTodoFile.parse(file.withTodo(0, todo));
      final read = written.entries.single.todo!;
      expect(read, todo);
      expect(read.resources, isEmpty);
    });
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
        final todo = TomTodo(
          id: 'd1',
          title: 'Dated',
          due: when,
          completedDate: when,
        );
        expect(todo.toMap()['due'], '2026-10-21', reason: '$hour:30 local');
        expect(
          todo.toMap()['completed_date'],
          '2026-10-21',
          reason: '$hour:30 local',
        );
        expect(
          TomTodo.encodeDate(when),
          '2026-10-21',
          reason: '$hour:30 local',
        );
      }
    });

    test(
      'TODOMODEL-D2: a UTC DateTime keeps its UTC day; a stored date reads back unchanged [1021]',
      () {
        expect(
          TomTodo.encodeDate(DateTime.utc(2026, 10, 21, 23, 30)),
          '2026-10-21',
        );
        final read = TomTodo.fromMap({
          'id': 'd2',
          'title': 'Read',
          'status': 'completed',
          'completed_date': '2026-10-21',
        });
        expect(read.toMap()['completed_date'], '2026-10-21');
        expect(read.completedDate, DateTime.utc(2026, 10, 21));
      },
    );
  });

  group('todo groups (3.0.0)', () {
    test('TODOGROUP-1: status `group` reads and writes its wire name', () {
      expect(TomTodoStatus.fromWire('group'), TomTodoStatus.group);
      expect(TomTodoStatus.group.wire, 'group');
      expect(TomTodoStatus.values.map((s) => s.wire), contains('group'));
    });

    test('TODOGROUP-2: a group todo with comprised_of round-trips; it is '
        'neither done nor open work', () {
      final g = TomTodo.fromMap({
        'id': 'grp1_akpt-release',
        'title': 'Release',
        'status': 'group',
        'comprised_of': ['grp2_akpt-build', 'other_quest/its-todo'],
      });
      expect(g.isGroup, isTrue);
      expect(g.isDone, isFalse);
      expect(g.comprisedOf, ['grp2_akpt-build', 'other_quest/its-todo']);
      expect(g.toMap()['status'], 'group');
      expect(g.toMap()['comprised_of'], [
        'grp2_akpt-build',
        'other_quest/its-todo',
      ]);
      expect(TomTodo.fromMap(g.toMap()), g);
      expect(
        TomTodo.fromMap({
          'id': 'x1',
          'title': 'x',
          'status': 'not-started',
        }).toMap(),
        isNot(contains('comprised_of')),
        reason: 'an empty list is not written',
      );
    });

    test('TODOGROUP-3: part_of is derived, never a field of the model', () {
      expect(TomTodo.fields, isNot(contains('part_of')));
    });
  });

  group('due_reminded (3.1.0)', () {
    test('round-trips verbatim beside due, and is in the closed field set', () {
      final todo = TomTodo.fromMap({
        'id': 'later',
        'title': 'Clean up',
        'status': 'not-started',
        'due': '2026-12-01',
        'due_reminded': '2026-12-01T09:00+01:00',
      });
      expect(todo.dueReminded, '2026-12-01T09:00+01:00');
      expect(todo.toMap()['due_reminded'], '2026-12-01T09:00+01:00');
      expect(TomTodo.fromMap(todo.toMap()), todo);
      expect(todo.copy().dueReminded, '2026-12-01T09:00+01:00');
      expect(TomTodo.fields, contains('due_reminded'));
    });

    test('a malformed moment is a format error', () {
      expect(
        () => TomTodo.fromMap({
          'id': 'later',
          'title': 'Clean up',
          'status': 'not-started',
          'due_reminded': 'tomorrow',
        }),
        throwsFormatException,
      );
    });

    test('a change of due clears it, the same date keeps it', () {
      final todo = TomTodo(
        id: 'later',
        title: 'Clean up',
        due: DateTime(2026, 12, 1),
        dueReminded: '2026-12-01T09:00Z',
      );
      todo.due = DateTime(2026, 12, 1);
      expect(todo.dueReminded, '2026-12-01T09:00Z');
      todo.due = DateTime(2026, 12, 8);
      expect(todo.dueReminded, isNull);
    });
  });

  group('role and guidelines (4.2.0)', () {
    TomItem item({
      String? role,
      Map<String, List<String>> guidelines = const {},
    }) => TomItem(
      id: 'g1',
      headline: 'Tune it',
      workflow: TomItemWorkflow(
        executionRole: 'software_engineer',
        bundleId: 'b1',
        role: role,
        guidelines: guidelines,
        derivedFrom: 'g0',
      ),
    );

    test('ROLEGL-1: both round-trip, written after bundle_id and before '
        'derived_from, in the flat field set and the workflow fields', () {
      final original = item(
        role: 'idea_author',
        guidelines: {
          'answer_mode': ['answer tool'],
          'night': ['remove'],
        },
      );
      final map = original.toMap();
      final keys = map.keys.toList();
      expect(
        keys.sublist(
          keys.indexOf('bundle_id'),
          keys.indexOf('derived_from') + 1,
        ),
        ['bundle_id', 'role', 'guidelines', 'derived_from'],
      );
      expect(map['role'], 'idea_author');
      expect(map['guidelines'], {
        'answer_mode': 'answer tool',
        'night': 'remove',
      });
      final read = TomItem.fromMap(map);
      expect(read, original);
      expect(read.workflow!.role, 'idea_author');
      expect(read.workflow!.guidelines['night'], [
        TomItemWorkflow.removeGuideline,
      ]);
      final flat = TomItem.fields.toList();
      expect(
        flat.sublist(flat.indexOf('bundle_id'), flat.indexOf('bundle_id') + 4),
        ['bundle_id', 'role', 'guidelines', 'derived_from'],
      );
      expect(
        TomItemWorkflow.fields,
        containsAllInOrder(['bundle_id', 'role', 'guidelines', 'derived_from']),
      );
    });

    test('ROLEGL-2: neither is written when unset; an empty guidelines map '
        'is not written either', () {
      final map = item().toMap();
      expect(map.containsKey('role'), isFalse);
      expect(map.containsKey('guidelines'), isFalse);
      final read = TomItem.fromMap({
        'id': 'x',
        'title': 'X',
        'guidelines': <String, String>{},
      });
      expect(read.workflow?.guidelines ?? const {}, isEmpty);
      expect(read.toMap().containsKey('guidelines'), isFalse);
    });

    test('ROLEGL-3: a role alone makes the workflow extension present', () {
      final read = TomItem.fromMap({
        'id': 'x',
        'title': 'X',
        'role': 'reviewer',
      });
      expect(read.workflow, isNotNull);
      expect(read.workflow!.role, 'reviewer');
    });

    test('ROLEGL-4: copy() is detached', () {
      final original = item(
        role: 'a',
        guidelines: {
          's': ['o'],
        },
      );
      final copy = original.copy();
      copy.workflow!.guidelines['s']!.add('other');
      copy.workflow!.role = 'b';
      expect(original.workflow!.guidelines['s'], ['o']);
      expect(original.workflow!.role, 'a');
    });

    test('ROLEGL-5: what is no role folder name or no section / option name '
        'is a format error', () {
      Map<String, Object?> with_(String key, Object? value) => {
        'id': 'x',
        'title': 'X',
        key: value,
      };
      for (final bad in ['', ' reviewer', 'a/b', '_hidden', 'two words']) {
        expect(
          () => TomItem.fromMap(with_('role', bad)),
          throwsFormatException,
          reason: 'role "$bad"',
        );
      }
      for (final bad in <Object>[
        'answer tool',
        ['a'],
        {'': 'o'},
        {'s': ''},
        {'s/t': 'o'},
        {'s': ' o'},
        {'s': 'o\n'},
        {'s': 1},
        {
          's': ['a', '+b'],
        },
        {
          's': ['remove', 'a'],
        },
        {
          's': ['+'],
        },
        {
          's': [1],
        },
      ]) {
        expect(
          () => TomItem.fromMap(with_('guidelines', bad)),
          throwsFormatException,
          reason: 'guidelines $bad',
        );
      }
      expect(
        TomItem.fromMap(
          with_('guidelines', {'answer_mode': 'trail only'}),
        ).workflow!.guidelines,
        {
          'answer_mode': ['trail only'],
        },
      );
    });

    test('ROLEGL-7: several choices (6.0.0): a list replaces, a list of '
        '"+" entries adds, a single choice stays a string', () {
      final original = item(
        guidelines: {
          'js_ts': ['vscode_extension', 'react'],
          'dart': ['+flutter'],
          'night': ['on'],
          'tone': ['+dry'],
        },
      );
      final map = original.toMap();
      expect(map['guidelines'], {
        'js_ts': ['vscode_extension', 'react'],
        'dart': '+flutter',
        'night': 'on',
        'tone': '+dry',
      });
      expect(TomItem.fromMap(map), original);
      expect(
        TomItem.fromMap({
          'id': 'x',
          'title': 'X',
          'guidelines': {
            'dart': ['+packages', '+flutter'],
          },
        }).workflow!.guidelines,
        {
          'dart': ['+packages', '+flutter'],
        },
      );
    });

    test('ROLEGL-6: a todo file writes and reads both, keeping the rest', () {
      const text =
          'todos:\n  - id: a\n    title: A\n    status: not-started\n    bundle_id: b1\n    derived_from: z\n';
      final file = TomTodoFile.parse(text);
      final todo = file.entries.single.item!.copy();
      (todo.workflow ??= TomItemWorkflow())
        ..role = 'idea_author'
        ..guidelines = {
          'answer_mode': ['answer tool'],
        };
      final written = file.withItem(0, todo);
      expect(
        written,
        contains('    bundle_id: b1\n    role: idea_author\n    guidelines:\n'),
      );
      final read = TomTodoFile.parse(written).entries.single.item!;
      expect(read, todo);
      expect(read.workflow!.derivedFrom, 'z');
    });
  });
}
