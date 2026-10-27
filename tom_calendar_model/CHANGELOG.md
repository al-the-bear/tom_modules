# Changelog

## 0.1.0

The package was `tom_core_calendar` in the `tom_core` repository; it is now
`tom_calendar_model` in `tom_modules`, with the barrel
`package:tom_calendar_model/tom_calendar_model.dart`. Type names are unchanged.

### Added

- **Appointments.** `CalendarAppointment`: timed in UTC or all-day by date,
  the creation offset, a verbatim RRULE with its parsed form, exceptions, a
  deterministic map form and on-demand occurrences.
- **Recurrence.** `CalendarRecurrenceRule` — the interpreted subset, its
  parser, its writer (the exact inverse) and its expansion.
- **Editing.** `CalendarOccurrenceEdit`, `CalendarAppointmentEditing` and
  `CalendarRecurrenceEditing`, as pure list transforms.
- **Frames.** `CalendarTimeFrame` and `CalendarClock`.
- **Times in words.** `calendarDescribeTimes` and `calendarDescribeRecurrence`.
- **Tasks.** `CalendarTask` and `CalendarTaskStatus`.
- **iCalendar.** `ICalendarCodec` for events and tasks, with the producer's
  `PRODID` and extension prefix, override detachment and the warnings report.
