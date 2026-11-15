# tom_calendar_ui

Calendar editing widgets over tom_calendar_model: date and time fields that
read and write UTC storage in the time frame the host gives, the repeat
control for the recurrence subset, and the appointment editor.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Calendar fields | `lib/src/calendar/` | Date and time entry over `tom_calendar_model`'s UTC storage, shown and read in the `CalendarTimeFrame` the host gives — the device's for a screen, UTC for an all-day date, whose day must not move (`TomDateField`, `TomTimeField`); the repeat control, which builds a rule of the interpreted recurrence subset, writes it back with `CalendarRecurrenceRule.format`, and shows a rule outside the subset read-only and kept exactly as written (`TomRecurrenceField`). |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_calendar_ui/tom_calendar_ui.dart` | the date, time and repeat fields and the appointment editor (`showTomAppointmentEditor`) | all |

## Dependencies

Flutter, `tom_calendar_model`.

## Tests

`flutter test` from this folder.
