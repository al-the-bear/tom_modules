/// Editing a series: formatting a rule (the exact inverse of parsing),
/// occurrence actions — this one, this and following, the whole series — and
/// converting between all-day and timed.
library;

import 'package:test/test.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

const idCal = '11111111-1111-4111-8111-111111111111';

CalendarAppointment standup({
  String id = 'a1',
  String? recurrence = 'FREQ=WEEKLY;BYDAY=MO,WE',
  List<DateTime> exceptions = const [],
}) => CalendarAppointment(
  id: id,
  title: 'Standup',
  start: DateTime.utc(2026, 7, 20, 8, 30),
  end: DateTime.utc(2026, 7, 20, 8, 45),
  recurrence: recurrence,
  exceptions: exceptions,
);

void main() {
  group('rule formatting — the inverse of tryParse', () {
    test('emits the canonical part order [0803]', () {
      const rule = CalendarRecurrenceRule(
        freq: CalendarRecurrenceFreq.weekly,
        interval: 2,
        count: 10,
        byDay: [
          CalendarByDay(DateTime.monday),
          CalendarByDay(DateTime.wednesday),
        ],
      );
      expect(rule.format(), 'FREQ=WEEKLY;INTERVAL=2;COUNT=10;BYDAY=MO,WE');
    });

    test('omits INTERVAL=1 — the RFC default is not written [0803]', () {
      const rule = CalendarRecurrenceRule(freq: CalendarRecurrenceFreq.daily);
      expect(rule.format(), 'FREQ=DAILY');
    });

    test('UNTIL is emitted as a UTC timestamp [0803]', () {
      final rule = CalendarRecurrenceRule(
        freq: CalendarRecurrenceFreq.monthly,
        until: DateTime.utc(2026, 12, 31, 23, 59, 59),
        byMonthDay: const [15],
      );
      expect(
        rule.format(),
        'FREQ=MONTHLY;UNTIL=20261231T235959Z;BYMONTHDAY=15',
      );
    });

    test('an all-day UNTIL is emitted as a date [0803]', () {
      final rule = CalendarRecurrenceRule(
        freq: CalendarRecurrenceFreq.daily,
        until: DateTime.utc(2026, 12, 31),
      );
      expect(rule.format(allDay: true), 'FREQ=DAILY;UNTIL=20261231');
    });

    test('a monthly ordinal weekday keeps its ordinal [0803]', () {
      const rule = CalendarRecurrenceRule(
        freq: CalendarRecurrenceFreq.monthly,
        byDay: [CalendarByDay(DateTime.friday, -1)],
      );
      expect(rule.format(), 'FREQ=MONTHLY;BYDAY=-1FR');
    });

    // The property that matters: anything the editor can *emit* must be
    // something the expander can read back identically, or the rule the user
    // sees on reopening is not the rule they built.
    test('format→parse is an identity over the whole subset [0803]', () {
      final rules = <CalendarRecurrenceRule>[
        const CalendarRecurrenceRule(freq: CalendarRecurrenceFreq.daily),
        const CalendarRecurrenceRule(
          freq: CalendarRecurrenceFreq.daily,
          interval: 3,
        ),
        const CalendarRecurrenceRule(
          freq: CalendarRecurrenceFreq.weekly,
          byDay: [
            CalendarByDay(DateTime.monday),
            CalendarByDay(DateTime.friday),
          ],
        ),
        const CalendarRecurrenceRule(
          freq: CalendarRecurrenceFreq.weekly,
          count: 4,
        ),
        CalendarRecurrenceRule(
          freq: CalendarRecurrenceFreq.weekly,
          until: DateTime.utc(2027, 1, 1, 0, 0, 0),
        ),
        const CalendarRecurrenceRule(
          freq: CalendarRecurrenceFreq.monthly,
          byMonthDay: [1],
        ),
        const CalendarRecurrenceRule(
          freq: CalendarRecurrenceFreq.monthly,
          byDay: [CalendarByDay(DateTime.tuesday, 2)],
        ),
        const CalendarRecurrenceRule(freq: CalendarRecurrenceFreq.yearly),
      ];
      for (final rule in rules) {
        expect(
          CalendarRecurrenceRule.tryParse(rule.format()),
          rule,
          reason: rule.format(),
        );
      }
    });

    test('a formatted rule drives the expander [0803]', () {
      const rule = CalendarRecurrenceRule(
        freq: CalendarRecurrenceFreq.weekly,
        byDay: [CalendarByDay(DateTime.monday)],
        count: 3,
      );
      final a = CalendarAppointment(
        id: 'a1',
        title: 'Standup',
        start: DateTime.utc(2026, 7, 20, 8, 30),
        end: DateTime.utc(2026, 7, 20, 8, 45),
        recurrence: rule.format(),
      );
      expect(
        a.occurrencesIn(DateTime.utc(2026, 7, 1), DateTime.utc(2026, 9, 1)),
        [
          DateTime.utc(2026, 7, 20, 8, 30),
          DateTime.utc(2026, 7, 27, 8, 30),
          DateTime.utc(2026, 8, 3, 8, 30),
        ],
      );
    });
  });

  group('occurrence actions', () {
    test(
      'delete this occurrence appends an EXDATE and nothing else [0803]',
      () {
        final list = [standup()];
        final out = CalendarOccurrenceEdit.deleteOccurrence(
          list,
          appointmentId: 'a1',
          occurrenceStart: DateTime.utc(2026, 7, 27, 8, 30),
        );
        expect(out, hasLength(1));
        expect(out.single.exceptions, [DateTime.utc(2026, 7, 27, 8, 30)]);
        expect(out.single.recurrence, 'FREQ=WEEKLY;BYDAY=MO,WE');
        // The occurrence is gone from the expansion — which is the whole point
        // of writing the EXDATE rather than a "cancelled" flag.
        expect(
          out.single.occurrencesIn(
            DateTime.utc(2026, 7, 20),
            DateTime.utc(2026, 8, 1),
          ),
          isNot(contains(DateTime.utc(2026, 7, 27, 8, 30))),
        );
      },
    );

    test('deleting the same occurrence twice is idempotent [0803]', () {
      var list = [standup()];
      for (var i = 0; i < 2; i++) {
        list = CalendarOccurrenceEdit.deleteOccurrence(
          list,
          appointmentId: 'a1',
          occurrenceStart: DateTime.utc(2026, 7, 27, 8, 30),
        );
      }
      expect(list.single.exceptions, hasLength(1));
    });

    test('deleting an occurrence that is not one is refused [0803]', () {
      expect(
        () => CalendarOccurrenceEdit.deleteOccurrence(
          [standup()],
          appointmentId: 'a1',
          // A Tuesday; the series is MO,WE.
          occurrenceStart: DateTime.utc(2026, 7, 21, 8, 30),
        ),
        throwsArgumentError,
      );
    });

    test('detaching an occurrence writes both halves at once [0803]', () {
      final edited = CalendarAppointment(
        id: 'ignored',
        title: 'Standup (long)',
        start: DateTime.utc(2026, 7, 27, 9, 0),
        end: DateTime.utc(2026, 7, 27, 10, 0),
        location: 'Room 2',
      );
      final out = CalendarOccurrenceEdit.detachOccurrence(
        [standup()],
        appointmentId: 'a1',
        occurrenceStart: DateTime.utc(2026, 7, 27, 8, 30),
        edited: edited,
        newId: 'detached-1',
      );
      expect(out, hasLength(2));
      final series = out.firstWhere((a) => a.id == 'a1');
      final detached = out.firstWhere((a) => a.id == 'detached-1');

      // Half one: the series now excludes the detached start.
      expect(series.exceptions, [DateTime.utc(2026, 7, 27, 8, 30)]);
      // Half two: a standalone appointment with the edited values and *no*
      // recurrence — an occurrence that still recurred would be two events.
      expect(detached.recurrence, isNull);
      expect(detached.exceptions, isEmpty);
      expect(detached.title, 'Standup (long)');
      expect(detached.location, 'Room 2');
      expect(detached.start, DateTime.utc(2026, 7, 27, 9, 0));
    });

    test('a detached occurrence keeps the id it was minted with [0803]', () {
      final out = CalendarOccurrenceEdit.detachOccurrence(
        [standup()],
        appointmentId: 'a1',
        occurrenceStart: DateTime.utc(2026, 7, 27, 8, 30),
        edited: standup(id: 'ignored', recurrence: null),
        newId: 'fresh-uuid',
      );
      expect(out.map((a) => a.id), containsAll(['a1', 'fresh-uuid']));
    });

    test('delete the series removes the entry entirely [0803]', () {
      final out = CalendarOccurrenceEdit.deleteSeries([
        standup(),
        standup(id: 'a2', recurrence: null),
      ], appointmentId: 'a1');
      expect(out.map((a) => a.id), ['a2']);
    });

    test('editing the series re-anchors and keeps the exceptions [0803]', () {
      final list = [
        standup(exceptions: [DateTime.utc(2026, 7, 27, 8, 30)]),
      ];
      final edited = CalendarAppointment(
        id: 'a1',
        title: 'Standup',
        start: DateTime.utc(2026, 7, 20, 9, 0),
        end: DateTime.utc(2026, 7, 20, 9, 15),
        recurrence: 'FREQ=WEEKLY;BYDAY=MO,WE',
      );
      final out = CalendarOccurrenceEdit.replaceSeries(
        list,
        appointmentId: 'a1',
        edited: edited,
      );
      expect(out.single.start, DateTime.utc(2026, 7, 20, 9, 0));
      expect(out.single.exceptions, [
        DateTime.utc(2026, 7, 27, 8, 30),
      ], reason: 'exceptions are kept as-is');
    });

    test('an all-day series takes date-only exceptions [0803]', () {
      final conference = CalendarAppointment(
        id: 'c1',
        title: 'Conference',
        allDay: true,
        start: DateTime.utc(2026, 9, 14),
        end: DateTime.utc(2026, 9, 14),
        recurrence: 'FREQ=YEARLY',
      );
      final out = CalendarOccurrenceEdit.deleteOccurrence(
        [conference],
        appointmentId: 'c1',
        occurrenceStart: DateTime.utc(2027, 9, 14),
      );
      expect(out.single.toMap()['exceptions'], ['2027-09-14']);
    });
  });

  group('all-day conversion', () {
    test('to all-day truncates the wall clock on both ends [0803]', () {
      final a = CalendarAppointment(
        id: 'a1',
        title: 'Workshop',
        start: DateTime.utc(2026, 7, 20, 9, 30),
        end: DateTime.utc(2026, 7, 21, 17, 0),
      );
      final out = CalendarAppointmentEditing.setAllDay(a, true);
      expect(out.allDay, isTrue);
      expect(out.toMap()['start'], '2026-07-20');
      // The inclusive last day is the day the timed event ended on.
      expect(out.toMap()['end'], '2026-07-21');
    });

    test('a same-day timed event becomes a one-day all-day event [0803]', () {
      final a = CalendarAppointment(
        id: 'a1',
        title: 'Review',
        start: DateTime.utc(2026, 7, 22, 9, 0),
        end: DateTime.utc(2026, 7, 22, 10, 30),
      );
      final out = CalendarAppointmentEditing.setAllDay(a, true);
      expect(out.toMap()['start'], '2026-07-22');
      expect(out.toMap()['end'], '2026-07-22');
    });

    test('back to timed gives the day a default working window [0803]', () {
      final a = CalendarAppointment(
        id: 'a1',
        title: 'Conference',
        allDay: true,
        start: DateTime.utc(2026, 9, 14),
        end: DateTime.utc(2026, 9, 16),
      );
      final out = CalendarAppointmentEditing.setAllDay(a, false);
      expect(out.allDay, isFalse);
      expect(out.toMap()['start'], '2026-09-14T09:00:00Z');
      // The last *included* day becomes an end on that day, not the midnight
      // that starts it — otherwise a 3-day event silently loses its last day.
      expect(out.toMap()['end'], '2026-09-16T17:00:00Z');
    });

    test('the exceptions change form with the event [0803]', () {
      final a = CalendarAppointment(
        id: 'a1',
        title: 'Standup',
        start: DateTime.utc(2026, 7, 20, 8, 30),
        end: DateTime.utc(2026, 7, 20, 8, 45),
        recurrence: 'FREQ=DAILY',
        exceptions: [DateTime.utc(2026, 7, 22, 8, 30)],
      );
      final out = CalendarAppointmentEditing.setAllDay(a, true);
      expect(out.toMap()['exceptions'], ['2026-07-22']);
    });

    test('toggling all-day is a no-op when it is already set [0803]', () {
      final a = standup();
      expect(CalendarAppointmentEditing.setAllDay(a, false), a);
    });
  });
}
