/// The shared todo model and the `*.todo.yaml` file codec.
///
/// One model — the workspace todo schema's field set, its six statuses and
/// four priorities — and one way of editing a todo file: as splices into its
/// own text, so every byte an edit does not touch stays as it was. With the
/// date-code ids, the archived and deleted siblings and the decisions journal
/// the workspace's tooling writes.
///
/// Reaches no `dart:io` and no Flutter, so an application of any kind — a
/// browser build included — can take it. Reading and writing the files is the
/// application's: this package works on their text.
library;

export 'src/decisions_journal.dart';
export 'src/todo.dart';
export 'src/todo_file.dart';
export 'src/todo_file_name.dart';
export 'src/todo_ids.dart';
export 'src/todo_relocation.dart';
