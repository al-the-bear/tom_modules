import 'recurrence.dart';

/// One appointment — the unit of a calendar body and of
/// sidecar-collaboration appointment annotations.
///
/// **Time policy.** Timed appointments are **UTC at second
/// precision**: iCalendar (RFC 5545) date-times carry no milliseconds and the
/// deterministic YAML form must round-trip byte-identically through the export
/// path, so the model truncates on construction rather than losing precision
/// later. All-day appointments are **date-only**, stored as UTC midnight, and
/// their [end] is the **last included day** — the exclusive `DTEND` of the
/// wire form is converted on both sides of the codec, never leaked into the
/// model.
///
/// **Recurrence.** [recurrence] holds the RRULE **verbatim** so a rule
/// this package cannot interpret still survives an export→import round-trip
/// (degrade never delete). [recurrenceRule] is the parsed form, `null`
/// when the rule falls outside the recurrence subset; the series then renders as its
/// base occurrence alone.
class CalendarAppointment {
  /// Stable appointment id (unique within its containing body/annotation
  /// bucket; becomes the iCalendar `UID`).
  final String id;

  String title;
  String? description;
  String? location;

  /// The UTC offset of the place this appointment was created in, as
  /// `+02:00` — or null when nothing recorded one.
  ///
  /// An **offset, not a zone**: the time policy keeps timezone identifiers out, and
  /// an offset is what the creating device knew for certain. It changes
  /// nothing about when the appointment is; it is what lets a reader
  /// elsewhere see the wall clock its author meant.
  final String? createdIn;

  final bool _allDay;
  DateTime _start;
  DateTime _end;
  String? _recurrence;
  CalendarRecurrenceRule? _recurrenceRule;
  List<DateTime> _exceptions;

  CalendarAppointment({
    required this.id,
    required this.title,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    this.description,
    this.location,
    this.createdIn,
    String? recurrence,
    List<DateTime> exceptions = const [],
  }) : _allDay = allDay,
       _start = _canonical(start, allDay),
       _end = _canonical(end, allDay),
       _recurrence = recurrence,
       _recurrenceRule = recurrence == null
           ? null
           : CalendarRecurrenceRule.tryParse(
               recurrence,
               start: _canonical(start, allDay),
             ),
       _exceptions = const [] {
    _requireForm(start, 'start');
    _requireForm(end, 'end');
    if (_end.isBefore(_start)) {
      throw ArgumentError.value(
        end,
        'end',
        'Appointment $id ends before it starts (${encodeTime(_start)})',
      );
    }
    _exceptions = _sortedExceptions(exceptions);
    if (createdIn != null) parseOffset(createdIn!);
  }

  static final RegExp _offset = RegExp(r'^([+-])(\d{2}):(\d{2})$');

  /// The offset `+02:00` names. Throws [FormatException] for anything that is
  /// not an offset a place on Earth keeps (−12:00 … +14:00).
  static Duration parseOffset(String value) {
    final match = _offset.firstMatch(value);
    final minutes = match == null
        ? null
        : int.parse(match.group(2)!) * 60 + int.parse(match.group(3)!);
    if (match == null ||
        int.parse(match.group(3)!) > 59 ||
        minutes! > (match.group(1) == '-' ? 12 * 60 : 14 * 60)) {
      throw FormatException(
        'An offset is written "+hh:mm" between -12:00 and +14:00: "$value"',
      );
    }
    return Duration(minutes: match.group(1) == '-' ? -minutes : minutes);
  }

  /// [offset] as `+02:00`. Zero is `+00:00`.
  static String encodeOffset(Duration offset) {
    final minutes = offset.inMinutes.abs();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${offset.isNegative ? '-' : '+'}'
        '${p2(minutes ~/ 60)}:${p2(minutes % 60)}';
  }

  /// Whether this is an all-day appointment (date-only start/end).
  ///
  /// The form is fixed at construction. Flipping it is not a canonicalization
  /// — the timed direction has to *invent* a wall clock — so it belongs to
  /// [CalendarAppointmentEditing.setAllDay], which makes that choice once and
  /// visibly. A setter here would have had to pick midnight, quietly turning a
  /// three-day event into a zero-length one.
  bool get allDay => _allDay;

  /// First occurrence start (UTC midnight when [allDay]).
  DateTime get start => _start;

  set start(DateTime value) {
    _requireForm(value, 'start');
    _start = _canonical(value, _allDay);
    _reparseRecurrence();
  }

  /// End of the base occurrence; when [allDay], the **last included day**.
  DateTime get end => _end;

  set end(DateTime value) {
    _requireForm(value, 'end');
    _end = _canonical(value, _allDay);
  }

  /// The RRULE value, verbatim as authored or imported.
  String? get recurrence => _recurrence;

  set recurrence(String? value) {
    _recurrence = value;
    _reparseRecurrence();
  }

  /// Parses [recurrence] against the current start: whether a rule is inside
  /// the recurrence subset can depend on the start's date (a yearly rule restating
  /// it), so a new start or a new rule re-reads it.
  void _reparseRecurrence() {
    final value = _recurrence;
    _recurrenceRule = value == null
        ? null
        : CalendarRecurrenceRule.tryParse(value, start: _start);
  }

  /// The parsed [recurrence], or `null` when it is outside the recurrence subset.
  CalendarRecurrenceRule? get recurrenceRule => _recurrenceRule;

  /// `EXDATE` starts removed from the series, sorted ascending.
  List<DateTime> get exceptions => List.unmodifiable(_exceptions);

  set exceptions(List<DateTime> value) {
    _exceptions = _sortedExceptions(value);
  }

  List<DateTime> _sortedExceptions(List<DateTime> value) {
    final canonical = <DateTime>[];
    for (final e in value) {
      _requireForm(e, 'exception');
      canonical.add(_canonical(e, _allDay));
    }
    canonical.sort();
    return canonical;
  }

  /// A detached clone — same id, same values, no shared mutable state.
  ///
  /// Every surface that hands an appointment to an editor needs this, because
  /// the model is mutable and the id is the store's update key: passing the
  /// live instance means a cancelled edit has already been applied. An
  /// appointment editor and an annotation panel are two such surfaces, which
  /// is why it lives on the model rather than privately in either.
  CalendarAppointment copy() => CalendarAppointment(
    id: id,
    title: title,
    allDay: _allDay,
    start: _start,
    end: _end,
    description: description,
    location: location,
    createdIn: createdIn,
    recurrence: _recurrence,
    exceptions: _exceptions,
  );

  /// An all-day appointment may only carry date-only values: silently
  /// truncating a wall-clock here is exactly the class of quiet corruption
  /// the UTC-only policy exists to prevent.
  void _requireForm(DateTime value, String field) {
    if (!_allDay) return;
    final u = value.toUtc();
    if (u.hour != 0 || u.minute != 0 || u.second != 0 || u.millisecond != 0) {
      throw ArgumentError.value(
        value,
        field,
        'Appointment $id is all-day; $field must be a date, not a timestamp',
      );
    }
  }

  static DateTime _canonical(DateTime t, bool allDay) {
    final utc = t.toUtc();
    return allDay
        ? DateTime.utc(utc.year, utc.month, utc.day)
        : DateTime.utc(
            utc.year,
            utc.month,
            utc.day,
            utc.hour,
            utc.minute,
            utc.second,
          );
  }

  /// Canonical `yyyy-MM-ddTHH:mm:ssZ` form used in the YAML bodies.
  static String encodeTime(DateTime t) {
    final u = _canonical(t, false);
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${p2(u.month)}-${p2(u.day)}'
        'T${p2(u.hour)}:${p2(u.minute)}:${p2(u.second)}Z';
  }

  /// Canonical `yyyy-MM-dd` form used for all-day values.
  static String encodeDate(DateTime t) {
    final u = t.toUtc();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${p2(u.month)}-${p2(u.day)}';
  }

  String _encode(DateTime t) => _allDay ? encodeDate(t) : encodeTime(t);

  /// Field order is fixed so every save path yields identical YAML.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'start': _encode(_start),
    'end': _encode(_end),
    if (_allDay) 'allDay': true,
    if (description != null) 'description': description,
    if (location != null) 'location': location,
    if (createdIn != null) 'createdIn': createdIn,
    if (_recurrence != null) 'recurrence': _recurrence,
    if (_exceptions.isNotEmpty)
      'exceptions': [for (final e in _exceptions) _encode(e)],
  };

  /// The field set is closed — an unknown key is a format error, not an
  /// extension point.
  static const Set<String> _fields = {
    'id',
    'title',
    'start',
    'end',
    'allDay',
    'description',
    'location',
    'createdIn',
    'recurrence',
    'exceptions',
  };

  static final RegExp _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _timestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$',
  );

  static CalendarAppointment fromMap(Map<dynamic, dynamic> map) {
    for (final key in map.keys) {
      if (!_fields.contains(key)) {
        throw FormatException('Unknown appointment field: "$key"');
      }
    }
    final id = map['id'];
    final title = map['title'];
    final start = map['start'];
    final end = map['end'];
    if (id is! String || title is! String || start == null || end == null) {
      throw FormatException('Invalid appointment map: $map');
    }
    // The id is the UID and the anchor `blockId`; an empty one names
    // nothing and could not be told apart from a second empty one.
    if (id.isEmpty) {
      throw FormatException('Appointment id must not be empty: $map');
    }
    // `allDay` is a boolean. Reading `"yes"` or `1` as timed would
    // reparse the dates of an event its author marked all-day.
    final rawAllDay = map['allDay'];
    if (rawAllDay != null && rawAllDay is! bool) {
      throw FormatException(
        'Appointment $id: allDay must be a boolean, not "$rawAllDay"',
      );
    }
    final allDay = rawAllDay == true;
    return CalendarAppointment(
      id: id,
      title: title,
      allDay: allDay,
      start: _parseInstant(start.toString(), allDay, 'start'),
      end: _parseInstant(end.toString(), allDay, 'end'),
      description: map['description'] as String?,
      location: map['location'] as String?,
      createdIn: map['createdIn'] as String?,
      recurrence: map['recurrence'] as String?,
      exceptions: [
        for (final e in (map['exceptions'] as List? ?? const []))
          _parseInstant(e.toString(), allDay, 'exception'),
      ],
    );
  }

  static DateTime _parseInstant(String value, bool allDay, String field) {
    if (allDay) {
      if (!_dateOnly.hasMatch(value)) {
        throw FormatException(
          'All-day appointment $field must be "yyyy-MM-dd": "$value"',
        );
      }
      return DateTime.parse('${value}T00:00:00Z');
    }
    if (!_timestamp.hasMatch(value)) {
      throw FormatException(
        'Timed appointment $field must be "yyyy-MM-ddTHH:mm:ssZ": "$value"',
      );
    }
    return DateTime.parse(value);
  }

  /// Duration of one occurrence.
  Duration get duration => _end.difference(_start);

  /// Every occurrence start in `[from, to]`, inclusive, with [exceptions]
  /// removed (expanded on demand, never materialized).
  ///
  /// A rule outside the recurrence subset degrades to the base occurrence.
  List<DateTime> occurrencesIn(DateTime from, DateTime to) {
    final rule = _recurrenceRule;
    final starts = rule == null ? [_start] : rule.expandUpTo(_start, to);
    return [
      for (final s in starts)
        if (!s.isBefore(from) && !s.isAfter(to) && !_exceptions.contains(s)) s,
    ];
  }

  /// Every occurrence touching the UTC calendar day of [day], each
  /// materialized as its own single, non-recurring appointment.
  ///
  /// This is what a day list paints: a weekly series shows *that day's*
  /// start and end, not the series' first ones. Multi-day occurrences appear
  /// on every day they span.
  List<CalendarAppointment> occurrencesOn(DateTime day) => [
    for (final s in _occurrenceStartsOn(day)) occurrenceAt(s),
  ];

  List<DateTime> _occurrenceStartsOn(DateTime day) {
    final dayStart = DateTime.utc(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    // A long occurrence can start before the day and still cover it, so the
    // window opens one full duration early.
    final from = dayStart.subtract(duration + const Duration(days: 1));
    return [
      for (final s in occurrencesIn(from, dayEnd))
        if (_covers(dayStart, s)) s,
    ];
  }

  /// Whether the occurrence starting at [occurrenceStart] spans [dayStart].
  bool _covers(DateTime dayStart, DateTime occurrenceStart) {
    final e = occurrenceStart.add(duration);
    final firstDay = DateTime.utc(
      occurrenceStart.year,
      occurrenceStart.month,
      occurrenceStart.day,
    );
    final lastDay = DateTime.utc(e.year, e.month, e.day);
    return !dayStart.isBefore(firstDay) && !dayStart.isAfter(lastDay);
  }

  /// This appointment as a single, non-recurring occurrence starting at
  /// [occurrenceStart] — what a calendar view paints and what an occurrence
  /// occurrence actions edit.
  CalendarAppointment occurrenceAt(DateTime occurrenceStart) {
    final s = _canonical(occurrenceStart, _allDay);
    return CalendarAppointment(
      id: id,
      title: title,
      allDay: _allDay,
      start: s,
      end: s.add(duration),
      description: description,
      location: location,
      createdIn: createdIn,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarAppointment &&
      other.id == id &&
      other.title == title &&
      other._allDay == _allDay &&
      other._start == _start &&
      other._end == _end &&
      other.description == description &&
      other.location == location &&
      other.createdIn == createdIn &&
      other._recurrence == _recurrence &&
      _sameInstants(other._exceptions, _exceptions);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    _allDay,
    _start,
    _end,
    description,
    location,
    createdIn,
    _recurrence,
    Object.hashAll(_exceptions),
  );

  @override
  String toString() =>
      'CalendarAppointment($id "$title" '
      '${_encode(_start)}..${_encode(_end)}'
      '${_recurrence == null ? '' : ' RRULE:$_recurrence'})';

  static bool _sameInstants(List<DateTime> a, List<DateTime> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
