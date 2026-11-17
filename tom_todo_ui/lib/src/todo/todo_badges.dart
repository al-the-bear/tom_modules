/// The facet badges a todo wears, on a row and on a board card.
///
/// One widget rather than two: the two surfaces show the *same* facets, and
/// two renderings of one fact drift — the board would gain a badge the row
/// never grew, and the user would learn each surface separately.
library;

import 'package:flutter/material.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

import 'package:tom_ui_support/tom_ui_support.dart';

/// The facet badges of one todo item — whose it is, priority, due, estimate,
/// tags, what it waits on and what waits on it. Renders nothing when the item
/// has none of them.
class TomTodoBadges extends StatelessWidget {
  const TomTodoBadges({
    super.key,
    required this.item,
  });

  final TomTodo item;

  /// Whether [status] wears a badge: every status the checkbox cannot
  /// express. `not-started` and `completed` are already visible as the
  /// checkbox state, so badging them would be a second, redundant channel.
  ///
  /// Exhaustive on purpose, so a status the shared model gains is a compile
  /// error here rather than a silently unbadged row.
  static bool _badgesStatus(TomTodoStatus status) => switch (status) {
    TomTodoStatus.notStarted || TomTodoStatus.completed => false,
    TomTodoStatus.inProgress ||
    TomTodoStatus.blocked ||
    TomTodoStatus.decisionNeeded ||
    TomTodoStatus.waitingForRepeat ||
    TomTodoStatus.cancelled ||
    // A group of todos is no work itself: the checkbox cannot say that.
    TomTodoStatus.group => true,
  };

  static Color _priorityColor(TomTodoPriority priority) =>
      switch (priority) {
        TomTodoPriority.low => Colors.blueGrey,
        TomTodoPriority.medium => Colors.blue,
        TomTodoPriority.high => Colors.orange,
        TomTodoPriority.critical => Colors.red,
      };

  /// Whether [item] wears any badge — what a row asks before giving the
  /// badges a line of their own.
  static bool hasAny(TomTodo item) => _badgesOf(item).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final badges = _badgesOf(item);
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 2, children: badges);
  }

  static List<Widget> _badgesOf(TomTodo item) => <Widget>[
      // The user's to do: an agent only prepares and reports, and a queue
      // walk passes it by (`user_action`). The VS Code extension marks it 👤;
      // the same mark here, so a todo reads the same in every host.
      if (item.userAction)
        Tooltip(
          key: Key('tom-todo-user-action-${item.id}'),
          message: 'Yours to do',
          child: const _Badge(text: '👤', color: Colors.purple),
        ),
      if (_badgesStatus(item.status))
        _Badge(text: item.status.wire, color: Colors.purple),
      if (item.priority != null)
        _Badge(text: item.priority!.wire, color: _priorityColor(item.priority!)),
      if (item.due != null)
        _Badge(
          text: TomTodo.encodeDate(item.due!),
          color: Colors.teal,
          icon: Icons.event,
        ),
      if (item.estimate != null)
        _Badge(
          text: item.estimate!,
          color: Colors.indigo,
          icon: Icons.timer_outlined,
        ),
      for (final tag in item.tags) _Badge(text: '#$tag', color: Colors.grey),
      // What the row does not show: that there is more to read (a
      // description) and what the todo waits on (its dependencies). Shown on
      // the row and on a board card alike, so the details are discoverable
      // without opening every todo.
      if (item.hasBlocker)
        Tooltip(
          key: Key('tom-todo-has-blockers-${item.id}'),
          message: [
            if (item.blockedBy.isNotEmpty)
              'Blocked by ${item.blockedBy.length} '
                  '${item.blockedBy.length == 1 ? 'todo' : 'todos'}',
            for (final condition in item.blockedUntil) 'Until $condition',
          ].join('\n'),
          child: _Badge(
            text: '${item.blockedBy.length + item.blockedUntil.length}',
            color: Colors.red,
            icon: Icons.block,
          ),
        ),
      if (item.hasOpenDecision)
        Tooltip(
          key: Key('tom-todo-has-open-decisions-${item.id}'),
          message: [
            for (final d in item.decisions)
              if (d.isOpen) d.summary,
          ].join('\n'),
          child: _Badge(
            text: '${item.decisions.where((d) => d.isOpen).length}',
            color: Colors.purple,
            icon: Icons.help_outline,
          ),
        ),
      if ((item.description ?? '').trim().isNotEmpty ||
          (item.notes ?? '').trim().isNotEmpty)
        Tooltip(
          key: Key('tom-todo-has-description-${item.id}'),
          message: 'Has a description or notes',
          child: const _Badge(
            text: 'notes',
            color: Colors.brown,
            icon: Icons.notes,
          ),
        ),
      // What waits on this one: `blocking`, the reverse of the others'
      // `blocked_by`, kept in step by the todo writers. ⛓️ as in the
      // extension.
      if (item.blocking.isNotEmpty)
        Tooltip(
          key: Key('tom-todo-blocks-${item.id}'),
          message: [
            'Blocks ${item.blocking.length} '
                '${item.blocking.length == 1 ? 'todo' : 'todos'}:',
            ...item.blocking,
          ].join('\n'),
          child: _Badge(
            text: '⛓️ ${item.blocking.length}',
            color: Colors.deepPurple,
          ),
        ),
      if (item.dependencies.isNotEmpty)
        Tooltip(
          key: Key('tom-todo-has-dependencies-${item.id}'),
          message: 'Depends on ${item.dependencies.length} '
              '${item.dependencies.length == 1 ? 'todo' : 'todos'}',
          child: _Badge(
            text: '${item.dependencies.length}',
            color: Colors.deepOrange,
            icon: Icons.link,
          ),
        ),
    ];
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // The hue names the facet; its lightness is moved until the text reads on
    // the chip, in either theme (wonetestb4).
    final chip =
        tomTintedChip(color, Theme.of(context).colorScheme.surface);
    return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: chip.background,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: chip.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: chip.foreground),
          const SizedBox(width: 3),
        ],
        // Flexible, because a `Wrap` wraps *between* badges, never
        // inside one: a single badge wider than the line — a long tag at
        // double text scale on a 238 px card — overflowed (woneqrc7).
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: chip.foreground),
          ),
        ),
      ],
    ),
  );
  }
}
