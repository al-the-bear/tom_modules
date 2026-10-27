/// The iCalendar codec's conformance: the appointment schema, the time policy,
/// recurrence and export/import of events.
///
/// This is a regression barrier collected from real-provider-shaped
/// constructs: each group pins a construct that once threw, silently
/// corrupted or silently dropped data.
library;

import 'package:test/test.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';

const _prodId = '-//Test//tom_calendar_model//EN';
const _codec = ICalendarCodec(prodId: _prodId, extensionPrefix: 'X-TEST');

/// Wraps VEVENT/VTODO body lines in a foreign VCALENDAR envelope — the shape
/// an import actually arrives in.
String _ics(String body) =>
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Test//EN\r\n'
    '$body\r\n'
    'END:VCALENDAR\r\n';

/// The same body inside the codec's own envelope — what
/// [ICalendarCodec.encode] must produce. Only the PRODID differs, so a
/// decode→encode round-trip is a fixed point on the component bodies.
String _out(String body) =>
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:$_prodId\r\n'
    '$body\r\n'
    'END:VCALENDAR\r\n';

void main() {
  // ---------------------------------------------------------------------
  // Construct 1 — the subset that always worked. Kept so the extension
  // cannot regress it.
  // ---------------------------------------------------------------------
  group('construct 1 — UTC VEVENT baseline', () {
    const ics =
        'BEGIN:VEVENT\r\n'
        'UID:9b1c6c1e-6f7a-4d9c-9a1b-2f3e4d5c6b7a\r\n'
        'DTSTAMP:19700101T000000Z\r\n'
        'DTSTART:20260722T090000Z\r\n'
        'DTEND:20260722T103000Z\r\n'
        'SUMMARY:Sprint review\r\n'
        'DESCRIPTION:Bring the demo build.\r\n'
        'LOCATION:Room 2\r\n'
        'X-TEST-SECTION:7f3c9e21-1111-4a5b-8c6d-000000000001\r\n'
        'END:VEVENT';

    test('decodes every mapped field and the section anchor', () {
      final result = _codec.decode(_ics(ics));
      expect(result.events, hasLength(1));
      final e = result.events.single;
      expect(e.appointment.id, '9b1c6c1e-6f7a-4d9c-9a1b-2f3e4d5c6b7a');
      expect(e.appointment.title, 'Sprint review');
      expect(e.appointment.start, DateTime.utc(2026, 7, 22, 9));
      expect(e.appointment.end, DateTime.utc(2026, 7, 22, 10, 30));
      expect(e.appointment.description, 'Bring the demo build.');
      expect(e.appointment.location, 'Room 2');
      expect(e.appointment.allDay, isFalse);
      expect(e.anchor, '7f3c9e21-1111-4a5b-8c6d-000000000001');
      expect(result.warnings, isEmpty);
    });

    test('re-encodes to the same document (round-trip is a fixed point)', () {
      final result = _codec.decode(_ics(ics));
      expect(_codec.encode(events: result.events), _out(ics));
    });
  });

  // ---------------------------------------------------------------------
  // Construct 2 — all-day: a DATE value decodes as a date, not an error.
  // ---------------------------------------------------------------------
  group('construct 2 — all-day VALUE=DATE', () {
    const ics =
        'BEGIN:VEVENT\r\n'
        'UID:4f8e2d3c-1a2b-4c5d-8e9f-0a1b2c3d4e5f\r\n'
        'DTSTAMP:19700101T000000Z\r\n'
        'DTSTART;VALUE=DATE:20260914\r\n'
        'DTEND;VALUE=DATE:20260917\r\n'
        'SUMMARY:Conference\r\n'
        'END:VEVENT';

    test(
      'decodes as all-day with an INCLUSIVE end (wire end is exclusive)',
      () {
        final a = _codec.decode(_ics(ics)).events.single.appointment;
        expect(a.allDay, isTrue);
        expect(a.start, DateTime.utc(2026, 9, 14));
        // Wire DTEND 20260917 is exclusive → the last included day is the 16th.
        expect(a.end, DateTime.utc(2026, 9, 16));
      },
    );

    test('encodes back to the exclusive wire form', () {
      final result = _codec.decode(_ics(ics));
      expect(_codec.encode(events: result.events), _out(ics));
    });

    test('a missing DTEND is a single-day event', () {
      final a = _codec
          .decode(
            _ics(
              'BEGIN:VEVENT\r\n'
              'UID:u1\r\n'
              'DTSTART;VALUE=DATE:20260914\r\n'
              'SUMMARY:One day\r\n'
              'END:VEVENT',
            ),
          )
          .events
          .single
          .appointment;
      expect(a.allDay, isTrue);
      expect(a.start, DateTime.utc(2026, 9, 14));
      expect(a.end, DateTime.utc(2026, 9, 14));
    });

    test('an all-day appointment serializes to date-only YAML', () {
      final a = CalendarAppointment(
        id: 'u1',
        title: 'Conference',
        allDay: true,
        start: DateTime.utc(2026, 9, 14),
        end: DateTime.utc(2026, 9, 16),
      );
      expect(a.toMap(), {
        'id': 'u1',
        'title': 'Conference',
        'start': '2026-09-14',
        'end': '2026-09-16',
        'allDay': true,
      });
      expect(CalendarAppointment.fromMap(a.toMap()), a);
    });
  });

  // ---------------------------------------------------------------------
  // Construct 3 — TZID / floating time. A local wall clock read as UTC is
  // wrong by the zone offset, so the reinterpretation is always reported.
  // ---------------------------------------------------------------------
  group('construct 3 — TZID and floating times', () {
    test('a TZID value is taken as UTC but ALWAYS warns — never silent', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:tz1\r\n'
          'DTSTART;TZID=America/New_York:20260101T090000\r\n'
          'DTEND;TZID=America/New_York:20260101T100000\r\n'
          'SUMMARY:Kickoff\r\n'
          'END:VEVENT',
        ),
      );
      final a = result.events.single.appointment;
      expect(a.start, DateTime.utc(2026, 1, 1, 9));
      final warnings = result.warnings.where(
        (w) => w.kind == ICalendarWarningKind.assumedUtc,
      );
      expect(
        warnings,
        isNotEmpty,
        reason:
            'treating TZID as UTC is permitted, but it requires a '
            'per-event warning; the shipped bug was the SILENCE',
      );
      expect(warnings.first.uid, 'tz1');
      expect(warnings.first.message, contains('America/New_York'));
    });

    test('a floating time (no Z, no TZID) is taken as UTC and warns', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:float1\r\n'
          'DTSTART:20260101T090000\r\n'
          'DTEND:20260101T100000\r\n'
          'SUMMARY:Floating\r\n'
          'END:VEVENT',
        ),
      );
      expect(
        result.events.single.appointment.start,
        DateTime.utc(2026, 1, 1, 9),
      );
      expect(
        result.warnings.where((w) => w.kind == ICalendarWarningKind.assumedUtc),
        isNotEmpty,
      );
    });

    test('a UTC "Z" value produces no timezone warning', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:z1\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:Clean\r\n'
          'END:VEVENT',
        ),
      );
      expect(
        result.warnings.where((w) => w.kind == ICalendarWarningKind.assumedUtc),
        isEmpty,
      );
    });

    test('DURATION substitutes for a missing DTEND', () {
      final a = _codec
          .decode(
            _ics(
              'BEGIN:VEVENT\r\n'
              'UID:d1\r\n'
              'DTSTART:20260101T090000Z\r\n'
              'DURATION:PT1H30M\r\n'
              'SUMMARY:Timed by duration\r\n'
              'END:VEVENT',
            ),
          )
          .events
          .single
          .appointment;
      expect(a.end, DateTime.utc(2026, 1, 1, 10, 30));
    });
  });

  // ---------------------------------------------------------------------
  // Construct 4 — RRULE + EXDATE + VALARM + ATTENDEE. The series keeps its
  // rule and exceptions, and VALARM / ATTENDEE are dropped with a warning.
  // ---------------------------------------------------------------------
  group('construct 4 — recurrence and dropped properties', () {
    const ics =
        'BEGIN:VEVENT\r\n'
        'UID:7d6e5f4a-3b2c-4d1e-9f8a-7b6c5d4e3f2a\r\n'
        'DTSTAMP:19700101T000000Z\r\n'
        'DTSTART:20260720T083000Z\r\n'
        'DTEND:20260720T084500Z\r\n'
        'SUMMARY:Standup\r\n'
        'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR\r\n'
        'EXDATE:20260724T083000Z\r\n'
        'ATTENDEE;CN=Ann:mailto:ann@example.com\r\n'
        'BEGIN:VALARM\r\n'
        'TRIGGER:-PT15M\r\n'
        'ACTION:DISPLAY\r\n'
        'END:VALARM\r\n'
        'END:VEVENT';

    test('RRULE and EXDATE survive verbatim on the model', () {
      final a = _codec.decode(_ics(ics)).events.single.appointment;
      expect(a.recurrence, 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
      expect(a.exceptions, [DateTime.utc(2026, 7, 24, 8, 30)]);
    });

    test('ATTENDEE and the VALARM component are dropped WITH a warning', () {
      final dropped = _codec
          .decode(_ics(ics))
          .warnings
          .where((w) => w.kind == ICalendarWarningKind.droppedProperty)
          .map((w) => w.message)
          .join('\n');
      expect(dropped, contains('ATTENDEE'));
      expect(dropped, contains('VALARM'));
    });

    test('a dropped property warns once per NAME per import', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:m1\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:A\r\n'
          'CATEGORIES:work\r\n'
          'END:VEVENT\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:m2\r\n'
          'DTSTART:20260102T090000Z\r\n'
          'DTEND:20260102T100000Z\r\n'
          'SUMMARY:B\r\n'
          'CATEGORIES:home\r\n'
          'END:VEVENT',
        ),
      );
      final categories = result.warnings.where(
        (w) =>
            w.kind == ICalendarWarningKind.droppedProperty &&
            w.message.contains('CATEGORIES'),
      );
      expect(
        categories,
        hasLength(1),
        reason: 'two events drop CATEGORIES; the report carries one entry',
      );
    });

    test('RRULE and EXDATE are re-emitted', () {
      final result = _codec.decode(_ics(ics));
      final out = _codec.encode(events: result.events);
      expect(out, contains('RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR\r\n'));
      expect(out, contains('EXDATE:20260724T083000Z\r\n'));
    });

    test('an all-day series emits EXDATE with VALUE=DATE', () {
      final out = _codec.encode(
        events: [
          ICalendarEvent(
            appointment: CalendarAppointment(
              id: 'ad1',
              title: 'Holiday',
              allDay: true,
              start: DateTime.utc(2026, 1, 1),
              end: DateTime.utc(2026, 1, 1),
              recurrence: 'FREQ=YEARLY',
              exceptions: [DateTime.utc(2027, 1, 1)],
            ),
          ),
        ],
      );
      expect(out, contains('EXDATE;VALUE=DATE:20270101\r\n'));
    });

    test('an RRULE outside the recurrence subset is preserved and warns', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:odd1\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:Odd\r\n'
          'RRULE:FREQ=MINUTELY;INTERVAL=20\r\n'
          'END:VEVENT',
        ),
      );
      final a = result.events.single.appointment;
      expect(
        a.recurrence,
        'FREQ=MINUTELY;INTERVAL=20',
        reason: 'never rewrite or discard a rule we cannot read',
      );
      expect(a.recurrenceRule, isNull, reason: 'not interpretable → degrades');
      expect(
        result.warnings.where(
          (w) => w.kind == ICalendarWarningKind.unsupportedRecurrence,
        ),
        isNotEmpty,
      );
      expect(
        _codec.encode(events: result.events),
        contains('RRULE:FREQ=MINUTELY;INTERVAL=20\r\n'),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Recurrence expansion. `occurrencesOn` answers in occurrences, so a
  // series shows on every day it occurs and not only on its first.
  // ---------------------------------------------------------------------
  group('recurrence expansion', () {
    CalendarAppointment weekdayStandup() => CalendarAppointment(
      id: 's1',
      title: 'Standup',
      start: DateTime.utc(2026, 7, 20, 8, 30), // a Monday
      end: DateTime.utc(2026, 7, 20, 8, 45),
      recurrence: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
      exceptions: [DateTime.utc(2026, 7, 24, 8, 30)], // that Friday
    );

    test('WEEKLY;BYDAY expands to each listed weekday', () {
      final starts = weekdayStandup().occurrencesIn(
        DateTime.utc(2026, 7, 20),
        DateTime.utc(2026, 7, 26, 23, 59, 59),
      );
      expect(starts, [
        DateTime.utc(2026, 7, 20, 8, 30),
        DateTime.utc(2026, 7, 21, 8, 30),
        DateTime.utc(2026, 7, 22, 8, 30),
        DateTime.utc(2026, 7, 23, 8, 30),
        // the 24th is excluded by EXDATE
      ]);
    });

    test('occurrencesOn answers per occurrence, not per series entry', () {
      final s = weekdayStandup();
      expect(s.occurrencesOn(DateTime.utc(2026, 7, 22)).isNotEmpty, isTrue);
      expect(
        s.occurrencesOn(DateTime.utc(2026, 7, 24)).isNotEmpty,
        isFalse,
        reason: 'excluded by EXDATE',
      );
      expect(
        s.occurrencesOn(DateTime.utc(2026, 7, 25)).isNotEmpty,
        isFalse,
        reason: 'Saturday is not in BYDAY',
      );
      expect(
        s.occurrencesOn(DateTime.utc(2026, 7, 27)).isNotEmpty,
        isTrue,
        reason: 'the series is unbounded — the next Monday recurs',
      );
    });

    test('DAILY;INTERVAL;COUNT is bounded by COUNT', () {
      final a = CalendarAppointment(
        id: 'd1',
        title: 'Every other day',
        start: DateTime.utc(2026, 3, 1, 12),
        end: DateTime.utc(2026, 3, 1, 13),
        recurrence: 'FREQ=DAILY;INTERVAL=2;COUNT=3',
      );
      expect(a.occurrencesIn(DateTime.utc(2026, 3), DateTime.utc(2026, 4)), [
        DateTime.utc(2026, 3, 1, 12),
        DateTime.utc(2026, 3, 3, 12),
        DateTime.utc(2026, 3, 5, 12),
      ]);
    });

    test('UNTIL is inclusive', () {
      final a = CalendarAppointment(
        id: 'u1',
        title: 'Weekly',
        start: DateTime.utc(2026, 3, 2, 9),
        end: DateTime.utc(2026, 3, 2, 10),
        recurrence: 'FREQ=WEEKLY;UNTIL=20260316T090000Z',
      );
      expect(a.occurrencesIn(DateTime.utc(2026, 3), DateTime.utc(2026, 4)), [
        DateTime.utc(2026, 3, 2, 9),
        DateTime.utc(2026, 3, 9, 9),
        DateTime.utc(2026, 3, 16, 9),
      ]);
    });

    test('MONTHLY;BYDAY=2TU picks the second Tuesday', () {
      final a = CalendarAppointment(
        id: 'm1',
        title: 'Board',
        start: DateTime.utc(2026, 1, 13, 15),
        end: DateTime.utc(2026, 1, 13, 16),
        recurrence: 'FREQ=MONTHLY;BYDAY=2TU',
      );
      expect(a.occurrencesIn(DateTime.utc(2026), DateTime.utc(2026, 4)), [
        DateTime.utc(2026, 1, 13, 15),
        DateTime.utc(2026, 2, 10, 15),
        DateTime.utc(2026, 3, 10, 15),
      ]);
    });

    test('MONTHLY;BYDAY=-1FR picks the last Friday', () {
      final a = CalendarAppointment(
        id: 'm2',
        title: 'Retro',
        start: DateTime.utc(2026, 1, 30, 16),
        end: DateTime.utc(2026, 1, 30, 17),
        recurrence: 'FREQ=MONTHLY;BYDAY=-1FR',
      );
      expect(a.occurrencesIn(DateTime.utc(2026), DateTime.utc(2026, 3)), [
        DateTime.utc(2026, 1, 30, 16),
        DateTime.utc(2026, 2, 27, 16),
      ]);
    });

    test('MONTHLY;BYMONTHDAY=31 skips months that have no 31st', () {
      final a = CalendarAppointment(
        id: 'm3',
        title: 'Month end',
        start: DateTime.utc(2026, 1, 31, 9),
        end: DateTime.utc(2026, 1, 31, 10),
        recurrence: 'FREQ=MONTHLY;BYMONTHDAY=31',
      );
      expect(a.occurrencesIn(DateTime.utc(2026), DateTime.utc(2026, 5)), [
        DateTime.utc(2026, 1, 31, 9),
        DateTime.utc(2026, 3, 31, 9),
        // no 31 February or April
      ]);
    });

    test('YEARLY on Feb 29 only recurs in leap years', () {
      final a = CalendarAppointment(
        id: 'y1',
        title: 'Leap day',
        start: DateTime.utc(2024, 2, 29, 12),
        end: DateTime.utc(2024, 2, 29, 13),
        recurrence: 'FREQ=YEARLY',
      );
      expect(a.occurrencesIn(DateTime.utc(2024), DateTime.utc(2029)), [
        DateTime.utc(2024, 2, 29, 12),
        DateTime.utc(2028, 2, 29, 12),
      ]);
    });

    test('an uninterpretable rule renders as its base occurrence only', () {
      final a = CalendarAppointment(
        id: 'x1',
        title: 'Odd',
        start: DateTime.utc(2026, 5, 4, 9),
        end: DateTime.utc(2026, 5, 4, 10),
        recurrence: 'FREQ=MINUTELY;INTERVAL=20',
      );
      expect(a.recurrenceRule, isNull);
      expect(a.occurrencesIn(DateTime.utc(2026, 5), DateTime.utc(2026, 6)), [
        DateTime.utc(2026, 5, 4, 9),
      ]);
    });

    test('an occurrence keeps the series duration and drops the rule', () {
      final occurrence = weekdayStandup().occurrenceAt(
        DateTime.utc(2026, 7, 22, 8, 30),
      );
      expect(occurrence.id, 's1');
      expect(occurrence.start, DateTime.utc(2026, 7, 22, 8, 30));
      expect(occurrence.end, DateTime.utc(2026, 7, 22, 8, 45));
      expect(occurrence.recurrence, isNull);
      expect(occurrence.exceptions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // Construct 6 — foreign preservation, and the warnings report.
  // ---------------------------------------------------------------------
  group('construct 6 — foreign material and the warnings report', () {
    test('a foreign UID is preserved verbatim (re-import is idempotent)', () {
      const foreign =
          '040000008200E00074C5B7101A82E00800000000B0D1C7A6E5D9DA01000000000000000'
          '0100000009F2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D';
      final a = _codec
          .decode(
            _ics(
              'BEGIN:VEVENT\r\n'
              'UID:$foreign\r\n'
              'DTSTART:20260101T090000Z\r\n'
              'DTEND:20260101T100000Z\r\n'
              'SUMMARY:From Outlook\r\n'
              'END:VEVENT',
            ),
          )
          .events
          .single
          .appointment;
      expect(a.id, foreign);
      // The UID is 79 octets, so RFC 5545 §3.1 requires the encoder to fold it
      // — the verbatim guarantee is about the *unfolded content*, not the wire
      // bytes, so re-import (not substring search) is what proves it.
      final reencoded = _codec.encode(events: [ICalendarEvent(appointment: a)]);
      expect(reencoded, contains('UID:'));
      expect(_codec.decode(reencoded).events.single.appointment.id, foreign);
    });

    test('a missing UID is minted and warned about', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:Anonymous\r\n'
          'END:VEVENT',
        ),
      );
      expect(result.events, hasLength(1));
      expect(result.events.single.appointment.id, isNotEmpty);
      expect(
        result.warnings.where((w) => w.kind == ICalendarWarningKind.mintedUid),
        hasLength(1),
      );
    });

    test('a component missing DTSTART/SUMMARY is skipped and REPORTED', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:broken\r\n'
          'DESCRIPTION:no start, no summary\r\n'
          'END:VEVENT',
        ),
      );
      expect(result.events, isEmpty);
      expect(
        result.warnings.where(
          (w) => w.kind == ICalendarWarningKind.skippedComponent,
        ),
        hasLength(1),
        reason: 'import never silently loses a whole event',
      );
    });

    test('ORGANIZER and CATEGORIES are reported as dropped', () {
      final dropped = _codec
          .decode(
            _ics(
              'BEGIN:VEVENT\r\n'
              'UID:f1\r\n'
              'DTSTART:20260101T090000Z\r\n'
              'DTEND:20260101T100000Z\r\n'
              'SUMMARY:Foreign\r\n'
              'ORGANIZER:mailto:boss@example.com\r\n'
              'CATEGORIES:work,urgent\r\n'
              'END:VEVENT',
            ),
          )
          .warnings
          .where((w) => w.kind == ICalendarWarningKind.droppedProperty)
          .map((w) => w.message)
          .join('\n');
      expect(dropped, contains('ORGANIZER'));
      expect(dropped, contains('CATEGORIES'));
    });

    // Found by the real corpus, not by a spec reading. A CalDAV
    // collection GET hoists a VTIMEZONE per distinct TZID to the top of the
    // export, beside the events rather than inside one. The decoder skipped
    // every top-level line it did not recognise, so those blocks — and a
    // VJOURNAL or VFREEBUSY with them — vanished without a word, while a
    // VALARM *inside* an event was correctly reported. The import contract admits no
    // such asymmetry: what the import discards, the report names.
    test('a top-level component the codec does not model is REPORTED', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VTIMEZONE\r\n'
          'TZID:Europe/Berlin\r\n'
          'BEGIN:DAYLIGHT\r\n'
          'DTSTART:20000326T020000\r\n'
          'TZOFFSETFROM:+0100\r\n'
          'TZOFFSETTO:+0200\r\n'
          'END:DAYLIGHT\r\n'
          'END:VTIMEZONE\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:after-the-timezone\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:Still parsed\r\n'
          'END:VEVENT',
        ),
      );
      // The nested STANDARD/DAYLIGHT blocks must not desynchronise the
      // parser: the event after the VTIMEZONE still arrives.
      expect(result.events.single.appointment.id, 'after-the-timezone');
      final dropped = result.warnings
          .where((w) => w.kind == ICalendarWarningKind.droppedProperty)
          .map((w) => w.message)
          .toList();
      expect(dropped, contains(contains('VTIMEZONE')));
      expect(
        dropped,
        isNot(contains(contains('DAYLIGHT'))),
        reason:
            'the inner blocks are part of the one component skipped, '
            'not six further findings',
      );
    });

    test('two VTIMEZONE blocks report once, like a repeated property', () {
      const tz = 'BEGIN:VTIMEZONE\r\nTZID:x\r\nEND:VTIMEZONE\r\n';
      final result = _codec.decode(
        _ics(
          '$tz$tz'
          'BEGIN:VEVENT\r\n'
          'UID:u\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:s\r\n'
          'END:VEVENT',
        ),
      );
      expect(
        result.warnings.where((w) => w.message.contains('VTIMEZONE')),
        hasLength(1),
      );
    });

    test('properties the codec DOES map are not reported as dropped', () {
      final result = _codec.decode(
        _ics(
          'BEGIN:VEVENT\r\n'
          'UID:clean\r\n'
          'DTSTAMP:19700101T000000Z\r\n'
          'DTSTART:20260101T090000Z\r\n'
          'DTEND:20260101T100000Z\r\n'
          'SUMMARY:Clean\r\n'
          'DESCRIPTION:d\r\n'
          'LOCATION:l\r\n'
          'END:VEVENT',
        ),
      );
      expect(result.warnings, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // Determinism — the property the whole export path and
  // the history/merge machinery rest on.
  // ---------------------------------------------------------------------
  group('determinism', () {
    test('encode sorts events by (start, id) regardless of input order', () {
      ICalendarEvent ev(String id, int day) => ICalendarEvent(
        appointment: CalendarAppointment(
          id: id,
          title: id,
          start: DateTime.utc(2026, 1, day, 9),
          end: DateTime.utc(2026, 1, day, 10),
        ),
      );
      final a = _codec.encode(events: [ev('b', 2), ev('a', 1), ev('c', 1)]);
      final b = _codec.encode(events: [ev('c', 1), ev('b', 2), ev('a', 1)]);
      expect(a, b);
      expect(a.indexOf('UID:a'), lessThan(a.indexOf('UID:c')));
      expect(a.indexOf('UID:c'), lessThan(a.indexOf('UID:b')));
    });

    test('exceptions are stored sorted ascending', () {
      final a = CalendarAppointment(
        id: 'e1',
        title: 'E',
        start: DateTime.utc(2026, 1, 1, 9),
        end: DateTime.utc(2026, 1, 1, 10),
        recurrence: 'FREQ=DAILY',
        exceptions: [DateTime.utc(2026, 1, 5, 9), DateTime.utc(2026, 1, 3, 9)],
      );
      expect(a.exceptions, [
        DateTime.utc(2026, 1, 3, 9),
        DateTime.utc(2026, 1, 5, 9),
      ]);
    });

    test('the YAML body field order is fixed', () {
      final a = CalendarAppointment(
        id: 'x',
        title: 'X',
        start: DateTime.utc(2026, 1, 1, 9),
        end: DateTime.utc(2026, 1, 1, 10),
        description: 'd',
        location: 'l',
        recurrence: 'FREQ=DAILY',
        exceptions: [DateTime.utc(2026, 1, 3, 9)],
      );
      expect(a.toMap().keys.toList(), [
        'id',
        'title',
        'start',
        'end',
        'description',
        'location',
        'recurrence',
        'exceptions',
      ]);
    });
  });

  // ---------------------------------------------------------------------
  // Schema validation — the model rejects contradictory input rather than
  // guessing, which is the same class of defect as the TZID silent parse.
  // ---------------------------------------------------------------------
  group('appointment schema validation', () {
    test('allDay with a timestamp start is rejected', () {
      expect(
        () => CalendarAppointment.fromMap({
          'id': 'x',
          'title': 'X',
          'start': '2026-01-01T09:00:00Z',
          'end': '2026-01-02',
          'allDay': true,
        }),
        throwsFormatException,
      );
    });

    test('a timed appointment with a date-only start is rejected', () {
      expect(
        () => CalendarAppointment.fromMap({
          'id': 'x',
          'title': 'X',
          'start': '2026-01-01',
          'end': '2026-01-02',
        }),
        throwsFormatException,
      );
    });

    test('end before start is rejected', () {
      expect(
        () => CalendarAppointment(
          id: 'x',
          title: 'X',
          start: DateTime.utc(2026, 1, 2),
          end: DateTime.utc(2026, 1, 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exceptions must use the same form as start', () {
      expect(
        () => CalendarAppointment(
          id: 'x',
          title: 'X',
          allDay: true,
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 1, 2),
          recurrence: 'FREQ=DAILY',
          exceptions: [DateTime.utc(2026, 1, 3, 9, 30)],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'an unknown body field is rejected (the field set has no extension fields)',
      () {
        expect(
          () => CalendarAppointment.fromMap({
            'id': 'x',
            'title': 'X',
            'start': '2026-01-01T09:00:00Z',
            'end': '2026-01-01T10:00:00Z',
            'colour': 'red',
          }),
          throwsFormatException,
        );
      },
    );
  });
}
