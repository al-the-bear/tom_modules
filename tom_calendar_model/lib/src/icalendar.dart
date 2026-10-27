/// An iCalendar (RFC 5545) codec for appointments and tasks.
///
/// Output is **deterministic** (components sorted, stable property order) so
/// exports can be compared byte-wise.
///
/// A component's anchor — which part of the producer's own container it
/// belongs to — travels as the non-standard `<prefix>-SECTION` property
/// (RFC 5545 §3.8.8.2 reserves `X-` names for this), so an export→import
/// round-trip keeps it while any standard calendar app still reads the file.
///
/// **Import never loses anything silently.** The codec has no timezone
/// database and maps only a subset of RFC 5545, so every value it reinterprets
/// and every property it drops is reported in [ICalendarImport.warnings]. That
/// report — not the mapping itself — is what makes a lossy import honest.
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'appointment.dart';
import 'recurrence.dart';
import 'task.dart';

/// One exported/imported event: an appointment plus its anchor.
class ICalendarEvent {
  final CalendarAppointment appointment;

  /// Which part of the producer's own container the appointment belongs to,
  /// carried as the `<prefix>-SECTION` extension property; null when none.
  final String? anchor;

  const ICalendarEvent({required this.appointment, this.anchor});

  @override
  bool operator ==(Object other) =>
      other is ICalendarEvent &&
      other.appointment == appointment &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(appointment, anchor);

  @override
  String toString() => 'ICalendarEvent($appointment @$anchor)';
}

/// One exported/imported `VTODO`: a task plus its anchor.
class ICalendarTask {
  final CalendarTask task;

  /// See [ICalendarEvent.anchor].
  final String? anchor;

  const ICalendarTask({required this.task, this.anchor});

  @override
  bool operator ==(Object other) =>
      other is ICalendarTask && other.task == task && other.anchor == anchor;

  @override
  int get hashCode => Object.hash(task, anchor);

  @override
  String toString() => 'ICalendarTask($task @$anchor)';
}

/// Why an import had to reinterpret or discard something.
enum ICalendarWarningKind {
  /// A component carried no `UID`, so one was minted.
  mintedUid,

  /// A date-time was not in UTC (`TZID=` or floating) and — with no timezone database here
  /// having no timezone database — was taken as UTC.
  assumedUtc,

  /// An `RRULE` outside the recurrence subset. It is stored verbatim but
  /// renders as its base occurrence only.
  unsupportedRecurrence,

  /// A property or sub-component this codec does not model was discarded.
  droppedProperty,

  /// A whole component was skipped: it lacked the `DTSTART`/`SUMMARY` it
  /// needs, or carried a value the model cannot hold (a timed `DTEND`,
  /// `DURATION` or `EXDATE` on an all-day event).
  skippedComponent,

  /// A `RECURRENCE-ID` override was imported as an occurrence edit: its occurrence
  /// was added to the series' `EXDATE` and it became a standalone appointment
  /// with an id of its own. The series is never replaced.
  detachedOccurrence,
}

/// One entry of the import warnings report.
class ICalendarWarning {
  final ICalendarWarningKind kind;

  /// `UID` of the component the warning came from, when there was one.
  final String? uid;

  final String message;

  const ICalendarWarning({required this.kind, required this.message, this.uid});

  @override
  String toString() => '[${kind.name}]${uid == null ? '' : ' $uid:'} $message';
}

/// The result of decoding an `.ics` document.
class ICalendarImport {
  final List<ICalendarEvent> events;
  final List<ICalendarTask> tasks;

  /// Everything the import reinterpreted or discarded, deduplicated so a
  /// 500-event file that drops `CATEGORIES` yields one entry, not 500.
  final List<ICalendarWarning> warnings;

  /// `RECURRENCE-ID` overrides whose series was **not** in the file.
  ///
  /// The override itself is already in [events] as a standalone appointment;
  /// what the codec could not do is add its occurrence to the series' `EXDATE`,
  /// because the series is not in front of it. The import plan does that
  /// against the series the target section already holds.
  final List<ICalendarDetachedOccurrence> detachedOccurrences;

  /// Whether the codec's own producer wrote the file — its `PRODID` is
  /// [ICalendarCodec.prodId]. Such a file states every field the producer
  /// keeps, so an import can take its tasks as they are.
  final bool writtenByProducer;

  const ICalendarImport({
    this.events = const [],
    this.tasks = const [],
    this.warnings = const [],
    this.detachedOccurrences = const [],
    this.writtenByProducer = false,
  });
}

/// One occurrence an imported `RECURRENCE-ID` override took out of a series
/// that the decoded file did not carry.
class ICalendarDetachedOccurrence {
  /// The `UID` of the series the override belongs to.
  final String seriesId;

  /// The original start of the overridden occurrence — what joins the
  /// series' `EXDATE`.
  final DateTime occurrenceStart;

  /// Whether [occurrenceStart] is a date (`VALUE=DATE`), so the plan can
  /// refuse it against a series of the other form.
  final bool isDate;

  /// The id the override was imported under.
  final String detachedId;

  const ICalendarDetachedOccurrence({
    required this.seriesId,
    required this.occurrenceStart,
    required this.isDate,
    required this.detachedId,
  });
}

/// Encoder/decoder between appointments and tasks and an `.ics` document.
///
/// The producer names itself with [prodId] and its own extension properties
/// with [extensionPrefix]: `<prefix>-SECTION` (an anchor), `-CREATED-IN` (the
/// offset an appointment was created in), and on a task `-DEPENDS`,
/// `-ESTIMATE`, `-TAGS` and `-FIELDS`. Those are written and read; every other
/// property a component carries is reported as dropped.
class ICalendarCodec {
  /// The `PRODID` this codec writes, and recognises as its own on import.
  final String prodId;

  /// The `X-` prefix of the producer's extension properties, e.g. `X-ACME`.
  final String extensionPrefix;

  const ICalendarCodec({required this.prodId, required this.extensionPrefix});

  /// Properties [decode] maps onto the model — everything else in a VEVENT is
  /// reported as dropped.
  Set<String> get _eventProperties => {
    'UID',
    'DTSTAMP',
    'DTSTART',
    'DTEND',
    'DURATION',
    'SUMMARY',
    'DESCRIPTION',
    'LOCATION',
    'RRULE',
    'EXDATE',
    'RECURRENCE-ID',
    '$extensionPrefix-SECTION',
    '$extensionPrefix-CREATED-IN',
  };

  Set<String> get _taskProperties => {
    'UID',
    'DTSTAMP',
    'SUMMARY',
    'DESCRIPTION',
    'STATUS',
    'PERCENT-COMPLETE',
    'DUE',
    'PRIORITY',
    '$extensionPrefix-SECTION',
    '$extensionPrefix-DEPENDS',
    '$extensionPrefix-ESTIMATE',
    '$extensionPrefix-TAGS',
    '$extensionPrefix-FIELDS',
  };

  // ---------------------------------------------------------------- encode

  /// Encodes [events] and [tasks] as one VCALENDAR document.
  ///
  /// [dtStamp] becomes every component's required `DTSTAMP`. It defaults to
  /// the Unix epoch so output is deterministic; pass `DateTime.now()` when
  /// exporting for real interchange.
  String encode({
    List<ICalendarEvent> events = const [],
    List<ICalendarTask> tasks = const [],
    DateTime? dtStamp,
  }) {
    final stamp = _encodeDateTime(dtStamp ?? DateTime.utc(1970));
    final sortedEvents = List.of(events)
      ..sort((a, b) {
        final byStart = a.appointment.start.compareTo(b.appointment.start);
        return byStart != 0
            ? byStart
            : a.appointment.id.compareTo(b.appointment.id);
      });
    final sortedTasks = List.of(tasks)
      ..sort((a, b) {
        // Undated tasks sort last; ties break on id, so the order is total.
        final ad = a.task.due, bd = b.task.due;
        if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
        if (ad == null && bd != null) return 1;
        if (ad != null && bd == null) return -1;
        return a.task.id.compareTo(b.task.id);
      });
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$prodId',
      for (final event in sortedEvents) ..._eventLines(event, stamp),
      for (final task in sortedTasks) ..._taskLines(task, stamp),
      'END:VCALENDAR',
    ];
    return lines.map(_fold).map((l) => '$l\r\n').join();
  }

  List<String> _eventLines(ICalendarEvent event, String stamp) {
    final a = event.appointment;
    final dateParam = a.allDay ? ';VALUE=DATE' : '';
    return [
      'BEGIN:VEVENT',
      'UID:${_escape(a.id)}',
      'DTSTAMP:$stamp',
      'DTSTART$dateParam:${_encodeInstant(a.start, a.allDay)}',
      // The wire DTEND of an all-day event is exclusive (RFC 5545 §3.6.1);
      // the model stores the last included day.
      'DTEND$dateParam:${_encodeInstant(a.allDay ? a.end.add(const Duration(days: 1)) : a.end, a.allDay)}',
      'SUMMARY:${_escape(a.title)}',
      if (a.description != null) 'DESCRIPTION:${_escape(a.description!)}',
      if (a.location != null) 'LOCATION:${_escape(a.location!)}',
      if (a.recurrence != null) 'RRULE:${a.recurrence}',
      if (a.exceptions.isNotEmpty)
        'EXDATE$dateParam:'
            '${a.exceptions.map((e) => _encodeInstant(e, a.allDay)).join(',')}',
      if (event.anchor != null)
        '$extensionPrefix-SECTION:${_escape(event.anchor!)}',
      // The instants above are UTC, which every reader agrees on; this is
      // the wall clock their author meant.
      if (a.createdIn != null) '$extensionPrefix-CREATED-IN:${a.createdIn}',
      'END:VEVENT',
    ];
  }

  List<String> _taskLines(ICalendarTask entry, String stamp) {
    final t = entry.task;
    final fields = t.fields;
    return [
      'BEGIN:VTODO',
      'UID:${_escape(t.id)}',
      'DTSTAMP:$stamp',
      'SUMMARY:${_escape(t.title)}',
      if (t.description != null) 'DESCRIPTION:${_escape(t.description!)}',
      'STATUS:${t.status.wire}',
      if (t.due != null) 'DUE;VALUE=DATE:${_encodeDate(t.due!)}',
      if (t.priority != null) 'PRIORITY:${t.priority}',
      // The facets RFC 5545 has no home for. Emitting them keeps export
      // lossless instead of quietly halving the model on the way out.
      if (t.dependencies.isNotEmpty)
        '$extensionPrefix-DEPENDS:${t.dependencies.map(_escape).join(',')}',
      if (t.estimate != null)
        '$extensionPrefix-ESTIMATE:${_escape(t.estimate!)}',
      if (entry.anchor != null)
        '$extensionPrefix-SECTION:${_escape(entry.anchor!)}',
      if (t.tags.isNotEmpty)
        '$extensionPrefix-TAGS:${t.tags.map(_escape).join(',')}',
      if (fields != null && fields.isNotEmpty)
        '$extensionPrefix-FIELDS:${_escape(jsonEncode(fields))}',
      'END:VTODO',
    ];
  }

  // ---------------------------------------------------------------- decode

  /// Decodes the VEVENTs and VTODOs of an `.ics` document.
  ///
  /// Never throws on foreign input: an unusable component is skipped and
  /// reported rather than aborting the whole import.
  ICalendarImport decode(String ics) {
    final report = _WarningReport();
    final decoded = <_DecodedEvent>[];
    final tasks = <ICalendarTask>[];

    final lines = _unfold(ics);
    String? component;
    var properties = <_Property>[];
    var nested = <String>[];
    // A top-level component this codec does not model, being skipped whole.
    // `VTIMEZONE` nests `STANDARD`/`DAYLIGHT`, so this is a depth, not a flag.
    final skipping = <String>[];
    var writtenByProducer = false;

    for (final line in lines) {
      final upper = line.toUpperCase();
      if (skipping.isNotEmpty) {
        if (upper.startsWith('BEGIN:')) {
          skipping.add(upper.substring('BEGIN:'.length));
        } else if (upper.startsWith('END:')) {
          skipping.removeLast();
        }
        continue;
      }
      if (nested.isNotEmpty) {
        if (upper.startsWith('BEGIN:')) {
          nested.add(upper.substring('BEGIN:'.length));
        } else if (upper.startsWith('END:')) {
          nested.removeLast();
        }
        continue;
      }
      if (upper == 'BEGIN:VEVENT' || upper == 'BEGIN:VTODO') {
        component = upper.substring('BEGIN:'.length);
        properties = [];
        continue;
      }
      if (component != null && upper == 'END:$component') {
        if (component == 'VEVENT') {
          final event = _eventFrom(properties, report);
          if (event != null) decoded.add(event);
        } else {
          final task = _taskFrom(properties, report);
          if (task != null) tasks.add(task);
        }
        component = null;
        continue;
      }
      if (component == null) {
        if (upper.startsWith('PRODID:')) {
          writtenByProducer = line.substring('PRODID:'.length).trim() == prodId;
          continue;
        }
        // Top level. `VCALENDAR`'s own properties carry nothing this codec
        // models, but a whole component beside the events — the `VTIMEZONE`
        // blocks a CalDAV server hoists into a collection export, a
        // `VJOURNAL`, a `VFREEBUSY` — is discarded, and an import is required to report the
        // report to say so rather than let it vanish.
        if (upper.startsWith('BEGIN:') && upper != 'BEGIN:VCALENDAR') {
          final name = upper.substring('BEGIN:'.length);
          skipping.add(name);
          report.droppedComponent(name);
        }
        continue;
      }
      if (upper.startsWith('BEGIN:')) {
        // A sub-component (VALARM, …) this codec does not model.
        final name = upper.substring('BEGIN:'.length);
        nested.add(name);
        report.droppedComponent(name);
        continue;
      }
      final property = _Property.parse(line);
      if (property != null) properties.add(property);
    }

    final detached = <ICalendarDetachedOccurrence>[];
    final events = _detachOverrides(decoded, report, detached);
    return ICalendarImport(
      events: events,
      tasks: tasks,
      warnings: report.warnings,
      detachedOccurrences: detached,
      writtenByProducer: writtenByProducer,
    );
  }

  /// Namespace of the ids a detached override is imported under.
  static final _overrideNamespace = Namespace.url.value;

  /// Imports every `RECURRENCE-ID` override as an occurrence edit.
  ///
  /// An override shares its series' `UID`, so read naively it **replaces the
  /// series** — the whole meeting collapses to the one moved occurrence. An edited
  /// occurrence is already expressible here: an `EXDATE` on the
  /// series plus a standalone appointment. So that is what an override
  /// becomes. The series stays as it is in the file, gaining one exception.
  ///
  /// The standalone appointment's id is a fresh UUID — a v5 of the series
  /// `UID` and the occurrence, so importing the same file twice updates the
  /// detached appointment instead of adding a second one.
  List<ICalendarEvent> _detachOverrides(
    List<_DecodedEvent> decoded,
    _WarningReport report,
    List<ICalendarDetachedOccurrence> detached,
  ) {
    final series = <String, ICalendarEvent>{};
    for (final d in decoded) {
      if (d.recurrenceId == null) series[d.event.appointment.id] = d.event;
    }
    final standalone = <ICalendarEvent>[];
    for (final d in decoded) {
      final rid = d.recurrenceId;
      if (rid == null) continue;
      final override = d.event.appointment;
      final seriesId = override.id;
      final master = series[seriesId];
      final stamp = d.recurrenceIdIsDate
          ? CalendarAppointment.encodeDate(rid)
          : CalendarAppointment.encodeTime(rid);
      if (master != null && master.appointment.allDay != d.recurrenceIdIsDate) {
        report.add(
          ICalendarWarningKind.skippedComponent,
          'the override of $seriesId at $stamp names its occurrence as a '
          '${d.recurrenceIdIsDate ? 'date' : 'date-time'}, but the series is '
          '${master.appointment.allDay ? 'all-day' : 'timed'}; it was skipped',
          uid: seriesId,
          dedupe: 'override-form|$seriesId|$stamp',
        );
        continue;
      }
      final newId = const Uuid().v5(
        _overrideNamespace,
        '$extensionPrefix:ical-override:$seriesId|$stamp',
      );
      standalone.add(
        ICalendarEvent(
          appointment: CalendarAppointment(
            id: newId,
            title: override.title,
            allDay: override.allDay,
            start: override.start,
            end: override.end,
            description: override.description,
            location: override.location,
            createdIn: override.createdIn,
          ),
          anchor: d.event.anchor ?? master?.anchor,
        ),
      );
      if (master != null) {
        final a = master.appointment;
        if (!a.exceptions.contains(rid)) a.exceptions = [...a.exceptions, rid];
        report.add(
          ICalendarWarningKind.detachedOccurrence,
          'the occurrence of $seriesId at $stamp is overridden; it was added '
          'to the series\' EXDATE and imported as the standalone appointment '
          '$newId',
          uid: seriesId,
          dedupe: 'override|$seriesId|$stamp',
        );
      } else {
        detached.add(
          ICalendarDetachedOccurrence(
            seriesId: seriesId,
            occurrenceStart: rid,
            isDate: d.recurrenceIdIsDate,
            detachedId: newId,
          ),
        );
        report.add(
          ICalendarWarningKind.detachedOccurrence,
          'the occurrence of $seriesId at $stamp is overridden, and the series '
          'is not in this file; the override was imported as the standalone '
          'appointment $newId, and the occurrence joins the series\' EXDATE '
          'where the calendar holds it',
          uid: seriesId,
          dedupe: 'override|$seriesId|$stamp',
        );
      }
    }
    return [
      for (final d in decoded)
        if (d.recurrenceId == null) d.event,
      ...standalone,
    ];
  }

  _DecodedEvent? _eventFrom(List<_Property> properties, _WarningReport report) {
    final byName = <String, List<_Property>>{};
    for (final p in properties) {
      (byName[p.name] ??= []).add(p);
    }

    final rawUid = byName['UID']?.first.value;
    final dtStart = byName['DTSTART']?.first;
    final summary = byName['SUMMARY']?.first.value;
    if (dtStart == null || summary == null) {
      report.add(
        ICalendarWarningKind.skippedComponent,
        'VEVENT ${rawUid ?? '(no UID)'} has no '
        '${dtStart == null ? 'DTSTART' : 'SUMMARY'} and was skipped',
        uid: rawUid,
        dedupe: 'skipped|VEVENT|${rawUid ?? properties.length}',
      );
      return null;
    }

    final uid = rawUid == null ? _mintUid(report) : _unescape(rawUid);
    for (final name in byName.keys) {
      if (!_eventProperties.contains(name)) {
        report.dropped(name, 'the $name property is not modelled');
      }
    }

    final allDay = dtStart.isDate;
    final occurrence = byName['RECURRENCE-ID']?.first.value.trim() ?? '';
    final start = _decodeInstant(dtStart, uid, report, occurrence: occurrence);
    if (start == null) {
      report.add(
        ICalendarWarningKind.skippedComponent,
        'VEVENT $uid has an unreadable DTSTART "${dtStart.value}"',
        uid: uid,
        dedupe: 'skipped|VEVENT|$uid',
      );
      return null;
    }

    /// Skips this component, naming why: an import may lose a
    /// component the model cannot hold, but never quietly and never by
    /// aborting the rest of the file.
    Null skip(String why) {
      report.add(
        ICalendarWarningKind.skippedComponent,
        'VEVENT $uid $why; the model cannot hold it and it was skipped',
        uid: uid,
        dedupe: 'skipped|VEVENT|$uid',
      );
      return null;
    }

    var end = start;
    final dtEnd = byName['DTEND']?.first;
    if (dtEnd != null) {
      if (allDay && !dtEnd.isDate) {
        return skip('is all-day but has a timed DTEND "${dtEnd.value}"');
      }
      final decoded = _decodeInstant(
        dtEnd,
        uid,
        report,
        occurrence: occurrence,
      );
      if (decoded != null) {
        // An all-day DTEND is exclusive on the wire; the model keeps the last
        // included day.
        end = allDay ? decoded.subtract(const Duration(days: 1)) : decoded;
      }
    } else {
      final duration = byName['DURATION']?.first.value;
      if (duration != null) {
        final parsed = _parseDuration(duration);
        if (parsed != null) {
          if (allDay && parsed.inSeconds % Duration.secondsPerDay != 0) {
            return skip('is all-day but has a timed DURATION "$duration"');
          }
          // An all-day DURATION ends where the exclusive DTEND would, so it
          // takes the same step back to the last included day: `P1D` is one
          // day, not two.
          end = allDay
              ? start.add(parsed).subtract(const Duration(days: 1))
              : start.add(parsed);
        }
      }
    }
    if (end.isBefore(start)) end = start;

    final recurrence = byName['RRULE']?.first.value;
    if (recurrence != null &&
        CalendarRecurrenceRule.tryParse(recurrence, start: start) == null) {
      report.add(
        ICalendarWarningKind.unsupportedRecurrence,
        'RRULE "$recurrence" is outside the supported subset; it is kept '
        'verbatim but renders as a single occurrence',
        uid: uid,
        dedupe: 'rrule|$uid',
      );
    }

    final exceptions = <DateTime>[];
    for (final exdate in byName['EXDATE'] ?? const <_Property>[]) {
      for (final value in exdate.value.split(',')) {
        if (allDay && !exdate.withValue(value).isDate) {
          return skip('is all-day but has a timed EXDATE "$value"');
        }
        final decoded = _decodeInstant(
          exdate.withValue(value),
          uid,
          report,
          occurrence: occurrence,
        );
        if (decoded != null) exceptions.add(decoded);
      }
    }

    final description = byName['DESCRIPTION']?.first.value;
    final location = byName['LOCATION']?.first.value;
    final anchor = byName['$extensionPrefix-SECTION']?.first.value;
    String? createdIn = byName['$extensionPrefix-CREATED-IN']?.first.value;
    if (createdIn != null) {
      try {
        CalendarAppointment.parseOffset(createdIn);
      } on FormatException {
        report.add(
          ICalendarWarningKind.droppedProperty,
          '$extensionPrefix-CREATED-IN "$createdIn" is not an offset; the event is '
          'imported without it.',
          uid: uid,
          dedupe: 'created-in|$uid',
        );
        createdIn = null;
      }
    }

    DateTime? recurrenceId;
    var recurrenceIdIsDate = false;
    final rawRecurrenceId = byName['RECURRENCE-ID']?.first;
    if (rawRecurrenceId != null) {
      recurrenceId = _decodeInstant(
        rawRecurrenceId,
        uid,
        report,
        occurrence: occurrence,
      );
      recurrenceIdIsDate = rawRecurrenceId.isDate;
      if (recurrenceId == null) {
        return skip(
          'has an unreadable RECURRENCE-ID '
          '"${rawRecurrenceId.value}"',
        );
      }
    }

    final CalendarAppointment appointment;
    try {
      appointment = CalendarAppointment(
        id: uid,
        title: _unescape(summary),
        allDay: allDay,
        start: start,
        end: end,
        description: description == null ? null : _unescape(description),
        location: location == null ? null : _unescape(location),
        createdIn: createdIn,
        recurrence: recurrence,
        exceptions: exceptions,
      );
    } on ArgumentError catch (error) {
      // The checks above name every case known to reach here; this is the
      // guarantee that an unforeseen one costs one component, not the file.
      return skip('is not a valid appointment (${error.message})');
    }
    return _DecodedEvent(
      ICalendarEvent(
        appointment: appointment,
        anchor: anchor == null ? null : _unescape(anchor),
      ),
      recurrenceId: recurrenceId,
      recurrenceIdIsDate: recurrenceIdIsDate,
    );
  }

  ICalendarTask? _taskFrom(List<_Property> properties, _WarningReport report) {
    final byName = <String, List<_Property>>{};
    for (final p in properties) {
      (byName[p.name] ??= []).add(p);
    }

    final rawUid = byName['UID']?.first.value;
    final summary = byName['SUMMARY']?.first.value;
    if (summary == null) {
      report.add(
        ICalendarWarningKind.skippedComponent,
        'VTODO ${rawUid ?? '(no UID)'} has no SUMMARY and was skipped',
        uid: rawUid,
        dedupe: 'skipped|VTODO|${rawUid ?? properties.length}',
      );
      return null;
    }

    final uid = rawUid == null ? _mintUid(report) : _unescape(rawUid);
    for (final name in byName.keys) {
      if (!_taskProperties.contains(name)) {
        report.dropped(name, 'the $name property is not modelled');
      }
    }

    final percent = int.tryParse(byName['PERCENT-COMPLETE']?.first.value ?? '');
    var status = CalendarTaskStatus.needsAction;
    final rawStatus = byName['STATUS']?.first.value.toUpperCase();
    if (rawStatus != null) {
      final mapped = CalendarTaskStatus.fromWire(rawStatus);
      if (mapped == null) {
        report.dropped(
          'STATUS',
          'the VTODO status "$rawStatus" is not recognised; treated as '
              'NEEDS-ACTION',
        );
      } else {
        status = mapped;
      }
    } else if (percent != null) {
      // PERCENT-COMPLETE is an import-only inference: RFC 5545 lets a client
      // send progress without STATUS.
      status = percent >= 100
          ? CalendarTaskStatus.completed
          : percent > 0
          ? CalendarTaskStatus.inProcess
          : CalendarTaskStatus.needsAction;
    }

    DateTime? due;
    final rawDue = byName['DUE']?.first;
    if (rawDue != null) {
      // A task's due is a date, so a timed DUE keeps only its date.
      due = _decodeInstant(rawDue, uid, report);
    }

    // 0 is "undefined"; anything outside 0–9 is not a priority.
    final rawPriority = int.tryParse(byName['PRIORITY']?.first.value ?? '');
    final priority = rawPriority != null && rawPriority >= 1 && rawPriority <= 9
        ? rawPriority
        : null;

    final description = byName['DESCRIPTION']?.first.value;
    final anchor = byName['$extensionPrefix-SECTION']?.first.value;
    final estimate = byName['$extensionPrefix-ESTIMATE']?.first.value;
    return ICalendarTask(
      task: CalendarTask(
        id: uid,
        title: _unescape(summary),
        description: description == null ? null : _unescape(description),
        status: status,
        priority: priority,
        due: due,
        estimate: estimate == null ? null : _unescape(estimate),
        tags: _splitList(byName['$extensionPrefix-TAGS']?.first.value),
        dependencies: _splitList(
          byName['$extensionPrefix-DEPENDS']?.first.value,
        ),
        fields: _decodeFields(
          byName['$extensionPrefix-FIELDS']?.first.value,
          uid,
          report,
        ),
      ),
      anchor: anchor == null ? null : _unescape(anchor),
    );
  }

  /// Reads `<prefix>-FIELDS` as a JSON object. A value that is not one is
  /// reported and dropped — the task itself still imports.
  Map<String, Object?>? _decodeFields(
    String? raw,
    String uid,
    _WarningReport report,
  ) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(_unescape(raw));
      if (map is! Map) throw const FormatException('not an object');
      return map.cast<String, Object?>();
    } on FormatException catch (error) {
      report.dropped(
        '$extensionPrefix-FIELDS',
        '$extensionPrefix-FIELDS of VTODO $uid could not be read: '
            '${error.message}',
      );
      return null;
    }
  }

  static List<String> _splitList(String? value) =>
      value == null || value.isEmpty
      ? const []
      : [for (final v in value.split(',')) _unescape(v)];

  String _mintUid(_WarningReport report) {
    final uid = const Uuid().v4();
    report.add(
      ICalendarWarningKind.mintedUid,
      'a component carried no UID; "$uid" was minted for it',
      uid: uid,
      dedupe: 'minted|$uid',
    );
    return uid;
  }

  // --- date-time (RFC 5545 §3.3.4/§3.3.5) ----------------------------------

  static String _encodeDateTime(DateTime t) {
    final u = t.toUtc();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${p2(u.month)}${p2(u.day)}'
        'T${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z';
  }

  static String _encodeDate(DateTime t) {
    final u = t.toUtc();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${p2(u.month)}${p2(u.day)}';
  }

  static String _encodeInstant(DateTime t, bool asDate) =>
      asDate ? _encodeDate(t) : _encodeDateTime(t);

  static final RegExp _wireDateTime = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$',
  );
  static final RegExp _wireDate = RegExp(r'^(\d{4})(\d{2})(\d{2})$');

  /// Decodes one date/date-time property value.
  ///
  /// A value that is not already UTC — carrying `TZID=` or floating — is
  /// **taken as UTC and always reported**. The UTC-only time policy permits the
  /// reinterpretation (there is no timezone database); the import contract forbids
  /// doing it quietly, which is the defect this codec was rebuilt to remove.
  ///
  /// The report holds one entry per **component** ([occurrence] tells a
  /// `RECURRENCE-ID` override from its series, which shares its `UID`), so
  /// DTSTART and DTEND of one event warn once and an override, which becomes
  /// an appointment of its own, warns for itself.
  DateTime? _decodeInstant(
    _Property property,
    String? uid,
    _WarningReport report, {
    String occurrence = '',
  }) {
    final value = property.value.trim();
    final date = _wireDate.firstMatch(value);
    if (date != null) {
      int g(int i) => int.parse(date.group(i)!);
      return DateTime.utc(g(1), g(2), g(3));
    }
    final match = _wireDateTime.firstMatch(value);
    if (match == null) return null;
    if (match.group(7) != 'Z') {
      final tzid = property.parameters['TZID'];
      report.add(
        ICalendarWarningKind.assumedUtc,
        tzid == null
            ? '${property.name} "$value" carries no timezone (floating time); '
                  'there is no timezone database and it was taken as UTC'
            : '${property.name} "$value" is in TZID=$tzid; there is no '
                  'timezone database and took it as UTC',
        uid: uid,
        dedupe: 'tz|$uid|$occurrence',
      );
    }
    int g(int i) => int.parse(match.group(i)!);
    return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  }

  static final RegExp _wireDuration = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  );

  /// RFC 5545 §3.3.6 duration, used when a VEVENT sends `DURATION` instead of
  /// `DTEND`.
  static Duration? _parseDuration(String value) {
    final match = _wireDuration.firstMatch(value.trim());
    if (match == null) return null;
    int g(int i) => int.tryParse(match.group(i) ?? '') ?? 0;
    final duration = Duration(
      days: g(2) * 7 + g(3),
      hours: g(4),
      minutes: g(5),
      seconds: g(6),
    );
    return match.group(1) == '-' ? -duration : duration;
  }

  // --- TEXT escaping (RFC 5545 §3.3.11) ------------------------------------

  static String _escape(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');

  static String _unescape(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length) {
        i++;
        final next = s[i];
        out.write(switch (next) {
          'n' || 'N' => '\n',
          _ => next,
        });
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  // --- line folding (RFC 5545 §3.1, 75-octet limit) ------------------------

  static String _fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = StringBuffer();
    var octets = 0;
    var first = true;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      final size = utf8.encode(char).length;
      // Continuation lines start with one space, which counts as an octet.
      final limit = first ? 75 : 74;
      if (octets + size > limit) {
        out.write('\r\n ');
        octets = 0;
        first = false;
      }
      out.write(char);
      octets += size;
    }
    return out.toString();
  }

  static List<String> _unfold(String ics) {
    final raw = ics.replaceAll('\r\n', '\n').split('\n');
    final lines = <String>[];
    for (final line in raw) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] = lines.last + line.substring(1);
      } else {
        lines.add(line);
      }
    }
    return lines;
  }
}

/// A decoded VEVENT and, for a `RECURRENCE-ID` override, the occurrence it
/// overrides.
class _DecodedEvent {
  final ICalendarEvent event;
  final DateTime? recurrenceId;
  final bool recurrenceIdIsDate;

  const _DecodedEvent(
    this.event, {
    this.recurrenceId,
    this.recurrenceIdIsDate = false,
  });
}

/// One content line: `NAME[;PARAM=VALUE]*:VALUE`.
class _Property {
  final String name;
  final Map<String, String> parameters;
  final String value;

  const _Property(this.name, this.parameters, this.value);

  _Property withValue(String other) => _Property(name, parameters, other);

  /// Whether the value is a date rather than a date-time (`VALUE=DATE`).
  bool get isDate =>
      parameters['VALUE']?.toUpperCase() == 'DATE' ||
      (parameters['VALUE'] == null &&
          ICalendarCodec._wireDate.hasMatch(value.trim()));

  static _Property? parse(String line) {
    final colon = line.indexOf(':');
    if (colon < 0) return null;
    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final segments = head.split(';');
    final parameters = <String, String>{};
    for (final segment in segments.skip(1)) {
      final eq = segment.indexOf('=');
      if (eq < 0) continue;
      parameters[segment.substring(0, eq).toUpperCase()] = _stripQuotes(
        segment.substring(eq + 1),
      );
    }
    return _Property(segments.first.toUpperCase(), parameters, value);
  }

  static String _stripQuotes(String s) =>
      s.length >= 2 && s.startsWith('"') && s.endsWith('"')
      ? s.substring(1, s.length - 1)
      : s;
}

/// Collects warnings, deduplicated, in first-seen order.
///
/// Deduplication is what makes the report usable: a dropped property is
/// reported **once per name per import**, not once per component,
/// and a timezone assumption once per component rather than once per date
/// field.
class _WarningReport {
  final _seen = <String>{};
  final warnings = <ICalendarWarning>[];

  void add(
    ICalendarWarningKind kind,
    String message, {
    String? uid,
    required String dedupe,
  }) {
    if (!_seen.add('${kind.name}|$dedupe')) return;
    warnings.add(ICalendarWarning(kind: kind, message: message, uid: uid));
  }

  void dropped(String name, String message) =>
      add(ICalendarWarningKind.droppedProperty, message, dedupe: 'name|$name');

  /// A whole component this codec does not model — `VALARM` inside an event,
  /// `VTIMEZONE`/`VJOURNAL`/`VFREEBUSY` beside one. Namespaced apart from
  /// [dropped] so a component and a property of the same name each report.
  void droppedComponent(String name) => add(
    ICalendarWarningKind.droppedProperty,
    'the $name component is not modelled',
    dedupe: 'component|$name',
  );
}
