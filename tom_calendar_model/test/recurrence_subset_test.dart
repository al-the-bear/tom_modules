/// The RRULE subset a rule is parsed into, and the appointment schema.
library;

import 'package:test/test.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

const _ical = ICalendarCodec(
  prodId: '-//Test//tom_calendar_model//EN',
  extensionPrefix: 'X-TEST',
);

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

String _ics(String body) =>
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Test//EN\r\n'
    '$body\r\n'
    'END:VCALENDAR\r\n';

CalendarAppointment _series(String rule, {bool allDay = false}) =>
    CalendarAppointment(
      id: 'series',
      title: 'Series',
      allDay: allDay,
      start: allDay ? DateTime.utc(2026, 7, 6) : DateTime.utc(2026, 7, 6, 9),
      end: allDay ? DateTime.utc(2026, 7, 6) : DateTime.utc(2026, 7, 6, 10),
      recurrence: rule,
    );

void main() {
  // -------------------------------------------------------------------------
  // (1) exactly the subset
  // -------------------------------------------------------------------------
  group('tryParse accepts exactly the recurrence subset', () {
    /// Asserts [rule] is refused and that a series carrying it takes the degrade
    /// path: its base occurrence alone, and the rule kept byte-for-byte.
    void expectRefused(String rule, {bool allDay = false}) {
      expect(
        CalendarRecurrenceRule.tryParse(rule),
        isNull,
        reason: '"$rule" is outside the recurrence subset',
      );
      final a = _series(rule, allDay: allDay);
      expect(a.recurrenceRule, isNull);
      expect(
        a.occurrencesIn(DateTime.utc(2026), DateTime.utc(2028)),
        [a.start],
        reason: 'a refused rule renders its base occurrence only',
      );
      final reread = CalendarAppointment.fromMap(a.toMap());
      expect(reread.recurrence, rule, reason: 'kept verbatim in YAML');
      final decoded = _ical.decode(
        _ical.encode(events: [ICalendarEvent(appointment: a)]),
      );
      expect(
        decoded.events.single.appointment.recurrence,
        rule,
        reason: 'kept verbatim through an iCalendar round-trip',
      );
      expect(
        decoded.warnings.map((w) => w.kind),
        contains(ICalendarWarningKind.unsupportedRecurrence),
      );
    }

    test('COUNT together with UNTIL is refused', () {
      expectRefused('FREQ=DAILY;COUNT=3;UNTIL=20261231T000000Z');
    });

    test('a repeated part is refused', () {
      expectRefused('FREQ=WEEKLY;BYDAY=MO;BYDAY=TU');
      expectRefused('FREQ=DAILY;FREQ=WEEKLY');
      expectRefused('FREQ=DAILY;INTERVAL=2;INTERVAL=3');
    });

    test('a timed UNTIL without Z is refused', () {
      expectRefused('FREQ=DAILY;UNTIL=20261231T090000');
    });

    test('MONTHLY with several BYDAY values is refused', () {
      expectRefused('FREQ=MONTHLY;BYDAY=1MO,3MO');
    });

    test('MONTHLY with several BYMONTHDAY values is refused', () {
      expectRefused('FREQ=MONTHLY;BYMONTHDAY=1,15');
    });

    test('MONTHLY with BYDAY and BYMONTHDAY together is refused', () {
      expectRefused('FREQ=MONTHLY;BYDAY=2TU;BYMONTHDAY=15');
    });

    test('a plain weekday on MONTHLY is refused', () {
      expectRefused('FREQ=MONTHLY;BYDAY=TU');
    });

    test('BYDAY on YEARLY is refused', () {
      expectRefused('FREQ=YEARLY;BYDAY=1MO');
      expectRefused('FREQ=YEARLY;BYDAY=MO');
    });

    test('BYMONTHDAY on YEARLY is refused', () {
      expectRefused('FREQ=YEARLY;BYMONTHDAY=4');
    });

    test('BYMONTHDAY on WEEKLY is refused', () {
      expectRefused('FREQ=WEEKLY;BYMONTHDAY=3');
    });

    test('the subset itself is still accepted and expanded', () {
      const accepted = [
        'FREQ=DAILY',
        'FREQ=DAILY;INTERVAL=2;COUNT=3',
        'FREQ=DAILY;UNTIL=20261231T235959Z',
        'FREQ=DAILY;UNTIL=20261231',
        'FREQ=WEEKLY;BYDAY=MO,WE,FR',
        'FREQ=WEEKLY;INTERVAL=2;COUNT=6;BYDAY=MO,WE',
        'FREQ=MONTHLY',
        'FREQ=MONTHLY;BYDAY=2TU',
        'FREQ=MONTHLY;BYDAY=-1FR',
        'FREQ=MONTHLY;BYMONTHDAY=15',
        'FREQ=MONTHLY;BYMONTHDAY=-1',
        'FREQ=YEARLY',
        'FREQ=YEARLY;INTERVAL=2;COUNT=4',
      ];
      for (final rule in accepted) {
        final parsed = CalendarRecurrenceRule.tryParse(rule);
        expect(parsed, isNotNull, reason: rule);
        expect(
          CalendarRecurrenceRule.tryParse(parsed!.format()),
          parsed,
          reason: '$rule: format is the inverse of tryParse',
        );
      }
      final weekly = _series('FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE');
      expect(weekly.occurrencesIn(DateTime.utc(2026), DateTime.utc(2028)), [
        DateTime.utc(2026, 7, 6, 9),
        DateTime.utc(2026, 7, 8, 9),
        DateTime.utc(2026, 7, 13, 9),
        DateTime.utc(2026, 7, 15, 9),
      ]);
    });

    test('a refused rule is not offered to the repeat control', () {
      // An editor branches on this predicate: a refused rule is shown
      // read-only behind the badge instead of being loaded into controls that
      // would re-emit it as a different rule.
      expect(
        CalendarRecurrenceEditing.isInterpretable('FREQ=MONTHLY;BYDAY=TU'),
        isFalse,
      );
      expect(
        CalendarRecurrenceEditing.isInterpretable('FREQ=MONTHLY;BYDAY=2TU'),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // (5) the schema on read, and minted ids
  // -------------------------------------------------------------------------
  group('the appointment schema', () {
    Map<String, Object?> map({Object? id = 'a', Object? allDay}) => {
      'id': id,
      'title': 'T',
      'start': '2026-07-22',
      'end': '2026-07-22',
      'allDay': ?allDay,
    };

    test('an empty id is refused on read', () {
      expect(
        () => CalendarAppointment.fromMap(map(id: '', allDay: true)),
        throwsFormatException,
      );
    });

    test('a non-boolean allDay is refused on read', () {
      for (final bad in ['true', 'yes', 1]) {
        expect(
          () => CalendarAppointment.fromMap(map(allDay: bad)),
          throwsFormatException,
          reason: 'allDay: $bad',
        );
      }
      expect(CalendarAppointment.fromMap(map(allDay: true)).allDay, isTrue);
    });

    test('an id the import mints is a UUID', () {
      final result = _ical.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'DTSTART:20260722T090000Z\r\n'
          'SUMMARY:No UID\r\n'
          'END:VEVENT',
        ),
      );
      expect(result.events.single.appointment.id, matches(_uuid));
      expect(
        result.warnings.map((w) => w.kind),
        contains(ICalendarWarningKind.mintedUid),
      );
    });
  });
}
