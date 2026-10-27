# Tom Modules

Reusable components of the Tom workspace on a business level: shared models
and the code that reads, writes, serialises and changes them. They are not of
general interest the way `tom_basics` or `tom_core` are, but several Tom
applications use the same model, so it lives here once.

| Package | What it is |
| --- | --- |
| [`tom_todo_model`](tom_todo_model/) | The shared todo model (`TomTodo`) and the `*.todo.yaml` file codec. |
| [`tom_calendar_model`](tom_calendar_model/) | The calendar model: appointments timed in UTC or all-day, a recurrence subset with on-demand expansion, occurrence and series edits, display time frames, tasks, and an RFC 5545 codec. |
| [`tom_formula`](tom_formula/) | A spreadsheet formula engine: the grammar and printer, the function library, dependency-tracked recalculation, lowering to Dart, and the backend port, with a conformance corpus in `testing.dart`. |
| [`tom_file_session`](tom_file_session/) | The editing session of one file over `tom_file_system` (encoding, byte preservation, explicit save, external changes, undo), the file-tree filter with its presets, and the `.env` codec. |

Each package has its own README and changelog. `tom_todo_model` is published
on pub.dev; the others are consumed by path inside the workspace until they are
published.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
