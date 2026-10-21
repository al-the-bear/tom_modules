/// What a todo file's name says: its family (a quest's todo file, a session
/// todo file, any other), whether it is the live file or its archived or
/// deleted sibling, and its quest.
library;

/// Which family a todo file belongs to.
enum TomTodoFileFamily {
  /// `todos<sibling>.<quest>.todo.yaml`.
  quest,

  /// `session-todo<sibling>.<host>.<quest>.todo.yaml`.
  session,

  /// Any other `*.todo.yaml` — a document-processing todo file, say.
  other,
}

/// A todo file's place among its siblings.
enum TomTodoFileSibling { live, archived, deleted }

/// A todo file's family, sibling state and quest, read off its name.
class TomTodoFileName {
  final TomTodoFileFamily family;
  final TomTodoFileSibling sibling;

  /// The `<quest>` segment, or null for [TomTodoFileFamily.other].
  final String? quest;

  /// The `<host>` segment of a session todo file, or null.
  final String? host;

  const TomTodoFileName({
    required this.family,
    required this.sibling,
    this.quest,
    this.host,
  });

  /// Parses [name], or answers null when it is not `*.todo.yaml`.
  ///
  /// The sibling suffix sits at the end of the **first dot-segment**, as the
  /// workspace's tooling writes it: `todos-archived.q.todo.yaml`,
  /// `session-todo-deleted.host.q.todo.yaml`.
  static TomTodoFileName? parse(String name) {
    const suffix = '.todo.yaml';
    if (!name.endsWith(suffix) || name.length == suffix.length) return null;
    final segments = name.substring(0, name.length - suffix.length).split('.');
    var first = segments.first;
    var sibling = TomTodoFileSibling.live;
    for (final (tail, state) in const [
      ('-archived', TomTodoFileSibling.archived),
      ('-deleted', TomTodoFileSibling.deleted),
    ]) {
      if (first.endsWith(tail)) {
        first = first.substring(0, first.length - tail.length);
        sibling = state;
      }
    }
    if (first == 'todos' && segments.length == 2) {
      return TomTodoFileName(
        family: TomTodoFileFamily.quest,
        sibling: sibling,
        quest: segments[1],
      );
    }
    if (first == 'session-todo' && segments.length == 3) {
      return TomTodoFileName(
        family: TomTodoFileFamily.session,
        sibling: sibling,
        host: segments[1],
        quest: segments[2],
      );
    }
    return TomTodoFileName(family: TomTodoFileFamily.other, sibling: sibling);
  }
}
