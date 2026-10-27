## 1.1.0

- `TomTodo.userAction` — the schema's new `user_action` field: the todo is the
  user's to do (looking at something, answering, deciding by hand), so an
  agent only prepares and reports and a `<prefix>*` queue walk passes it by.
  Written as `user_action: true` only when set; a value that is not a boolean
  is a format error. An older reader (1.0.x) refuses a todo carrying the field
  as an unknown key and reports it, leaving the rest of its file readable:
  upgrade every package that reads todo files before marking todos.

## 1.0.1

- No longer depends on `tom_basics`. The YAML line writers the codec uses
  (`yaml_lines.dart`, from `tom_basics` 3.3.0) are carried as a private copy,
  so the model fits a dependency graph that takes `tom_basics` by path as well
  as one that takes it from pub.dev. A test in the package holds the copy to
  the original while both are in one workspace. Once `tom_basics` is taken from
  pub.dev throughout, the copy goes and the dependency returns.

## 1.0.0

- First release. The shared todo model and the `*.todo.yaml` codec, moved out
  of Worktracker (`tom_worktracker_core`, where they were the `todo.dart`
  entry point) so that every application that reads or writes a todo — the VS
  Code scripting API, Webwork, Forge and Worktracker itself — uses one model:
  - `TomTodo` with `TomTodoStatus`, `TomTodoPriority`, `TomTodoScope`,
    `TomTodoDecision` and `TomTodoReference`: the workspace todo schema's field
    set, including `due`, `estimate`, `blocked_until`, `archived` / `deleted`
    and the orchestration fields.
  - `TomTodoFile`: parses a todo file and edits it as splices into its own text
    (`withTodo`, `withInserted`, `withoutTodo`, `withMoved`, `withFileKey`), so
    every byte an edit does not touch stays as it was; an item the model
    refuses is kept and reported, never rewritten.
  - The file names (`TomTodoFileName`: the `-archived` / `-deleted` siblings),
    the date-coded ids, relocation between files, and the decisions journal.
