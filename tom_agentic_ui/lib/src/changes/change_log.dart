import 'package:flutter/foundation.dart';

import 'change_entry.dart';

/// A run of [ChangeEntry]s that belong to the same agent turn (§9).
///
/// The change log is grouped by turn so the panel can collapse a multi-edit
/// agent turn into one expandable header while keeping each individual change
/// inspectable underneath.
class ChangeGroup {
  /// The turn id shared by every entry in [entries].
  final String turnId;

  /// The entries of this turn, in record order (oldest first within the turn).
  final List<ChangeEntry> entries;

  ChangeGroup({required this.turnId, required this.entries});

  /// The first (earliest) entry's timestamp — used to order groups.
  DateTime get startedAt => entries.first.timestamp;
}

/// The agent change log (§9): an append-only record of mutations that **resets
/// on save** (M2, N6).
///
/// It owns no document state — it only records [ChangeEntry]s the controller
/// hands it as mutations land. The log is grouped by agent turn for display
/// (newest turn first) and is *not* serialized with the document; once the
/// document is saved the accrued changes are cleared and the saved state
/// becomes the new base.
class ChangeLog extends ChangeNotifier {
  final List<ChangeEntry> _entries = [];

  /// All entries in record order (oldest first).
  List<ChangeEntry> get entries => List.unmodifiable(_entries);

  /// All entries newest first — the panel's default ordering (§9).
  List<ChangeEntry> get entriesNewestFirst => _entries.reversed.toList();

  /// Whether any changes have been recorded since the last [reset].
  bool get isEmpty => _entries.isEmpty;

  /// The number of recorded entries.
  int get length => _entries.length;

  /// Entries grouped by agent turn, **newest turn first**; within a turn the
  /// entries keep record order (oldest first) so the change sequence reads
  /// naturally top-to-bottom inside the group.
  List<ChangeGroup> get groups {
    final order = <String>[];
    final byTurn = <String, List<ChangeEntry>>{};
    for (final e in _entries) {
      final list = byTurn.putIfAbsent(e.turnId, () {
        order.add(e.turnId);
        return [];
      });
      list.add(e);
    }
    return [
      for (final turnId in order.reversed)
        ChangeGroup(turnId: turnId, entries: byTurn[turnId]!),
    ];
  }

  /// Appends [entry] and notifies listeners.
  void record(ChangeEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  /// Clears the log (called on save, M2/N6). The saved document state becomes
  /// the new base, so the accrued change history no longer applies.
  void reset() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// The entry with [id], or `null`.
  ChangeEntry? byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}
