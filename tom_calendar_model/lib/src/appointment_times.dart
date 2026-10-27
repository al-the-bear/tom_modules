/// How an appointment's time is said.
///
/// One sentence-maker for every surface. A time is always given in **UTC**,
/// which is what is stored and is the same for every reader; beside it the
/// wall clock of the place the appointment was **created in**, when that was
/// recorded; and, on a screen, the wall clock of the **device** reading it.
library;

import 'appointment.dart';
import 'calendar_editing.dart';
import 'recurrence.dart';

/// The times of [appointment], in every frame that says something new.
///
/// [local] is the device's frame and is given only by a surface that has a
/// device — an editor, a panel. An export gives none, so what it writes is
/// the same on every machine.
///
/// A frame is left out when it would repeat one already shown: a device at
/// UTC adds nothing to UTC, and a device in the zone the appointment was
/// created in is one frame, not two.
///
/// An all-day appointment is a date and has no frame.
String calendarDescribeTimes(
  CalendarAppointment appointment, {
  CalendarTimeFrame? local,
}) {
  final a = appointment;
  if (a.allDay) {
    final from = CalendarAppointment.encodeDate(a.start);
    final to = CalendarAppointment.encodeDate(a.end);
    return from == to ? '$from (all day)' : '$from – $to (all day)';
  }

  final localOffset = local?.offsetAt(a.start);
  final createdOffset = a.createdIn == null
      ? null
      : CalendarAppointment.parseOffset(a.createdIn!);

  final parts = <String>[
    '${_range(a, Duration.zero)} UTC'
        '${localOffset == Duration.zero ? ' (local)' : ''}',
  ];
  if (localOffset != null && localOffset != Duration.zero) {
    parts.add(
      '${_range(a, localOffset)} local '
      '(UTC${CalendarAppointment.encodeOffset(localOffset)})',
    );
  }
  if (createdOffset != null &&
      createdOffset != Duration.zero &&
      createdOffset != localOffset) {
    parts.add(
      '${_range(a, createdOffset)} where created '
      '(UTC${a.createdIn})',
    );
  }
  return parts.join(' · ');
}

/// [appointment]'s recurrence as a sentence, for print — or the
/// empty string when it does not repeat.
///
/// `Repeats every 2 weeks on Monday and Wednesday, 6 times; except
/// 2026-07-24 08:30 UTC.` A rule outside the recurrence subset is not paraphrased
///: it is quoted verbatim as a custom rule.
///
/// The days a rule names are **UTC** days and are said as such, so the
/// sentence is the same on every machine, like the rest of a printout.
String calendarDescribeRecurrence(CalendarAppointment appointment) {
  final a = appointment;
  final raw = a.recurrence;
  if (raw == null) return '';
  final rule = a.recurrenceRule;
  if (rule == null) return 'Repeats by a custom rule: $raw';

  final n = rule.interval;
  String every(String one, String many) =>
      n == 1 ? 'every $one' : 'every $n $many';
  final buffer = StringBuffer('Repeats ');
  switch (rule.freq) {
    case CalendarRecurrenceFreq.daily:
      buffer.write(every('day', 'days'));
    case CalendarRecurrenceFreq.weekly:
      buffer.write(every('week', 'weeks'));
      if (rule.byDay.isNotEmpty) {
        final days = [for (final d in rule.byDay) _weekdayNames[d.weekday - 1]];
        buffer.write(' on ${_joinWords(days)}');
      }
    case CalendarRecurrenceFreq.monthly:
      buffer.write(every('month', 'months'));
      if (rule.byMonthDay.isNotEmpty) {
        buffer.write(' on ${_monthDay(rule.byMonthDay.single)}');
      } else if (rule.byDay.isNotEmpty) {
        final d = rule.byDay.single;
        buffer.write(
          ' on the ${_ordinal(d.ordinal!)} '
          '${_weekdayNames[d.weekday - 1]}',
        );
      }
    case CalendarRecurrenceFreq.yearly:
      buffer.write(every('year', 'years'));
  }
  if (rule.count != null) {
    buffer.write(rule.count == 1 ? ', once' : ', ${rule.count} times');
  } else if (rule.until != null) {
    buffer.write(', until ${_instant(rule.until!, a.allDay)}');
  }
  if (a.exceptions.isNotEmpty) {
    final excepted = [for (final e in a.exceptions) _instant(e, a.allDay)];
    buffer.write('; except ${_joinWords(excepted)}');
  }
  return buffer.toString();
}

/// A date for an all-day series, a UTC date-time for a timed one.
String _instant(DateTime t, bool allDay) =>
    allDay ? _date(t) : '${_date(t)} ${_clock(t)} UTC';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _joinWords(List<String> words) => words.length <= 1
    ? words.join()
    : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';

String _ordinal(int n) => switch (n) {
  -1 => 'last',
  -2 => 'second-to-last',
  1 => 'first',
  2 => 'second',
  3 => 'third',
  4 => 'fourth',
  5 => 'fifth',
  _ when n < 0 => '${_nth(-n)}-to-last',
  _ => _nth(n),
};

String _nth(int n) {
  final suffix = (n % 100 >= 11 && n % 100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

String _monthDay(int day) => day > 0 ? 'day $day' : 'the ${_ordinal(day)} day';

/// `2026-07-22 09:00–10:00`, or both dates when the end is on another day.
String _range(CalendarAppointment a, Duration offset) {
  final start = a.start.add(offset);
  final end = a.end.add(offset);
  if (a.start == a.end) return '${_date(start)} ${_clock(start)}';
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return sameDay
      ? '${_date(start)} ${_clock(start)}–${_clock(end)}'
      : '${_date(start)} ${_clock(start)} – ${_date(end)} ${_clock(end)}';
}

String _p2(int v) => v.toString().padLeft(2, '0');

String _date(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_p2(t.month)}-${_p2(t.day)}';

String _clock(DateTime t) => t.second == 0
    ? '${_p2(t.hour)}:${_p2(t.minute)}'
    : '${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}';
