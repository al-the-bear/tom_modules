/// Repeated todos: the `waiting-for-repeat` status, the `repeat` rule, the
/// `next_repeat` moment and the `repeat_count`, read and written as the
/// workspace schema has them.
library;

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

void main() {
  group('TODOREPEAT-A the codec', () {
    test(
      'a weekly rule round-trips in the schema order, defaults left out',
      () {
        final map = {
          'id': 'standup',
          'title': 'Weekly status',
          'status': 'waiting-for-repeat',
          'repeat': {
            'rule': 'weekly',
            'every': 2,
            'weekdays': ['mon', 'thu'],
            'time': '09:00',
            'until': '2027-06-30',
            'count': 10,
          },
          'next_repeat': '2026-11-16T09:00+01:00',
          'repeat_count': 3,
        };
        final todo = TomTodo.fromMap(map);
        expect(todo.status, TomTodoStatus.waitingForRepeat);
        expect(todo.isRepeated, isTrue);
        expect(todo.isDone, isFalse, reason: 'waiting is an open status');
        expect(todo.repeat!.weekdays, ['mon', 'thu']);
        expect(todo.toMap(), map);
        expect(todo.copy(), todo);
      },
    );

    test('the day forms of monthly and yearly', () {
      Map<String, Object?> rt(Map<String, Object?> r) =>
          TomTodoRepeat.fromMap(r).toMap();
      expect(rt({'rule': 'monthly', 'day': 15}), {
        'rule': 'monthly',
        'day': 15,
      });
      expect(rt({'rule': 'monthly', 'day': 'last'}), {
        'rule': 'monthly',
        'day': 'last',
      });
      expect(rt({'rule': 'monthly', 'nth': 2, 'weekday': 'tue'}), {
        'rule': 'monthly',
        'nth': 2,
        'weekday': 'tue',
      });
      expect(rt({'rule': 'monthly', 'nth': 'last', 'weekday': 'fri'}), {
        'rule': 'monthly',
        'nth': 'last',
        'weekday': 'fri',
      });
      expect(rt({'rule': 'monthly', 'working_day': 'last'}), {
        'rule': 'monthly',
        'working_day': 'last',
      });
      expect(rt({'rule': 'yearly', 'month': 3, 'day': 1}), {
        'rule': 'yearly',
        'month': 3,
        'day': 1,
      });
      expect(rt({'rule': 'after', 'every': 10, 'unit': 'days'}), {
        'rule': 'after',
        'every': 10,
        'unit': 'days',
      });
      expect(rt({'rule': 'manual'}), {'rule': 'manual'});
    });

    test('a rule the schema does not allow is a format error', () {
      for (final bad in <Map<String, Object?>>[
        {'rule': 'hourly'},
        {'rule': 'weekly'},
        {'rule': 'after', 'every': 2},
        {'rule': 'monthly'},
        {'rule': 'monthly', 'day': 15, 'nth': 1, 'weekday': 'mon'},
        {'rule': 'monthly', 'day': 32},
        {'rule': 'monthly', 'nth': 2},
        {'rule': 'yearly', 'day': 1},
        {'rule': 'daily', 'every': 0},
        {'rule': 'daily', 'time': '9:00'},
        {'rule': 'daily', 'colour': 'red'},
        {
          'rule': 'weekly',
          'weekdays': ['monday'],
        },
      ]) {
        expect(
          () => TomTodoRepeat.fromMap(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(
        () => TomTodo.fromMap({
          'id': 'a',
          'title': 'a',
          'next_repeat': '2026-11-16',
        }),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({'id': 'a', 'title': 'a', 'repeat_count': 'two'}),
        throwsFormatException,
      );
    });

    test('the new fields are part of the closed field set', () {
      expect(
        TomTodo.fields,
        containsAll(['repeat', 'next_repeat', 'repeat_count']),
      );
      expect(
        TomTodoStatus.fromWire('waiting-for-repeat'),
        TomTodoStatus.waitingForRepeat,
      );
    });
  });

  group('TODOREPEAT-B the reminder schedule', () {
    test(
      'remind, next_remind and remind_count round-trip after the repeat fields',
      () {
        final map = {
          'id': 'invoice',
          'title': 'Send the invoice',
          'status': 'not-started',
          'repeat': {'rule': 'monthly', 'day': 1},
          'remind': {
            'rule': 'weekly',
            'weekdays': ['mon', 'thu'],
            'time': '09:00',
            'count': 4,
          },
          'next_remind': '2026-11-23T09:00+01:00',
          'remind_count': 2,
        };
        final todo = TomTodo.fromMap(map);
        expect(todo.remind!.weekdays, ['mon', 'thu']);
        expect(todo.nextRemind, '2026-11-23T09:00+01:00');
        expect(todo.remindCount, 2);
        expect(todo.toMap(), map);
        expect(todo.copy(), todo);
        expect(
          TomTodo.fields,
          containsAll(['remind', 'next_remind', 'remind_count']),
        );
        expect(
          TomItem.planningFields,
          containsAll(['remind', 'next_remind', 'remind_count']),
        );
      },
    );

    test('a manual reminder rule and malformed values are format errors', () {
      expect(
        () => TomTodo.fromMap({
          'id': 'a',
          'title': 'a',
          'remind': {'rule': 'manual'},
        }),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({
          'id': 'a',
          'title': 'a',
          'remind': {'rule': 'weekly'},
        }),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({
          'id': 'a',
          'title': 'a',
          'next_remind': '2026-11-23',
        }),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({'id': 'a', 'title': 'a', 'remind_count': 'two'}),
        throwsFormatException,
      );
      expect(
        () => TomTodo.fromMap({'id': 'a', 'title': 'a', 'remind_count': -1}),
        throwsFormatException,
      );
    });
  });
}
