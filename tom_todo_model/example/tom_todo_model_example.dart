// Parse a todo file, complete one todo, and write the file back as text in
// which only that todo's edited keys changed.
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
  for (final todo in file.todos) {
    print('${todo.id}: ${todo.title} (${todo.status.wire})');
  }

  final entry = file.entryFor('gx1_ajka-plant')!;
  final done = entry.todo!.copy()
    ..status = TomTodoStatus.completed
    ..completedDate = DateTime(2026, 10, 21);
  final edited = file.withTodo(entry.index, done);
  print('---');
  print(edited);
}
