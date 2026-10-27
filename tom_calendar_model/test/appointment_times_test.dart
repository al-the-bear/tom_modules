/// How an appointment's time is said: in UTC, beside the wall clock of the
/// place it was created in, and on a screen in the device's.
library;

import 'package:test/test.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

const tokyo = CalendarTimeFrame.fixed(Duration(hours: 9));
const berlin = CalendarTimeFrame.fixed(Duration(hours: 2));

CalendarAppointment meeting({String? createdIn = '+02:00'}) =>
    CalendarAppointment(
      id: 'a',
      title: 'Review',
      start: DateTime.utc(2026, 7, 22, 9),
      end: DateTime.utc(2026, 7, 22, 10),
      createdIn: createdIn,
    );

void main() {
  group('what is said', () {
    test('with no device, UTC and where it was created', () {
      expect(
        calendarDescribeTimes(meeting()),
        '2026-07-22 09:00–10:00 UTC · '
        '2026-07-22 11:00–12:00 where created (UTC+02:00)',
      );
    });

    test('on a device elsewhere, all three', () {
      expect(
        calendarDescribeTimes(meeting(), local: tokyo),
        '2026-07-22 09:00–10:00 UTC · '
        '2026-07-22 18:00–19:00 local (UTC+09:00) · '
        '2026-07-22 11:00–12:00 where created (UTC+02:00)',
      );
    });

    test('a device where it was created is one frame, not two', () {
      expect(
        calendarDescribeTimes(meeting(), local: berlin),
        '2026-07-22 09:00–10:00 UTC · '
        '2026-07-22 11:00–12:00 local (UTC+02:00)',
      );
    });

    test('a device at UTC adds nothing to UTC, and says that '
        'UTC is local', () {
      expect(
        calendarDescribeTimes(
          meeting(createdIn: null),
          local: CalendarTimeFrame.utc,
        ),
        '2026-07-22 09:00–10:00 UTC (local)',
      );
      expect(
        calendarDescribeTimes(meeting(createdIn: '+00:00')),
        '2026-07-22 09:00–10:00 UTC',
      );
    });

    test('nothing recorded, nothing claimed', () {
      expect(
        calendarDescribeTimes(meeting(createdIn: null)),
        '2026-07-22 09:00–10:00 UTC',
      );
    });

    test('a frame in which it crosses midnight shows both '
        'dates', () {
      final late = CalendarAppointment(
        id: 'a',
        title: 'Late',
        start: DateTime.utc(2026, 7, 22, 14),
        end: DateTime.utc(2026, 7, 22, 16),
      );
      expect(
        calendarDescribeTimes(late, local: tokyo),
        '2026-07-22 14:00–16:00 UTC · '
        '2026-07-22 23:00 – 2026-07-23 01:00 local (UTC+09:00)',
      );
    });

    test('an all-day appointment is a date, in no frame', () {
      final day = CalendarAppointment(
        id: 'd',
        title: 'Holiday',
        allDay: true,
        start: DateTime.utc(2026, 7, 22),
        end: DateTime.utc(2026, 7, 23),
        createdIn: '+02:00',
      );
      expect(
        calendarDescribeTimes(day, local: tokyo),
        '2026-07-22 – 2026-07-23 (all day)',
      );
    });
  });
}
