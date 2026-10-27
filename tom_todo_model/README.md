# Tom Todo Model

The shared todo model of the Tom workspace and the codec for its `*.todo.yaml`
files.

- **`TomTodo`** — one todo with the workspace todo schema's field set: `id`,
  `title`, `description`, `status` (`not-started`, `in-progress`, `blocked`,
  `decision-needed`, `completed`, `cancelled`), `priority`, `due`, `estimate`,
  `tags`, `scope`, `decisions`, `references`, `dependencies`, `blocked_by`,
  `blocked_until`, `user_action` (the todo is the user's to do), `notes`, the dates (`created`, `updated`, `completed_date`,
  `archived`, `deleted`, always `YYYY-MM-DD` — a `DateTime` stands for the
  calendar day its own fields name, local or UTC) and the orchestration fields
  (`execution_role`, `qa_role`, `orchestration_role`, `bundle_id`,
  `derived_from`, `feedback_source`). `TomTodo.fromMap` is the wire boundary:
  it refuses a value the schema does not allow, with the reason.
- **`TomTodoFile`** — parses a todo file and edits it **as splices into its
  own text**: changing one todo rewrites only the keys that changed, so the
  rest of the file — other todos, comments between and around todos, key order,
  block scalars, keys this model does not know — stays byte for byte. (A key
  that is rewritten is written fresh, together with any comment on its line.)
  An item the model refuses is listed with its reason and is never rewritten.
- **File names, ids, relocation, decisions** — `TomTodoFileName` (a todo
  file's `-archived` and `-deleted` siblings), the date-coded ids
  (`<base>_<date code>-<what>`), moving a todo between files, and the
  decisions journal an archived todo's decisions are copied into.

The package reaches no `dart:io` and no Flutter: it works on the text of a
file, and reading and writing the file is the application's. A browser build
can use it.

## Example

```dart
import 'package:tom_todo_model/tom_todo_model.dart';

void main() {
  final file = TomTodoFile.parse('''
quest: garden
todos:
  # the beds
  - id: gx1_ajka-plant
    title: Plant the beds
    status: not-started   # first
''');
  final entry = file.entryFor('gx1_ajka-plant')!;
  final done = entry.todo!.copy()
    ..status = TomTodoStatus.completed
    ..completedDate = DateTime(2026, 10, 21);
  // Only the edited keys are rewritten; `# the beds` and the other todo stay.
  print(file.withTodo(entry.index, done));
}
```

See `example/tom_todo_model_example.dart` for a runnable version.

## Where it is used

The VS Code extension's scripting API (`tom_vscode_scripting_api`), Webwork,
Forge and Worktracker read and write todos through this one model. The schema
it follows is the workspace's `todo.schema.json`.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
