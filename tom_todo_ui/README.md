# tom_todo_ui

Todo widgets over tom_todo_model: the todo row, its badges and the details
editor, and the editor of a *.todo.yaml file with validation, archive and
delete, and the aggregate over a folder's todo files.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Todo widgets | `lib/src/todo/` | One todo over `tom_todo_model`'s shared model: the row (`TomTodoRow` — checkbox, title, badges, row menu; **controlled**, it owns no state and reports every change, so one host writes a document body and another a store), the facet badges a row and a board card both wear (`TomTodoBadges`), and the details editor that edits a copy and returns it (`showTomTodoDetails`, with `TomTodoCandidate` for the dependency picker and `tomCopyTodoDetails`). |
| Todo-file editor | `lib/src/todo_file/` | A `*.todo.yaml` file as a list of todo rows (`TomTodoFileEditor`) over a host (`TomTodoFileEditorHost`, a `TomFileEditorHost` adding the schema cache, the validator, the relocator, a clock, the author, a todo to select and save): the file read into `tom_todo_model`'s model and written back as splices of the changed keys (`TomTodoFileController`), the header's file-level keys, filters, drag to reorder, add with a date-code id and the stem-reuse warning, the details editor, validation against the schema the file names with each problem at its todo (`TomTodoFileValidator`), archive and delete as one undoable move to the `-archived` / `-deleted` sibling with the decisions journal (`TomTodoRelocator`), and the file's source (`TomTodoFileSource`, the source editor over the session). Three views are the host's to offer: a board (`board`), every todo file under a root (`aggregate`, a `TomTodoAggregateSource` drawn by `TomTodoAggregateView`, found by `tomScanTodoFiles`), and moving and copying todos to other places (`transfer`, a `TomTodoFileTransfer`); a host that supplies none gets the list and the source. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_todo_ui/tom_todo_ui.dart` | everything above | all |

## Dependencies

Flutter, `path`, `tom_basics`, `tom_file_editors`, `tom_file_session`, `tom_file_system`, `tom_todo_model`, `tom_ui_support`.

## Tests

`flutter test` from this folder.
