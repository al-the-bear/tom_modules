/// A task — the codec's `VTODO` — and how it crosses the wire: the RFC 5545
/// properties it has, the extension properties under the producer's prefix,
/// and what an import infers from a foreign file.
library;

import 'package:test/test.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

const _codec = ICalendarCodec(
  prodId: '-//Test//tom_calendar_model//EN',
  extensionPrefix: 'X-TEST',
);

String _ics(String body) =>
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Other//EN\r\n'
    '$body\r\n'
    'END:VCALENDAR\r\n';

String _todo(String properties) =>
    _ics('BEGIN:VTODO\r\nUID:t1\r\nSUMMARY:Task\r\n${properties}END:VTODO');

void main() {
  group('the task value', () {
    test('a priority is 1 to 9, or none', () {
      for (final p in [1, 5, 9]) {
        expect(CalendarTask(id: 'a', title: 'A', priority: p).priority, p);
      }
      for (final p in [0, 10, -1]) {
        expect(
          () => CalendarTask(id: 'a', title: 'A', priority: p),
          throwsArgumentError,
        );
      }
    });

    test('a due date keeps only its UTC date', () {
      final task = CalendarTask(
        id: 'a',
        title: 'A',
        due: DateTime.utc(2026, 7, 6, 18, 30),
      );
      expect(task.due, DateTime.utc(2026, 7, 6));
    });

    test('equality compares the lists and the carried fields by value', () {
      CalendarTask make() => CalendarTask(
        id: 'a',
        title: 'A',
        tags: ['x'],
        dependencies: ['b'],
        fields: {
          'notes': 'n',
          'nested': {
            'k': [1, 2],
          },
        },
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make(), isNot(CalendarTask(id: 'a', title: 'A')));
    });

    test('a status names its wire form, and only a known one reads back', () {
      for (final s in CalendarTaskStatus.values) {
        expect(CalendarTaskStatus.fromWire(s.wire), s);
      }
      expect(CalendarTaskStatus.fromWire('DONE'), isNull);
    });
  });

  group('the wire', () {
    test('every field round-trips, the facets under the given prefix', () {
      final task = CalendarTask(
        id: 'agenda',
        title: 'Write; the, agenda',
        description: 'Line one\nline two',
        status: CalendarTaskStatus.inProcess,
        priority: 2,
        due: DateTime.utc(2026, 7, 6),
        estimate: '2h',
        tags: ['team', 'weekly'],
        dependencies: ['room'],
        fields: {'owner': 'ann', 'checked': true},
      );
      final ics = _codec.encode(
        tasks: [ICalendarTask(task: task, anchor: 'list')],
      );
      expect(ics, contains('X-TEST-ESTIMATE:2h'));
      expect(ics, contains('X-TEST-TAGS:'));
      expect(ics, contains('X-TEST-FIELDS:'));
      expect(ics, contains('X-TEST-SECTION:list'));
      expect(ics, contains('STATUS:IN-PROCESS'));
      final back = _codec.decode(ics);
      expect(back.writtenByProducer, isTrue);
      expect(back.warnings, isEmpty);
      expect(back.tasks.single.task, task);
      expect(back.tasks.single.anchor, 'list');
    });

    test('another producer\'s extension properties are not read as ours', () {
      final back = _codec.decode(_todo('X-OTHER-ESTIMATE:2h\r\n'));
      expect(back.tasks.single.task.estimate, isNull);
      expect(back.writtenByProducer, isFalse);
      expect(
        back.warnings.map((w) => w.kind),
        contains(ICalendarWarningKind.droppedProperty),
      );
    });

    test('PERCENT-COMPLETE decides the status only when STATUS is absent', () {
      CalendarTaskStatus statusOf(String props) =>
          _codec.decode(_todo(props)).tasks.single.task.status;
      expect(
        statusOf('PERCENT-COMPLETE:0\r\n'),
        CalendarTaskStatus.needsAction,
      );
      expect(statusOf('PERCENT-COMPLETE:40\r\n'), CalendarTaskStatus.inProcess);
      expect(
        statusOf('PERCENT-COMPLETE:100\r\n'),
        CalendarTaskStatus.completed,
      );
      expect(
        statusOf('STATUS:CANCELLED\r\nPERCENT-COMPLETE:100\r\n'),
        CalendarTaskStatus.cancelled,
      );
    });

    test('an unknown STATUS is reported and read as NEEDS-ACTION', () {
      final back = _codec.decode(_todo('STATUS:WAITING\r\n'));
      expect(back.tasks.single.task.status, CalendarTaskStatus.needsAction);
      expect(
        back.warnings.single.message,
        contains('"WAITING" is not recognised; treated as NEEDS-ACTION'),
      );
    });

    test('a PRIORITY outside 1 to 9 is no priority', () {
      int? priorityOf(String value) => _codec
          .decode(_todo('PRIORITY:$value\r\n'))
          .tasks
          .single
          .task
          .priority;
      expect(priorityOf('0'), isNull);
      expect(priorityOf('12'), isNull);
      expect(priorityOf('9'), 9);
    });

    test('fields that are not a JSON object are reported and dropped, and '
        'the task still imports', () {
      final back = _codec.decode(_todo('X-TEST-FIELDS:[1\\,2]\r\n'));
      expect(back.tasks.single.task.title, 'Task');
      expect(back.tasks.single.task.fields, isNull);
      expect(
        back.warnings.single.message,
        contains('X-TEST-FIELDS of VTODO t1 could not be read'),
      );
    });

    test('a timed DUE keeps its date', () {
      final back = _codec.decode(_todo('DUE:20260706T183000Z\r\n'));
      expect(back.tasks.single.task.due, DateTime.utc(2026, 7, 6));
    });
  });
}
