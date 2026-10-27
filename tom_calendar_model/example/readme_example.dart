// The README example, compiled: a weekly series, its occurrences, one of them
// cancelled, the times said in words, and an iCalendar round trip carrying a
// task beside the event.
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
