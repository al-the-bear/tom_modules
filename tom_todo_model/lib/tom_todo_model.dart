/// The item model and the `*.todo.yaml` file codec.
///
/// One record for whatever can have a status, a reminder or a repetition —
/// [TomItem], with its item types and extensions — and one way of editing a
/// todo file: as splices into its own text, so every byte an edit does not
/// touch stays as it was. With the date-code ids, the archived and deleted
/// siblings and the decisions journal the workspace's tooling writes.
///
/// Reaches no `dart:io` and no Flutter, so an application of any kind — a
/// browser build included — can take it. Reading and writing the files is the
/// application's: this package works on their text.
library;

export 'src/decisions_journal.dart';
export 'src/item.dart';
export 'src/item_store.dart';
export 'src/mail_store.dart';
export 'src/todo.dart';
export 'src/todo_file.dart';
export 'src/todo_file_store.dart';
export 'src/todo_file_name.dart';
export 'src/todo_ids.dart';
export 'src/todo_relocation.dart';
export 'src/todo_repeat.dart';
