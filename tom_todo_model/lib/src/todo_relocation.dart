/// Archive and delete as **relocation**: a todo moves to its file's
/// `-archived` or `-deleted` sibling, stamped with the date, and a completed
/// todo's decisions are copied to the quest's decisions journal.
///
/// This is the text half — which sibling, whether the move is allowed, and
/// what the three files read afterwards. Reading and writing them, in the
/// workspace tooling's order (target, journal, source), is the caller's.
library;

import 'yaml_lines.dart';

import 'decisions_journal.dart';
import 'todo.dart';
import 'todo_file.dart';
import 'todo_file_name.dart';

/// Which sibling a todo moves to.
enum TomTodoRelocationKind {
  archive('archived', 'Archive'),
  delete('deleted', 'Delete');

  const TomTodoRelocationKind(this.stamp, this.verb);

  /// The sibling suffix and the key stamped on the moved todo.
  final String stamp;
  final String verb;
}

/// The sibling of [fileName] for [kind]: the first dot-segment suffixed.
String tomTodoSiblingName(String fileName, TomTodoRelocationKind kind) {
  final dot = fileName.indexOf('.');
  return dot == -1
      ? '$fileName-${kind.stamp}'
      : '${fileName.substring(0, dot)}-${kind.stamp}'
            '${fileName.substring(dot)}';
}

/// Why todo [index] of [file] (named [fileName]) cannot be relocated by
/// [kind], or null when it can: a sibling file keeps its todos, only a
/// completed todo is archived, and a completed todo is not deleted.
String? tomTodoRelocationRefusal(
  TomTodoFile file,
  String fileName,
  int index,
  TomTodoRelocationKind kind,
) {
  final name = TomTodoFileName.parse(fileName);
  if (name != null && name.sibling != TomTodoFileSibling.live) {
    return 'This is an archived or deleted todo file; its todos stay here.';
  }
  final todo = file.entries[index].todo;
  final completed = todo?.status == TomTodoStatus.completed;
  return switch (kind) {
    TomTodoRelocationKind.archive when !completed =>
      'Only a completed todo is archived.',
    TomTodoRelocationKind.delete when completed =>
      'A completed todo is archived, not deleted.',
    _ => null,
  };
}

/// The decisions journal todo [index] of [source] is recorded in when it is
/// relocated by [kind], or null when nothing is: only an archived todo with
/// decisions, in a file whose quest is known.
String? tomTodoRelocationJournalName(
  TomTodoFile source,
  String fileName,
  int index,
  TomTodoRelocationKind kind,
) {
  final quest = _journalQuest(source, fileName, index, kind);
  return quest == null ? null : tomDecisionsJournalName(quest);
}

/// The quest whose journal records the move, or null when none does.
String? _journalQuest(
  TomTodoFile source,
  String fileName,
  int index,
  TomTodoRelocationKind kind,
) {
  final todo = source.entries[index].todo;
  if (kind != TomTodoRelocationKind.archive ||
      todo == null ||
      todo.decisions.isEmpty) {
    return null;
  }
  final quest = source.quest ?? TomTodoFileName.parse(fileName)?.quest;
  return quest == null || quest.isEmpty ? null : quest;
}

/// The three files after todo [index] of [source] moves by [kind] on [now].
///
/// [target] is the sibling's current text, or null when it does not exist
/// yet; [journal] the journal's, or null. The sibling is keyed by id, so a
/// re-run after an interruption replaces the todo there rather than adding it
/// twice. [journalText] is null when no journal entry is written.
({String targetText, String sourceText, String? journalText})
tomPlanTodoRelocation({
  required TomTodoFile source,
  required String fileName,
  required int index,
  required TomTodoRelocationKind kind,
  required DateTime now,
  String? target,
  String? journal,
}) {
  final refused = tomTodoRelocationRefusal(source, fileName, index, kind);
  if (refused != null) throw StateError(refused);
  final entry = source.entries[index];
  final date = TomTodo.encodeDate(now);
  final block = source.blockWith(index, kind.stamp, date);

  final String targetText;
  if (target == null) {
    targetText = _newSibling(source, date) + block;
  } else {
    var file = TomTodoFile.parse(target);
    final existing = file.entryFor(entry.id);
    var at = file.entries.length;
    if (existing != null) {
      at = existing.index;
      file = TomTodoFile.parse(file.withoutTodo(existing.index));
    }
    file = TomTodoFile.parse(file.withInsertedBlock(block, at: at));
    targetText = file.withFileKey('updated', date);
  }

  String? journalText;
  final quest = _journalQuest(source, fileName, index, kind);
  if (quest != null) {
    journalText =
        (journal ?? tomDecisionsJournalHeader(quest)) +
        tomDecisionJournalEntry(entry.todo!, now);
  }

  final sourceText = TomTodoFile.parse(
    source.withoutTodo(index),
  ).withFileKey('updated', date);
  return (
    targetText: targetText,
    sourceText: sourceText,
    journalText: journalText,
  );
}

/// A new sibling's header: the source's schema line, its quest, the date.
String _newSibling(TomTodoFile source, String date) {
  final nl = source.newline;
  final out = StringBuffer();
  final schema = source.schemaRef;
  if (schema != null) out.write('# yaml-language-server: \$schema=$schema$nl');
  if (source.quest != null) {
    out.write('quest: ${tomYamlScalar(source.quest!)}$nl');
  }
  out.write('created: ${tomYamlScalar(date)}$nl');
  out.write('updated: ${tomYamlScalar(date)}$nl');
  out.write('todos:$nl');
  return out.toString();
}
