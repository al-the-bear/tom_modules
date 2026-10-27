/// A yearly rule whose single BYMONTH and single
/// BYMONTHDAY restate the start's date is plain `FREQ=YEARLY`. Calendar.app
/// writes every yearly event that way; anything else with BYMONTH stays
/// outside the subset.
library;

import 'package:tom_calendar_model/tom_calendar_model.dart';
import 'package:test/test.dart';

const _apple = 'FREQ=YEARLY;UNTIL=21000826;BYMONTH=8;BYMONTHDAY=26';
final _birthday = DateTime.utc(1990, 8, 26);

CalendarAppointment _appointment(
  String rule,
  DateTime start, {
  bool allDay = true,
}) => CalendarAppointment(
  id: 'birthday',
  title: 'Birthday',
  allDay: allDay,
  start: start,
  end: start,
  recurrence: rule,
);

void main() {
  group('the rule', () {
    test('restating the start, it parses to plain FREQ=YEARLY '
        'with its UNTIL [1019]', () {
      final rule = CalendarRecurrenceRule.tryParse(_apple, start: _birthday)!;
      expect(rule.freq, CalendarRecurrenceFreq.yearly);
      expect(rule.byMonthDay, isEmpty);
      expect(rule.byDay, isEmpty);
      expect(
        rule.until,
        DateTime.utc(2100, 8, 26, 23, 59, 59),
        reason: 'a date UNTIL includes its whole day',
      );
      expect(
        rule.format(allDay: true),
        'FREQ=YEARLY;UNTIL=21000826',
        reason: 'an edit writes the plain form',
      );
    });

    test('everything else with BYMONTH is still refused '
        '[1019]', () {
      final refused = {
        'another day': 'FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=27',
        'another month': 'FREQ=YEARLY;BYMONTH=9;BYMONTHDAY=26',
        'two months': 'FREQ=YEARLY;BYMONTH=8,9;BYMONTHDAY=26',
        'two days': 'FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=26,27',
        'no day': 'FREQ=YEARLY;BYMONTH=8',
        'a weekday as well': 'FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=26;BYDAY=MO',
        'monthly': 'FREQ=MONTHLY;BYMONTH=8;BYMONTHDAY=26',
        'month 13': 'FREQ=YEARLY;BYMONTH=13;BYMONTHDAY=26',
        // BYMONTHDAY alone on YEARLY is that day of every month (RFC 5545),
        // not the start's date.
        'a day without a month': 'FREQ=YEARLY;BYMONTHDAY=26',
      };
      refused.forEach((why, rule) {
        expect(
          CalendarRecurrenceRule.tryParse(rule, start: _birthday),
          isNull,
          reason: why,
        );
      });
      expect(
        CalendarRecurrenceRule.tryParse(_apple),
        isNull,
        reason: 'without the start the restatement cannot be confirmed',
      );
    });

    test('a timed start is compared in UTC, the frame it is '
        'stored in [1019]', () {
      final start = DateTime.utc(2026, 8, 26, 23, 30);
      expect(
        CalendarRecurrenceRule.tryParse(
          'FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=26',
          start: start,
        ),
        isNotNull,
      );
      expect(
        CalendarRecurrenceRule.tryParse(
          'FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=27',
          start: start,
        ),
        isNull,
      );
    });
  });

  group('the appointment', () {
    test('an Apple birthday recurs every year and keeps the '
        'rule as written [1019]', () {
      final a = _appointment(_apple, _birthday);
      expect(a.recurrence, _apple);
      expect(a.recurrenceRule, isNotNull);
      expect(a.occurrencesOn(DateTime.utc(2027, 8, 26)), isNotEmpty);
      expect(a.occurrencesOn(DateTime.utc(2027, 8, 27)), isEmpty);
      expect(
        a.occurrencesOn(DateTime.utc(2101, 8, 26)),
        isEmpty,
        reason: 'UNTIL still ends the series',
      );
    });

    test('moving the start away from the restated date '
        're-reads the rule, which then no longer fits [1019]', () {
      final a = _appointment(_apple, _birthday);
      a.start = DateTime.utc(1990, 8, 27);
      expect(a.recurrenceRule, isNull);
      a.start = _birthday;
      expect(a.recurrenceRule, isNotNull);
    });

    test('the editor may present it [1019]', () {
      expect(
        CalendarRecurrenceEditing.isInterpretable(_apple, start: _birthday),
        isTrue,
      );
      expect(CalendarRecurrenceEditing.isInterpretable(_apple), isFalse);
    });
  });
}
