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
