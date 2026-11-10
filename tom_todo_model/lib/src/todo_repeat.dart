/// A repeated todo's rule: when it comes back after it was done.
///
/// Stored as the todo's `repeat:` map (the workspace `todo.schema.json`
/// `repeat` definition). A repeated todo that is done does not become
/// `completed`: it goes to `waiting-for-repeat`, with `next_repeat` the
/// moment it is due again (computed by the VS Code extension's repeated-todo
/// controller, which also moves it back to `not-started` when that moment has
/// come). A `manual` rule has no moment: the todo waits until it is repeated
/// by hand.
///
/// This class is data: it reads, validates and writes the rule. It does not
/// compute dates.
library;

/// The kinds of rule.
enum TomTodoRepeatRule {
  /// No moment: repeated by hand.
  manual('manual'),

  /// [TomTodoRepeat.every] [TomTodoRepeat.unit]s after the todo was done.
  after('after'),

  /// Every [TomTodoRepeat.every] days.
  daily('daily'),

  /// Every [TomTodoRepeat.every] weeks on [TomTodoRepeat.weekdays].
  weekly('weekly'),

  /// Every [TomTodoRepeat.every] months on a day of the month.
  monthly('monthly'),

  /// Every [TomTodoRepeat.every] years in [TomTodoRepeat.month] on a day of
  /// that month.
  yearly('yearly');

  const TomTodoRepeatRule(this.wire);

  final String wire;

  static TomTodoRepeatRule fromWire(String value) => values.firstWhere(
    (r) => r.wire == value,
    orElse: () => throw FormatException('Unknown repeat rule: "$value"'),
  );
}

/// The day of a month a `monthly` or `yearly` rule names — exactly one of:
/// [day] (1–31; a month without that day takes its last), [lastDay], the
/// [nth] [weekday] (1–5, or -1 for the last), or the first / last working day
/// ([workingDay], Monday to Friday).
class TomTodoRepeat {
  TomTodoRepeatRule rule;

  /// The interval: every N days / weeks / months / years. At least 1.
  int every;

  /// For `after`: `days`, `weeks`, `months` or `years`.
  String? unit;

  /// For `weekly`: `mon` … `sun`.
  List<String> weekdays;

  /// For `monthly` / `yearly`: a day of the month, 1–31.
  int? day;

  /// For `monthly` / `yearly`: the last day of the month.
  bool lastDay;

  /// For `monthly` / `yearly`: the nth (1–5, -1 = last) [weekday] of the month.
  int? nth;
  String? weekday;

  /// For `monthly` / `yearly`: `first` or `last` working day of the month.
  String? workingDay;

  /// For `yearly`: the month, 1–12.
  int? month;

  /// The time of day, `HH:MM`, local; absent: the start of the day.
  String? time;

  /// The last day a repetition may be due on, `yyyy-MM-dd`.
  String? until;

  /// The number of repetitions after which the todo is done for good.
  int? count;

  TomTodoRepeat({
    required this.rule,
    this.every = 1,
    this.unit,
    List<String> weekdays = const [],
    this.day,
    this.lastDay = false,
    this.nth,
    this.weekday,
    this.workingDay,
    this.month,
    this.time,
    this.until,
    this.count,
  }) : weekdays = List.of(weekdays) {
    check();
  }

  static const Set<String> weekdayNames = {'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'};
  static const Set<String> units = {'days', 'weeks', 'months', 'years'};
  static final RegExp _timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  static final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// The fields a `repeat:` map may carry.
  static const Set<String> fields = {
    'rule', 'every', 'unit', 'weekdays', 'day', 'nth', 'weekday', 'working_day', 'month', 'time', 'until', 'count',
  };

  /// Throws a [FormatException] when the rule is not one the schema allows.
  void check() {
    void fail(String why) => throw FormatException('Todo "repeat": $why');
    if (every < 1) fail('"every" must be 1 or more, not $every');
    if (time != null && !_timeRe.hasMatch(time!)) fail('"time" must be HH:MM, not "$time"');
    if (until != null && !_dateRe.hasMatch(until!)) fail('"until" must be yyyy-MM-dd, not "$until"');
    if (count != null && count! < 1) fail('"count" must be 1 or more, not $count');
    for (final w in weekdays) {
      if (!weekdayNames.contains(w)) fail('unknown weekday "$w"');
    }
    if (weekday != null && !weekdayNames.contains(weekday)) fail('unknown weekday "$weekday"');
    switch (rule) {
      case TomTodoRepeatRule.manual:
      case TomTodoRepeatRule.daily:
        break;
      case TomTodoRepeatRule.after:
        if (unit == null || !units.contains(unit)) fail('"after" needs "unit": days, weeks, months or years');
      case TomTodoRepeatRule.weekly:
        if (weekdays.isEmpty) fail('"weekly" needs "weekdays"');
      case TomTodoRepeatRule.monthly:
      case TomTodoRepeatRule.yearly:
        final ways = [day != null, lastDay, nth != null, workingDay != null].where((x) => x).length;
        if (ways != 1) fail('"${rule.wire}" needs exactly one of "day" (1–31 or last), "nth" with "weekday", "working_day"');
        if (day != null && (day! < 1 || day! > 31)) fail('"day" must be 1–31 or last, not $day');
        if (nth != null && (nth == 0 || nth! < -1 || nth! > 5)) fail('"nth" must be 1–5 or last, not $nth');
        if (nth != null && weekday == null) fail('"nth" needs "weekday"');
        if (workingDay != null && workingDay != 'first' && workingDay != 'last') fail('"working_day" must be first or last');
        if (rule == TomTodoRepeatRule.yearly && (month == null || month! < 1 || month! > 12)) fail('"yearly" needs "month" 1–12');
    }
  }

  /// The stored form, fields in the schema's order, each only when set.
  Map<String, Object?> toMap() => {
    'rule': rule.wire,
    if (every != 1) 'every': every,
    if (unit != null) 'unit': unit,
    if (weekdays.isNotEmpty) 'weekdays': List.of(weekdays),
    if (lastDay) 'day': 'last' else if (day != null) 'day': day,
    if (nth != null) 'nth': nth == -1 ? 'last' : nth,
    if (weekday != null) 'weekday': weekday,
    if (workingDay != null) 'working_day': workingDay,
    if (month != null) 'month': month,
    if (time != null) 'time': time,
    if (until != null) 'until': until,
    if (count != null) 'count': count,
  };

  static int? _int(Object? v, String field) {
    if (v == null) return null;
    if (v is int) return v;
    throw FormatException('Todo "repeat": "$field" must be a whole number, not "$v"');
  }

  /// Reads a stored `repeat:` map; an unknown key or value is a format error.
  static TomTodoRepeat fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!fields.contains(key)) throw FormatException('Todo "repeat": unknown field "$key"');
    }
    final rule = map['rule'];
    if (rule is! String) throw const FormatException('Todo "repeat" needs a "rule"');
    final day = map['day'];
    final nth = map['nth'];
    final until = map['until'];
    return TomTodoRepeat(
      rule: TomTodoRepeatRule.fromWire(rule),
      every: _int(map['every'], 'every') ?? 1,
      unit: map['unit'] as String?,
      weekdays: [for (final w in (map['weekdays'] as List? ?? const [])) w.toString()],
      day: day == 'last' ? null : _int(day, 'day'),
      lastDay: day == 'last',
      nth: nth == 'last' ? -1 : _int(nth, 'nth'),
      weekday: map['weekday'] as String?,
      workingDay: map['working_day'] as String?,
      month: _int(map['month'], 'month'),
      time: map['time'] as String?,
      until: until?.toString(),
      count: _int(map['count'], 'count'),
    );
  }

  TomTodoRepeat copy() => fromMap(toMap());

  /// A `next_repeat` moment: `yyyy-MM-ddTHH:MM` with `Z` or an offset.
  static final RegExp nextRepeatRe = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})$');
}
