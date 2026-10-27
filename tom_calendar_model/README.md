# tom_calendar_model

Published on pub.dev as [`tom_calendar_model` 0.1.0](https://pub.dev/packages/tom_calendar_model).

> **Attribution.** The Tom Framework is developed by Peter Nicolai Alexis Kyaw.
> These packages are BSD-3-Clause licensed and published on pub.dev.

Calendar model and iCalendar interchange: an appointment that is timed in UTC
or all-day by date, a recurrence subset that is parsed, written and expanded on
demand, the occurrence actions an editor offers, the sentences a printout uses
for an appointment's times, and an RFC 5545 codec for events and tasks that
reports everything an import had to reinterpret or drop. An application keeps
its appointments where it likes; it gets the rules that make them a calendar.

## Overview

- **Appointments** (`CalendarAppointment`) are timed — UTC at second precision
  — or all-day, stored as UTC midnight with an inclusive last day. A timed
  appointment may record the offset of the place it was created in
  (`createdIn`, e.g. `+02:00`), so its wall clock there can be said again.
  `toMap`/`fromMap` give a deterministic map with a fixed field order and a
  closed field set.
- **Recurrence** is held **verbatim** as the RRULE string, and parsed into a
  `CalendarRecurrenceRule` only when it falls inside the subset this package
  interprets: `FREQ`, `INTERVAL`, `COUNT` or `UNTIL`, `BYDAY` (with ordinals on
  `MONTHLY`), `BYMONTHDAY`, and on `YEARLY` a `BYMONTH` + `BYMONTHDAY` pair that
  restates the start's date. A rule outside it renders as its base occurrence
  and survives a round trip untouched — degrade, never delete. `format` is the
  exact inverse of `tryParse`. Occurrences are expanded into the window asked
  for (`occurrencesIn`, `occurrencesOn`), never materialized.
- **Editing** is pure list transforms: `CalendarOccurrenceEdit` cancels one
  occurrence (an `EXDATE`, so it survives an export), detaches one as a
  standalone appointment, or replaces or deletes the series;
  `CalendarAppointmentEditing` converts between timed and all-day;
  `CalendarRecurrenceEditing` decides whether a rule can be edited and moves
  its weekdays with the day a frame reads.
- **Frames.** A day is read in a frame: `CalendarTimeFrame.utc`, a fixed
  offset, or the device's. `CalendarClock` pairs a frame with "now", so a host
  or a test can fix both.
- **Times in words.** `calendarDescribeTimes` gives an appointment's times in
  UTC, in the wall clock it was created in, and — when a device frame is given
  — in the reader's; `calendarDescribeRecurrence` says a rule as a sentence.
- **iCalendar.** `ICalendarCodec` encodes `VEVENT`s (`ICalendarEvent`) and
  `VTODO`s (`ICalendarTask` over `CalendarTask`) and decodes them back. The
  producer names itself with a `PRODID` and an extension prefix: an anchor, the
  creation offset and a task's estimate, tags, dependencies and other facets
  travel as `<prefix>-SECTION`, `-CREATED-IN`, `-ESTIMATE`, `-TAGS`, `-DEPENDS`
  and `-FIELDS`. A decode never throws on foreign input: what it reinterprets
  (a `TZID` taken as UTC, a minted `UID`) or drops (a `VALARM`, an unmodelled
  property) is listed as `ICalendarWarning`s, a `RECURRENCE-ID` override
  becomes an exception on its series plus a standalone appointment, and
  `writtenByProducer` says whether the file came from this producer.

## Installation

Add it from pub.dev:

```yaml
dependencies:
  tom_calendar_model: ^0.1.0
```

Dart SDK `^3.10.8`. It uses no Flutter and no `dart:io`, so it links into a
browser build.

## Features

| Type | What it does |
| ---- | ------------ |
| `CalendarAppointment` | One appointment: times, recurrence, exceptions, its map form and its occurrences. |
| `CalendarRecurrenceRule`, `CalendarRecurrenceFreq`, `CalendarByDay` | The recurrence subset: parse, format, expand. |
| `CalendarOccurrenceEdit`, `CalendarAppointmentEditing`, `CalendarRecurrenceEditing` | The editing transforms. |
| `CalendarTimeFrame`, `CalendarClock` | The frame a day is read in, and "now". |
| `calendarDescribeTimes`, `calendarDescribeRecurrence` | Times and rules in words. |
| `CalendarTask`, `CalendarTaskStatus` | A task — the codec's `VTODO`. |
| `ICalendarCodec`, `ICalendarEvent`, `ICalendarTask`, `ICalendarImport`, `ICalendarWarning`, `ICalendarWarningKind`, `ICalendarDetachedOccurrence` | RFC 5545 interchange and its report. |

## Example

```dart
import 'package:tom_calendar_model/tom_calendar_model.dart';

void main() {
  final standup = CalendarAppointment(
    id: 'standup',
    title: 'Standup',
    start: DateTime.utc(2026, 7, 6, 7),
    end: DateTime.utc(2026, 7, 6, 7, 15),
    createdIn: '+02:00',
    recurrence: 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4',
  );

  final july = standup.occurrencesIn(
    DateTime.utc(2026, 7),
    DateTime.utc(2026, 8),
  );
  print(july.map(CalendarAppointment.encodeTime).join(', '));

  final edited = CalendarOccurrenceEdit.deleteOccurrence(
    [standup],
    appointmentId: 'standup',
    occurrenceStart: july[1],
  );
  print(
    edited.single
        .occurrencesIn(DateTime.utc(2026, 7), DateTime.utc(2026, 8))
        .length,
  );

  print(calendarDescribeTimes(standup));
  print(calendarDescribeRecurrence(standup));

  const codec = ICalendarCodec(
    prodId: '-//Example//Planner//EN',
    extensionPrefix: 'X-PLANNER',
  );
  final ics = codec.encode(
    events: [ICalendarEvent(appointment: edited.single, anchor: 'team')],
    tasks: [
      ICalendarTask(
        task: CalendarTask(
          id: 'agenda',
          title: 'Write the agenda',
          status: CalendarTaskStatus.inProcess,
          priority: 3,
          due: DateTime.utc(2026, 7, 6),
        ),
      ),
    ],
  );
  final back = codec.decode(ics);
  print(back.writtenByProducer);
  print(back.events.single.anchor);
  print(back.events.single.appointment.exceptions.length);
  print(back.tasks.single.task.status.wire);
  print(back.warnings.length);
}
```

The compiled form of this section is
[`example/readme_example.dart`](example/readme_example.dart), and
`test/readme_example_test.dart` asserts what it prints.

## Dependencies

| Dependency | Kind | For |
| ---------- | ---- | --- |
| `uuid` | runtime | `UID`s the codec mints, and stable ids for detached overrides |
| `test`, `lints` | dev | the suite |

## Status

Version **0.1.0**. `dart test` runs the suite: the time frames, the recurrence
subset and its editing, the times in words, the iCalendar codec for events and
tasks, the package's shape, and the example. `tool/test_in_zones.sh` runs it
once per time zone, from UTC-11 to UTC+14.
