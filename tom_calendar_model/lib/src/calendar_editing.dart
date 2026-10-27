/// The model half of occurrence actions and all-day conversion.
///
/// Both are model concerns — writing a rule is a string transform
/// ([CalendarRecurrenceRule.format]) and an occurrence action is a list
/// transform — so they live here rather than in an editor. That keeps them
/// testable without a widget binding and reachable by plain-Dart callers — a
/// sync job, an agent tool — which need to cancel an occurrence for reasons
/// that have nothing to do with a dialog.
///
/// Every operation here is **pure**: it takes the appointment list a calendar
/// body holds and returns a new one. The caller writes the result back to wherever
/// the body lives, and keeps the list it replaced if it needs an inverse.
library;

import 'appointment.dart';
import 'recurrence.dart';

/// The reference frame a **calendar day** is read in.
///
/// Storage is UTC and an instant has no day of its own: 01:00Z on the
/// 23rd is the evening of the 22nd five hours west. Every transform that turns
/// an instant into a day, or a day into an instant, therefore has to be told
/// whose day — and is told through this, rather than assuming one.
///
/// [utc] is the default everywhere, which is what keeps a sync job and an
/// agent deterministic: their answer does not depend on the clock of the
/// machine they run on. An editor passes [device], because the day a user is
/// reading is the device's.
class CalendarTimeFrame {
  /// A frame at a fixed [offset] from UTC.
  const CalendarTimeFrame.fixed(Duration this.offset);

  const CalendarTimeFrame._device() : offset = null;

  /// The storage frame.
  static const CalendarTimeFrame utc = CalendarTimeFrame.fixed(Duration.zero);

  /// The zone of the machine this runs on, daylight saving included.
  static const CalendarTimeFrame device = CalendarTimeFrame._device();

  /// The offset from UTC, or null for [device], whose offset depends on the
  /// instant.
  final Duration? offset;

  /// The wall clock [instant] shows in this frame, as a UTC-flagged value
  /// whose fields are that wall clock.
  DateTime wall(DateTime instant) {
    final offset = this.offset;
    if (offset != null) return instant.toUtc().add(offset);
    final local = instant.toLocal();
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  }

  /// The instant at which this frame's wall clock reads the given fields.
  DateTime instant(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) {
    final offset = this.offset;
    if (offset != null) {
      return DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
      ).subtract(offset);
    }
    return DateTime(year, month, day, hour, minute, second).toUtc();
  }

  /// The date [instant] falls on in this frame, timezone-free (UTC midnight).
  DateTime dateOf(DateTime instant) {
    final w = wall(instant);
    return DateTime.utc(w.year, w.month, w.day);
  }

  /// This frame's offset from UTC at [instant].
  Duration offsetAt(DateTime instant) =>
      offset ?? instant.toLocal().timeZoneOffset;

  /// How many days this frame's date of [instant] is ahead of its UTC date:
  /// -1, 0 or 1.
  int dayShift(DateTime instant) {
    final u = instant.toUtc();
    return dateOf(
      instant,
    ).difference(DateTime.utc(u.year, u.month, u.day)).inDays;
  }
}

/// What "now" is and whose days it is read in — the one place an editor
/// asks either question.
///
/// A calendar opens on today and draws its grid, its day list and its "when"
/// lines in the reader's days. Both depend on the machine: [system] answers
/// with the device's clock and zone, which is what the app runs on. A test
/// passes [CalendarClock.fixed], so what it draws does not depend on the day
/// or the zone it runs in.
class CalendarClock {
  const CalendarClock({required this.now, required this.frame});

  /// A clock stopped at [instant], reading days at [offset] from UTC.
  CalendarClock.fixed(DateTime instant, {Duration offset = Duration.zero})
    : now = (() => instant),
      frame = CalendarTimeFrame.fixed(offset);

  /// The device's clock and zone.
  static const CalendarClock system = CalendarClock(
    now: DateTime.now,
    frame: CalendarTimeFrame.device,
  );

  /// The current instant.
  final DateTime Function() now;

  /// The frame a day is read in.
  final CalendarTimeFrame frame;

  /// Today's date in [frame], timezone-free (UTC midnight).
  DateTime today() => frame.dateOf(now());
}

/// Whether the recurrence editor can present [rrule] as a set of controls.
///
/// A rule outside the subset is "degrade, never delete": a rule outside the recurrence subset stays on
/// the appointment byte-for-byte and is shown as read-only text. This is the
/// predicate the editor branches on — and `null` is *interpretable*, because
/// "no rule" is exactly the state the controls start in when the user adds one.
class CalendarRecurrenceEditing {
  const CalendarRecurrenceEditing._();

  /// [start] is the series' start: a yearly rule restating its date is
  /// interpretable , and only the start can say so.
  static bool isInterpretable(String? rrule, {DateTime? start}) =>
      rrule == null ||
      CalendarRecurrenceRule.tryParse(rrule, start: start) != null;

  /// [rule] with every day it names moved by [days] (-1, 0 or 1).
  ///
  /// A rule is stored against the UTC start, so its `BYDAY` and
  /// `BYMONTHDAY` name **UTC** days. An editor shows the day the user reads,
  /// which is [CalendarTimeFrame.dayShift] away; this is the conversion between
  /// the two, applied one way on load and the other on save.
  ///
  /// Exact for a weekday. For a day of the month it is exact while both days
  /// exist in every month and lie in the same one; across a month boundary
  /// (the 31st in one frame is the 1st in the other) a UTC rule cannot say
  /// what the user means, and the day wraps within the month.
  static CalendarRecurrenceRule shiftDays(
    CalendarRecurrenceRule rule,
    int days,
  ) {
    if (days == 0) return rule;
    final byDay =
        [
          for (final d in rule.byDay)
            CalendarByDay((d.weekday - 1 + days) % 7 + 1, d.ordinal),
        ]..sort((a, b) {
          final byOrdinal = (a.ordinal ?? 0).compareTo(b.ordinal ?? 0);
          return byOrdinal != 0 ? byOrdinal : a.weekday.compareTo(b.weekday);
        });
    return CalendarRecurrenceRule(
      freq: rule.freq,
      interval: rule.interval,
      count: rule.count,
      until: rule.until,
      byDay: byDay,
      byMonthDay: [for (final d in rule.byMonthDay) (d - 1 + days) % 31 + 1]
        ..sort(),
    );
  }
}

/// The occurrence actions over a calendar body's appointment list.
class CalendarOccurrenceEdit {
  const CalendarOccurrenceEdit._();

  /// Removes one occurrence of [appointmentId] by appending its start to the
  /// series' `EXDATE`s.
  ///
  /// An EXDATE rather than a "cancelled" flag, because the exclusion has to
  /// survive an iCalendar export: RFC 5545 has no way to say "this occurrence
  /// exists but is hidden", and a flag an application invented would vanish the first
  /// time the series was read by anything else.
  ///
  /// Idempotent — cancelling an already-cancelled occurrence is a no-op rather
  /// than a duplicate EXDATE, since the exception list is a set in all but
  /// spelling.
  ///
  /// Throws [ArgumentError] when [occurrenceStart] is not an occurrence of the
  /// series. A caller that computed the start from the rendered calendar
  /// always passes a real one; one that did not has a bug that an EXDATE
  /// matching nothing would hide.
  static List<CalendarAppointment> deleteOccurrence(
    List<CalendarAppointment> appointments, {
    required String appointmentId,
    required DateTime occurrenceStart,
  }) {
    final series = _require(appointments, appointmentId);
    final start = _requireOccurrence(series, occurrenceStart);
    if (series.exceptions.contains(start)) return List.of(appointments);
    return [
      for (final a in appointments)
        if (a.id != appointmentId)
          a
        else
          _respawn(a, exceptions: [...a.exceptions, start]),
    ];
  }

  /// Splits one occurrence out of a series as a standalone appointment.
  ///
  /// This is "edit this occurrence only", and it writes **both
  /// halves at once**: the series gains an EXDATE for [occurrenceStart] and a
  /// new non-recurring appointment carries the edited values. Two separate
  /// operations would let a save land between them and leave the day showing
  /// the occurrence twice — or not at all.
  ///
  /// The detached appointment gets [newId] (the caller mints the UUID, so the
  /// model stays free of an id generator) and keeps **no** recurrence and no
  /// exceptions of its own: an occurrence that still recurred would be a
  /// second series, not an exception to the first.
  static List<CalendarAppointment> detachOccurrence(
    List<CalendarAppointment> appointments, {
    required String appointmentId,
    required DateTime occurrenceStart,
    required CalendarAppointment edited,
    required String newId,
  }) {
    final withExdate = deleteOccurrence(
      appointments,
      appointmentId: appointmentId,
      occurrenceStart: occurrenceStart,
    );
    return [
      ...withExdate,
      CalendarAppointment(
        id: newId,
        title: edited.title,
        allDay: edited.allDay,
        start: edited.start,
        end: edited.end,
        description: edited.description,
        location: edited.location,
        createdIn: edited.createdIn,
      ),
    ];
  }

  /// Removes the whole series — "delete all occurrences".
  static List<CalendarAppointment> deleteSeries(
    List<CalendarAppointment> appointments, {
    required String appointmentId,
  }) {
    _require(appointments, appointmentId);
    return [
      for (final a in appointments)
        if (a.id != appointmentId) a,
    ];
  }

  /// Replaces the series with [edited] — "edit all occurrences".
  ///
  /// The existing exceptions are **kept**. Re-anchoring a series does not
  /// un-cancel the occurrences the user already cancelled; the model treats the
  /// exception list as belonging to the series identity, not to its timing.
  /// Exceptions that no longer name an occurrence simply stop matching, which
  /// is what RFC 5545 says a stale EXDATE does.
  ///
  /// When the edit changed the series' form, the kept exceptions change form
  /// with it, reading their day in [frame] — the frame the edit itself was
  /// made in, so an exception still names the occurrence it cancelled.
  static List<CalendarAppointment> replaceSeries(
    List<CalendarAppointment> appointments, {
    required String appointmentId,
    required CalendarAppointment edited,
    CalendarTimeFrame frame = CalendarTimeFrame.utc,
  }) {
    final existing = _require(appointments, appointmentId);
    return [
      for (final a in appointments)
        if (a.id != appointmentId)
          a
        else
          CalendarAppointment(
            id: appointmentId,
            title: edited.title,
            allDay: edited.allDay,
            start: edited.start,
            end: edited.end,
            description: edited.description,
            location: edited.location,
            createdIn: edited.createdIn,
            recurrence: edited.recurrence,
            exceptions: existing.allDay == edited.allDay
                ? existing.exceptions
                : [
                    for (final e in existing.exceptions)
                      CalendarAppointmentEditing.convertInstant(
                        e,
                        allDay: edited.allDay,
                        hour: CalendarAppointmentEditing.defaultStartHour,
                        frame: frame,
                      ),
                  ],
          ),
    ];
  }

  static CalendarAppointment _require(
    List<CalendarAppointment> appointments,
    String id,
  ) {
    for (final a in appointments) {
      if (a.id == id) return a;
    }
    throw ArgumentError.value(id, 'appointmentId', 'No such appointment');
  }

  static DateTime _requireOccurrence(
    CalendarAppointment series,
    DateTime occurrenceStart,
  ) {
    final start = occurrenceStart.toUtc();
    // The window is the day itself: an occurrence starts at one instant, and
    // asking for a day is enough to find it without expanding a whole series.
    final day = DateTime.utc(start.year, start.month, start.day);
    final candidates = <DateTime>{
      ...series.occurrencesIn(day, day.add(const Duration(days: 1))),
      ...series.exceptions,
    };
    for (final c in candidates) {
      if (c == start) return c;
    }
    throw ArgumentError.value(
      occurrenceStart,
      'occurrenceStart',
      'Not an occurrence of appointment ${series.id}',
    );
  }

  static CalendarAppointment _respawn(
    CalendarAppointment a, {
    required List<DateTime> exceptions,
  }) => CalendarAppointment(
    id: a.id,
    title: a.title,
    allDay: a.allDay,
    start: a.start,
    end: a.end,
    description: a.description,
    location: a.location,
    createdIn: a.createdIn,
    recurrence: a.recurrence,
    exceptions: exceptions,
  );
}

/// Form conversion — timed to all-day and back — for a single appointment.
class CalendarAppointmentEditing {
  const CalendarAppointmentEditing._();

  /// The window a former all-day event is given when it becomes timed.
  ///
  /// A conversion has to choose *something*: an all-day event carries no wall
  /// clock to restore. Midnight-to-midnight would be a zero-length event on
  /// the first day, so the choice is a working day, and the user adjusts the
  /// pickers that are already open in front of them.
  static const int defaultStartHour = 9;
  static const int _defaultEndHour = 17;

  /// Returns [appointment] in the requested form, or the same instance when it
  /// is already in it.
  ///
  /// **To all-day**: both ends truncate to their date, so the
  /// inclusive-last-day end is the day the timed event ended on.
  ///
  /// **To timed**: the first day gets [defaultStartHour] and the **last
  /// included** day gets [_defaultEndHour] — not the midnight that starts the
  /// day after, and not the midnight that starts the last day, either of which
  /// would silently shorten a multi-day event by a day.
  ///
  /// Exceptions change form alongside the event: an EXDATE has to equal an
  /// occurrence start to match one, and the occurrence starts have just moved.
  ///
  /// [frame] is whose day is meant. To all-day, an instant becomes the date it
  /// falls on **in that frame**; to timed, a date becomes that hour **of that
  /// frame's** day. The default is UTC, so a caller with no user in front of
  /// it gets the same answer on every machine.
  static CalendarAppointment setAllDay(
    CalendarAppointment appointment,
    bool allDay, {
    CalendarTimeFrame frame = CalendarTimeFrame.utc,
  }) {
    if (appointment.allDay == allDay) return appointment;
    DateTime convert(DateTime t, int hour) =>
        convertInstant(t, allDay: allDay, hour: hour, frame: frame);

    return CalendarAppointment(
      id: appointment.id,
      title: appointment.title,
      allDay: allDay,
      start: convert(appointment.start, defaultStartHour),
      end: convert(appointment.end, _defaultEndHour),
      description: appointment.description,
      location: appointment.location,
      createdIn: appointment.createdIn,
      recurrence: appointment.recurrence,
      exceptions: [
        for (final e in appointment.exceptions) convert(e, defaultStartHour),
      ],
    );
  }

  /// One instant of an appointment changing form: to the date it falls on in
  /// [frame] when [allDay], and otherwise — [value] being a timezone-free
  /// date — to [hour] o'clock of that date in [frame].
  static DateTime convertInstant(
    DateTime value, {
    required bool allDay,
    required int hour,
    CalendarTimeFrame frame = CalendarTimeFrame.utc,
  }) {
    if (allDay) return frame.dateOf(value);
    final date = value.toUtc();
    return frame.instant(date.year, date.month, date.day, hour);
  }
}
