/// Whose day is meant.
///
/// An instant has no day of its own, so every transform that turns one into a
/// day is told the frame. Two properties are checked: in a frame west of UTC
/// the day produced is the day a user there was reading, and with no frame
/// given the answer is the UTC one on every machine.
library;

import 'package:tom_calendar_model/tom_calendar_model.dart';
import 'package:test/test.dart';

const west = CalendarTimeFrame.fixed(Duration(hours: -5));
const east = CalendarTimeFrame.fixed(Duration(hours: 9));

/// 22 July, 20:00–21:00 five hours west of UTC.
CalendarAppointment evening({String? recurrence, List<DateTime>? exceptions}) =>
    CalendarAppointment(
      id: 'a',
      title: 'Dinner',
      start: DateTime.utc(2026, 7, 23, 1),
      end: DateTime.utc(2026, 7, 23, 2),
      recurrence: recurrence,
      exceptions: exceptions ?? const [],
    );

void main() {
  group('the frame', () {
    test('an instant falls on the day its frame reads', () {
      final t = DateTime.utc(2026, 7, 23, 1);
      expect(west.dateOf(t), DateTime.utc(2026, 7, 22));
      expect(CalendarTimeFrame.utc.dateOf(t), DateTime.utc(2026, 7, 23));
      expect(
        east.dateOf(DateTime.utc(2026, 7, 22, 20)),
        DateTime.utc(2026, 7, 23),
      );
      expect(west.dayShift(t), -1);
      expect(east.dayShift(DateTime.utc(2026, 7, 22, 20)), 1);
      expect(west.dayShift(DateTime.utc(2026, 7, 22, 15)), 0);
    });

    test('wall and instant are inverses', () {
      for (final frame in [west, east, CalendarTimeFrame.utc]) {
        final t = DateTime.utc(2026, 1, 1, 2, 30, 15);
        final w = frame.wall(t);
        expect(
          frame.instant(w.year, w.month, w.day, w.hour, w.minute, w.second),
          t,
        );
      }
    });

    test('the device frame agrees with the platform', () {
      final t = DateTime.utc(2026, 7, 23, 1);
      final local = t.toLocal();
      expect(
        CalendarTimeFrame.device.dateOf(t),
        DateTime.utc(local.year, local.month, local.day),
      );
      expect(
        CalendarTimeFrame.device.instant(2026, 7, 22, 9),
        DateTime(2026, 7, 22, 9).toUtc(),
      );
    });
  });

  group('all-day conversion', () {
    test('west of UTC, all-day is the day the user was reading', () {
      final out = CalendarAppointmentEditing.setAllDay(
        evening(),
        true,
        frame: west,
      );
      expect(out.allDay, isTrue);
      expect(out.start, DateTime.utc(2026, 7, 22));
      expect(out.end, DateTime.utc(2026, 7, 22));
    });

    test('with no frame given the answer is the UTC day', () {
      final out = CalendarAppointmentEditing.setAllDay(evening(), true);
      expect(out.start, DateTime.utc(2026, 7, 23));
      expect(out.end, DateTime.utc(2026, 7, 23));
      expect(
        CalendarAppointmentEditing.setAllDay(
          evening(),
          true,
          frame: CalendarTimeFrame.utc,
        ).toMap(),
        out.toMap(),
      );
    });

    test('to timed, the working day is the frame\'s', () {
      final allDay = CalendarAppointment(
        id: 'a',
        title: 'Offsite',
        allDay: true,
        start: DateTime.utc(2026, 7, 22),
        end: DateTime.utc(2026, 7, 23),
      );
      final out = CalendarAppointmentEditing.setAllDay(
        allDay,
        false,
        frame: west,
      );
      expect(
        out.start,
        DateTime.utc(2026, 7, 22, 14),
        reason: '09:00 five hours west',
      );
      expect(
        out.end,
        DateTime.utc(2026, 7, 23, 22),
        reason: '17:00 on the last included day',
      );
      expect(
        west.wall(out.start).hour,
        CalendarAppointmentEditing.defaultStartHour,
      );

      final headless = CalendarAppointmentEditing.setAllDay(allDay, false);
      expect(headless.start, DateTime.utc(2026, 7, 22, 9));
    });

    test('a round trip returns to the day it left', () {
      final there = CalendarAppointmentEditing.setAllDay(
        evening(),
        true,
        frame: west,
      );
      final back = CalendarAppointmentEditing.setAllDay(
        there,
        false,
        frame: west,
      );
      expect(west.dateOf(back.start), DateTime.utc(2026, 7, 22));
      final again = CalendarAppointmentEditing.setAllDay(
        back,
        true,
        frame: west,
      );
      expect(again.start, there.start);
    });

    test('exceptions change form in the same frame, so they '
        'still name an occurrence', () {
      final series = evening(
        recurrence: 'FREQ=DAILY',
        exceptions: [DateTime.utc(2026, 7, 24, 1)],
      );
      final out = CalendarAppointmentEditing.setAllDay(
        series,
        true,
        frame: west,
      );
      expect(out.exceptions, [DateTime.utc(2026, 7, 23)]);
      expect(
        out.occurrencesIn(DateTime.utc(2026, 7, 22), DateTime.utc(2026, 7, 24)),
        [DateTime.utc(2026, 7, 22), DateTime.utc(2026, 7, 24)],
        reason: 'the 23rd is the cancelled one',
      );
    });

    test('replacing a series with one of the other form carries '
        'its exceptions in the frame of the edit', () {
      final series = evening(
        recurrence: 'FREQ=DAILY',
        exceptions: [DateTime.utc(2026, 7, 24, 1)],
      );
      final edited = CalendarAppointmentEditing.setAllDay(
        series,
        true,
        frame: west,
      );
      final inFrame = CalendarOccurrenceEdit.replaceSeries(
        [series],
        appointmentId: 'a',
        edited: edited,
        frame: west,
      ).single;
      expect(inFrame.exceptions, [DateTime.utc(2026, 7, 23)]);

      final headless = CalendarOccurrenceEdit.replaceSeries(
        [series],
        appointmentId: 'a',
        edited: CalendarAppointmentEditing.setAllDay(series, true),
      ).single;
      expect(headless.exceptions, [DateTime.utc(2026, 7, 24)]);

      final unchanged = CalendarOccurrenceEdit.replaceSeries(
        [series],
        appointmentId: 'a',
        edited: series,
        frame: west,
      ).single;
      expect(
        unchanged.exceptions,
        series.exceptions,
        reason: 'the form did not change, so nothing is converted',
      );
    });
  });

  group('the days a rule names', () {
    CalendarRecurrenceRule rule(String value) =>
        CalendarRecurrenceRule.tryParse(value)!;

    test('a weekday moves with the day, around the week', () {
      final stored = rule('FREQ=WEEKLY;BYDAY=MO,WE');
      expect(
        CalendarRecurrenceEditing.shiftDays(stored, -1).format(),
        'FREQ=WEEKLY;BYDAY=TU,SU',
      );
      expect(
        CalendarRecurrenceEditing.shiftDays(stored, 1).format(),
        'FREQ=WEEKLY;BYDAY=TU,TH',
      );
      expect(CalendarRecurrenceEditing.shiftDays(stored, 0), same(stored));
    });

    test('there and back is the rule it was', () {
      for (final value in [
        'FREQ=WEEKLY;INTERVAL=2;COUNT=5;BYDAY=MO,SU',
        'FREQ=MONTHLY;BYDAY=2TU',
        'FREQ=MONTHLY;BYMONTHDAY=15',
        'FREQ=MONTHLY;BYMONTHDAY=31',
      ]) {
        for (final days in [-1, 1]) {
          final there = CalendarRecurrenceEditing.shiftDays(rule(value), days);
          expect(
            CalendarRecurrenceEditing.shiftDays(there, -days).format(),
            value,
            reason: '$value by $days',
          );
        }
      }
    });

    test('the rule a user west of UTC builds for Wednesday '
        'evening recurs on their Wednesdays', () {
      // Wednesday 22 July, 20:00 five hours west: Thursday in UTC.
      final shown = rule('FREQ=WEEKLY;BYDAY=WE');
      final stored = CalendarRecurrenceEditing.shiftDays(
        shown,
        -west.dayShift(DateTime.utc(2026, 7, 23, 1)),
      );
      expect(stored.format(), 'FREQ=WEEKLY;BYDAY=TH');

      final series = evening(recurrence: stored.format());
      final starts = series.occurrencesIn(
        DateTime.utc(2026, 7, 22),
        DateTime.utc(2026, 8, 12),
      );
      expect(starts, hasLength(3));
      for (final start in starts) {
        expect(west.wall(start).weekday, DateTime.wednesday);
        expect(west.wall(start).hour, 20);
      }
    });
  });
}
