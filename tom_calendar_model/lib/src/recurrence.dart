/// The recurrence subset this package interprets, and its live expansion.
///
/// An RRULE is stored **verbatim** on the appointment ("degrade,
/// never delete") and is interpreted only if it falls inside the
/// supported subset — `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`,
/// `BYMONTHDAY`, and on `YEARLY` a `BYMONTH` + `BYMONTHDAY` pair that restates
/// the start's date. Anything else parses to `null`, which makes the series
/// render as its base occurrence while the rule survives an export→import
/// round-trip untouched.
///
/// Occurrences are **never materialized**: a view asks for the window
/// it is painting and the rule is expanded into it on demand.
library;

/// The recurrence frequencies this package interprets.
enum CalendarRecurrenceFreq { daily, weekly, monthly, yearly }

/// One `BYDAY` entry: a weekday, optionally with an ordinal (`2TU`, `-1FR`).
///
/// A weekly rule takes plain weekdays and a monthly rule exactly one ordinal
/// weekday; anything else is outside the subset and refused by
/// [CalendarRecurrenceRule.tryParse].
class CalendarByDay {
  /// `DateTime.monday` (1) … `DateTime.sunday` (7).
  final int weekday;

  /// 1-based position in the period, negative counting from the end.
  final int? ordinal;

  const CalendarByDay(this.weekday, [this.ordinal]);

  @override
  bool operator ==(Object other) =>
      other is CalendarByDay &&
      other.weekday == weekday &&
      other.ordinal == ordinal;

  @override
  int get hashCode => Object.hash(weekday, ordinal);
}

/// A parsed RRULE inside the subset this package interprets.
class CalendarRecurrenceRule {
  final CalendarRecurrenceFreq freq;
  final int interval;
  final int? count;
  final DateTime? until;
  final List<CalendarByDay> byDay;
  final List<int> byMonthDay;

  const CalendarRecurrenceRule({
    required this.freq,
    this.interval = 1,
    this.count,
    this.until,
    this.byDay = const [],
    this.byMonthDay = const [],
  });

  /// Guard against an unbounded rule with a far-future window.
  static const int _maxPeriods = 20000;

  static const Map<String, int> _weekdays = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };

  static const Map<String, CalendarRecurrenceFreq> _freqs = {
    'DAILY': CalendarRecurrenceFreq.daily,
    'WEEKLY': CalendarRecurrenceFreq.weekly,
    'MONTHLY': CalendarRecurrenceFreq.monthly,
    'YEARLY': CalendarRecurrenceFreq.yearly,
  };

  /// Parses an RRULE **value** (the part after `RRULE:`).
  ///
  /// Accepts **exactly** the recurrence subset and returns `null` for everything
  /// else, so that a rule this class cannot expand faithfully is never
  /// expanded at all — it takes the degrade path instead (base occurrence,
  /// custom-recurrence badge, kept verbatim). Refused, besides unknown part
  /// names and malformed values:
  ///
  /// * a part named twice (`FREQ=DAILY;FREQ=WEEKLY`);
  /// * `COUNT` together with `UNTIL` (mutually exclusive);
  /// * a timed `UNTIL` without the `Z` (UTC, or a date for all-day);
  /// * `BYDAY` or `BYMONTHDAY` on `DAILY` or `YEARLY` — except, on `YEARLY`,
  ///   exactly one `BYMONTH` with exactly one `BYMONTHDAY` that name
  ///   [start]'s month and day (in UTC, the frame the start is stored in).
  ///   That is Calendar.app's form of every yearly event, and it means
  ///   exactly plain `FREQ=YEARLY`, which is what it parses to. Without
  ///   [start] such a rule cannot be confirmed and is refused;
  /// * `BYMONTH` anywhere else;
  /// * `BYMONTHDAY` on `WEEKLY`, and an ordinal weekday on `WEEKLY`;
  /// * on `MONTHLY`: more than one `BYDAY` or `BYMONTHDAY` value, both parts
  ///   together, or a plain (ordinal-less) weekday.
  ///
  /// A refusal is not a loss: callers keep the verbatim string.
  static CalendarRecurrenceRule? tryParse(String rrule, {DateTime? start}) {
    CalendarRecurrenceFreq? freq;
    var interval = 1;
    int? count;
    DateTime? until;
    final byDay = <CalendarByDay>[];
    final byMonthDay = <int>[];
    final byMonth = <int>[];
    final named = <String>{};

    for (final part in rrule.split(';')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 0) return null;
      final name = part.substring(0, eq).toUpperCase();
      final value = part.substring(eq + 1);
      // RFC 5545 §3.3.10: a rule part MUST NOT occur more than once. Reading
      // the second one over the first would expand a rule nobody wrote.
      if (!named.add(name)) return null;
      switch (name) {
        case 'FREQ':
          freq = _freqs[value.toUpperCase()];
          if (freq == null) return null;
        case 'INTERVAL':
          final n = int.tryParse(value);
          if (n == null || n < 1) return null;
          interval = n;
        case 'COUNT':
          final n = int.tryParse(value);
          if (n == null || n < 1) return null;
          count = n;
        case 'UNTIL':
          until = _parseUntil(value);
          if (until == null) return null;
        case 'BYDAY':
          for (final entry in value.split(',')) {
            final parsed = _parseByDay(entry.toUpperCase());
            if (parsed == null) return null;
            byDay.add(parsed);
          }
        case 'BYMONTHDAY':
          for (final entry in value.split(',')) {
            final n = int.tryParse(entry);
            if (n == null || n == 0 || n < -31 || n > 31) return null;
            byMonthDay.add(n);
          }
        case 'BYMONTH':
          for (final entry in value.split(',')) {
            final n = int.tryParse(entry);
            if (n == null || n < 1 || n > 12) return null;
            byMonth.add(n);
          }
        default:
          // BYSETPOS, WKST, BYWEEKNO, … — outside the subset.
          return null;
      }
    }
    if (freq == null) return null;
    if (count != null && until != null) return null;
    if (byMonth.isNotEmpty) {
      // A yearly rule whose month and day restate the
      // start's date is plain `FREQ=YEARLY` and parses to it. Any other use of
      // BYMONTH — another month, several, without a day, or on another
      // frequency — expands to dates the subset does not express.
      final day = start?.toUtc();
      if (freq != CalendarRecurrenceFreq.yearly ||
          day == null ||
          byMonth.length != 1 ||
          byMonthDay.length != 1 ||
          byDay.isNotEmpty ||
          byMonth.single != day.month ||
          byMonthDay.single != day.day) {
        return null;
      }
      byMonthDay.clear();
    }
    switch (freq) {
      case CalendarRecurrenceFreq.daily:
      case CalendarRecurrenceFreq.yearly:
        // A yearly rule repeats the start date; BYDAY/BYMONTHDAY there would
        // need BYMONTH/BYWEEKNO semantics the subset does not carry.
        if (byDay.isNotEmpty || byMonthDay.isNotEmpty) return null;
      case CalendarRecurrenceFreq.weekly:
        if (byMonthDay.isNotEmpty) return null;
        if (byDay.any((d) => d.ordinal != null)) return null;
      case CalendarRecurrenceFreq.monthly:
        // Exactly one of: one ordinal weekday (`2TU`, `-1FR`), one day of the
        // month, or neither (the start's day of the month). A plain `TU` on a
        // monthly rule means *every* Tuesday of the month in RFC 5545, which
        // the subset does not express.
        if (byDay.length + byMonthDay.length > 1) return null;
        if (byDay.any((d) => d.ordinal == null)) return null;
    }
    byDay.sort((a, b) {
      final byOrdinal = (a.ordinal ?? 0).compareTo(b.ordinal ?? 0);
      return byOrdinal != 0 ? byOrdinal : a.weekday.compareTo(b.weekday);
    });
    byMonthDay.sort();
    return CalendarRecurrenceRule(
      freq: freq,
      interval: interval,
      count: count,
      until: until,
      byDay: List.unmodifiable(byDay),
      byMonthDay: List.unmodifiable(byMonthDay),
    );
  }

  /// The RRULE value for this rule — the inverse of [tryParse].
  ///
  /// The part order is fixed (`FREQ;INTERVAL;COUNT;UNTIL;BYDAY;BYMONTHDAY`)
  /// for the same reason the appointment field order is: two edits
  /// that produce the same rule must produce the same bytes, or a save that
  /// changed nothing still shows up as a diff.
  ///
  /// `INTERVAL=1` is omitted — it is the RFC 5545 default, and writing it
  /// would make a rule this package emitted differ textually from the same rule
  /// imported from another calendar.
  ///
  /// [allDay] selects the `UNTIL` form: RFC 5545 requires it to match the
  /// value type of `DTSTART`, so an all-day series bounds on a date and a
  /// timed one on a UTC timestamp.
  String format({bool allDay = false}) {
    final parts = <String>['FREQ=${freq.name.toUpperCase()}'];
    if (interval != 1) parts.add('INTERVAL=$interval');
    if (count != null) parts.add('COUNT=$count');
    if (until != null) parts.add('UNTIL=${_formatUntil(until!, allDay)}');
    if (byDay.isNotEmpty) {
      parts.add('BYDAY=${byDay.map(_formatByDay).join(',')}');
    }
    if (byMonthDay.isNotEmpty) {
      parts.add('BYMONTHDAY=${byMonthDay.join(',')}');
    }
    return parts.join(';');
  }

  static String _formatByDay(CalendarByDay day) {
    final code = _weekdays.entries
        .firstWhere((e) => e.value == day.weekday)
        .key;
    return day.ordinal == null ? code : '${day.ordinal}$code';
  }

  static String _formatUntil(DateTime until, bool allDay) {
    final u = until.toUtc();
    String p2(int v) => v.toString().padLeft(2, '0');
    final date =
        '${u.year.toString().padLeft(4, '0')}${p2(u.month)}'
        '${p2(u.day)}';
    if (allDay) return date;
    return '${date}T${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z';
  }

  static CalendarByDay? _parseByDay(String entry) {
    final match = RegExp(
      r'^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$',
    ).firstMatch(entry);
    if (match == null) return null;
    final ordinal = match.group(1) == null ? null : int.parse(match.group(1)!);
    if (ordinal == 0) return null;
    return CalendarByDay(_weekdays[match.group(2)!]!, ordinal);
  }

  /// A UTC date-time (`…Z`) or a date (the all-day form). A timed value
  /// without the `Z` is floating — local to a reader this package does not know —
  /// and is refused rather than guessed at.
  static DateTime? _parseUntil(String value) {
    final timed = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
    ).firstMatch(value);
    if (timed != null) {
      int g(int i) => int.parse(timed.group(i)!);
      return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
    }
    final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      int g(int i) => int.parse(dateOnly.group(i)!);
      // Date-only UNTIL bounds the whole day.
      return DateTime.utc(g(1), g(2), g(3), 23, 59, 59);
    }
    return null;
  }

  /// Every occurrence start from [seriesStart] up to and including [to].
  ///
  /// `EXDATE` removal happens in [CalendarAppointment]; `COUNT` is applied
  /// here, before that removal, as RFC 5545 §3.8.5.1 requires.
  List<DateTime> expandUpTo(DateTime seriesStart, DateTime to) {
    final out = <DateTime>[];
    var generated = 0;
    for (var period = 0; period < _maxPeriods; period++) {
      if (_periodAnchor(seriesStart, period).isAfter(to)) break;
      for (final candidate in _candidates(seriesStart, period)) {
        if (candidate.isBefore(seriesStart)) continue;
        if (until != null && candidate.isAfter(until!)) return out;
        generated++;
        if (count != null && generated > count!) return out;
        if (candidate.isAfter(to)) return out;
        out.add(candidate);
      }
    }
    return out;
  }

  /// A monotonically increasing lower bound for the occurrences of [period],
  /// used purely to decide when expansion may stop.
  DateTime _periodAnchor(DateTime start, int period) {
    final n = period * interval;
    switch (freq) {
      case CalendarRecurrenceFreq.daily:
        return start.add(Duration(days: n));
      case CalendarRecurrenceFreq.weekly:
        return _weekStart(start).add(Duration(days: 7 * n));
      case CalendarRecurrenceFreq.monthly:
        return DateTime.utc(start.year, start.month + n);
      case CalendarRecurrenceFreq.yearly:
        return DateTime.utc(start.year + n);
    }
  }

  /// The candidate starts generated by [period], ascending.
  List<DateTime> _candidates(DateTime start, int period) {
    final n = period * interval;
    switch (freq) {
      case CalendarRecurrenceFreq.daily:
        return [start.add(Duration(days: n))];

      case CalendarRecurrenceFreq.weekly:
        if (byDay.isEmpty) return [start.add(Duration(days: 7 * n))];
        final weekStart = _weekStart(start).add(Duration(days: 7 * n));
        return [
          for (final day in byDay)
            _at(
              weekStart.add(Duration(days: day.weekday - DateTime.monday)),
              start,
            ),
        ];

      case CalendarRecurrenceFreq.monthly:
        final month = DateTime.utc(start.year, start.month + n);
        return _daysInPeriod(month.year, month.month, start);

      case CalendarRecurrenceFreq.yearly:
        return _daysInPeriod(start.year + n, start.month, start);
    }
  }

  /// Resolves `BYMONTHDAY` / `BYDAY` (or the implicit day-of-month) inside
  /// one month, dropping positions the month does not have.
  List<DateTime> _daysInPeriod(int year, int month, DateTime start) {
    final days = <DateTime>[];
    if (byMonthDay.isNotEmpty) {
      final last = _daysInMonth(year, month);
      for (final day in byMonthDay) {
        final resolved = day > 0 ? day : last + day + 1;
        if (resolved >= 1 && resolved <= last) {
          days.add(DateTime.utc(year, month, resolved));
        }
      }
    } else if (byDay.isNotEmpty) {
      for (final entry in byDay) {
        final resolved = _nthWeekdayOfMonth(
          year,
          month,
          entry.weekday,
          entry.ordinal ?? 1,
        );
        if (resolved != null) days.add(resolved);
      }
    } else {
      if (start.day <= _daysInMonth(year, month)) {
        days.add(DateTime.utc(year, month, start.day));
      }
    }
    days.sort();
    return [for (final d in days) _at(d, start)];
  }

  /// [date] carried over to the time-of-day of [start].
  static DateTime _at(DateTime date, DateTime start) => DateTime.utc(
    date.year,
    date.month,
    date.day,
    start.hour,
    start.minute,
    start.second,
  );

  /// The Monday of [t]'s week (RFC 5545's default `WKST=MO`).
  static DateTime _weekStart(DateTime t) => DateTime.utc(
    t.year,
    t.month,
    t.day,
  ).subtract(Duration(days: t.weekday - DateTime.monday));

  static int _daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  /// The [ordinal]-th [weekday] of a month, or `null` if the month has none
  /// (e.g. a fifth Monday). Negative [ordinal] counts back from the end.
  static DateTime? _nthWeekdayOfMonth(
    int year,
    int month,
    int weekday,
    int ordinal,
  ) {
    final last = _daysInMonth(year, month);
    if (ordinal > 0) {
      final first = DateTime.utc(year, month, 1);
      final offset = (weekday - first.weekday) % 7;
      final day = 1 + offset + (ordinal - 1) * 7;
      return day <= last ? DateTime.utc(year, month, day) : null;
    }
    final lastDate = DateTime.utc(year, month, last);
    final offset = (lastDate.weekday - weekday) % 7;
    final day = last - offset + (ordinal + 1) * 7;
    return day >= 1 ? DateTime.utc(year, month, day) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarRecurrenceRule &&
      other.freq == freq &&
      other.interval == interval &&
      other.count == count &&
      other.until == until &&
      _listEquals(other.byDay, byDay) &&
      _listEquals(other.byMonthDay, byMonthDay);

  @override
  int get hashCode => Object.hash(
    freq,
    interval,
    count,
    until,
    Object.hashAll(byDay),
    Object.hashAll(byMonthDay),
  );

  static bool _listEquals(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
