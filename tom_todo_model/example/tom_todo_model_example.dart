// Parse a todo file, complete one item, give another a reminder, and write
// the file back as text in which only the edited keys changed.
import 'package:tom_todo_model/tom_todo_model.dart';

const _file = '''
quest: garden
todos:
  # the beds
  - id: gx1_ajka-plant
    title: Plant the beds
    status: not-started   # first
  - id: gx2_ajka-water
    title: Water the beds
    status: not-started
''';

void main() {
  final file = TomTodoFile.parse(_file);
  for (final item in file.items) {
    final types = item.types().map((t) => t.wire).join(', ');
    print('${item.id}: ${item.headline} (${item.status.wire}; $types)');
  }

  final entry = file.entryFor('gx1_ajka-plant')!;
  final done = entry.item!.copy()
    ..changeStatus(TomTodoStatus.completed, on: DateTime(2026, 10, 21));
  var text = file.withItem(entry.index, done);

  // Any item can ring: the new field is written because it is set.
  final reread = TomTodoFile.parse(text);
  final water = reread.entryFor('gx2_ajka-water')!;
  final ringing = water.item!.copyWith(
    reminders: [TomItemReminder(at: '2026-10-22T07:00+02:00')],
  );
  text = reread.withItem(water.index, ringing);
  print('---');
  print(text);
}
