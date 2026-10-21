/// The decisions journal, `decisions.<quest>.md`, in the format the
/// workspace's tooling writes.
///
/// Archiving a completed todo copies its decisions here, so the reasoning
/// outlives the todo. The shape — heading, numbered summaries, the
/// **Needed:** and **Decided:** bullets, the five-space continuation, the
/// preamble — is the one the VS Code extension writes and its Logs viewer
/// reads, reproduced line for line: a journal two writers append to in two
/// formats is a journal no reader can trust.
library;

import 'todo.dart';

const String _continuation = '     ';

/// The journal's file name for [quest].
String tomDecisionsJournalName(String quest) => 'decisions.$quest.md';

/// An ISO-8601 UTC stamp with milliseconds, as JavaScript's `toISOString`
/// writes it — never microseconds, which Dart would add.
String tomDecisionsJournalStamp(DateTime when) {
  final u = when.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}'
      '.${u.millisecond.toString().padLeft(3, '0')}Z';
}

String _inline(String text) =>
    text.replaceAll('\r\n', '\n').trim().split('\n').join('\n$_continuation');

/// One journal entry for [todo], ending in one newline, or `''` when it has
/// no decisions.
String tomDecisionJournalEntry(TomTodo todo, DateTime archivedAt) {
  if (todo.decisions.isEmpty) return '';
  final title =
      (todo.title.trim().isNotEmpty ? todo.title : (todo.description ?? ''))
          .trim();
  final heading = title.isEmpty ? '`${todo.id}`' : '`${todo.id}` — $title';
  final lines = ['## ${tomDecisionsJournalStamp(archivedAt)} — $heading', ''];
  for (var i = 0; i < todo.decisions.length; i++) {
    final d = todo.decisions[i];
    lines.add('${i + 1}. **${d.summary}**');
    if (d.decisionNeeded.trim().isNotEmpty) {
      lines.add('   - **Needed:** ${_inline(d.decisionNeeded)}');
    }
    lines.add(
      d.decision != null && d.decision!.trim().isNotEmpty
          ? '   - **Decided:** ${_inline(d.decision!)}'
          : '   - **Decided:** _(not decided)_',
    );
  }
  lines.add('');
  return lines.join('\n');
}

/// The preamble a new journal starts with.
String tomDecisionsJournalHeader(String quest) => [
  '# Decisions — $quest',
  '',
  'What was decided on the todos of this quest, copied here when each todo',
  'was archived so the reasoning outlives the todo. Only todos that reached',
  '`completed` are recorded — one archived half-done was abandoned, not',
  'concluded. Entries that say _(not decided)_ were archived with the',
  'question still open.',
  'Appended to: the newest entry is at the bottom.',
  '',
  '',
].join('\n');
