/// The kind of mutation a [ChangeEntry] records (§9).
///
/// These mirror the mutation tools exposed to the agent (§8): scalar/content
/// edits, `@Form` field edits, list growth/shrink, and structural-review
/// decisions. The kind drives how a [ReviewPane] pick is re-applied.
enum ChangeKind {
  /// A `content`/`scalar` leaf value was set.
  content,

  /// A single `@Form` field value was set (carries [ChangeEntry.field]).
  formField,

  /// A list item was appended.
  listAdd,

  /// A list item was removed.
  listRemove,

  /// A structural-review decision was applied.
  review,
}

/// Which pane of the three-way review (§9) a value is taken from.
///
/// The review is a *pick-a-pane* choice (M1): the user selects exactly one of
/// these as the section's new value; it is not a field-level merge.
enum ReviewPane {
  /// The section content at the last save (`baseAtLastSave`).
  base,

  /// The value produced by *this* edit (`afterThisEdit`).
  thisEdit,

  /// The live current value (may include later edits on top of this one).
  current,
}

/// A single recorded mutation, appended on every agent mutation tool call (§9).
///
/// Entries are immutable snapshots of one edit. They capture three reference
/// points so the three-way review can show *base* (at last save), *this edit*
/// (before→after), and *current* (live) side by side:
///   * [baseAtLastSave] — the value when the document was last saved (or
///     loaded). This is the review's pane 1.
///   * [beforeThisEdit] / [afterThisEdit] — the value immediately before and
///     after this specific change. [afterThisEdit] is the review's pane 2.
///
/// The live "current" pane is *not* stored on the entry — it is read back from
/// the document at review time, since later edits may have changed it.
class ChangeEntry {
  /// Stable, document-unique id for this entry.
  final String id;

  /// The section-ID path the change applies to (D3).
  final String sectionId;

  /// What kind of mutation this entry records.
  final ChangeKind kind;

  /// For [ChangeKind.formField], the form field name; otherwise `null`.
  final String? field;

  /// The value at [sectionId] immediately before this edit (`null` if unset).
  final String? beforeThisEdit;

  /// The value at [sectionId] immediately after this edit (`null` if cleared).
  final String? afterThisEdit;

  /// The value at [sectionId] as of the last save — the review's "base" pane.
  final String? baseAtLastSave;

  /// When the change was recorded.
  final DateTime timestamp;

  /// The agent turn this change belongs to (groups the change log, §9).
  final String turnId;

  /// The originating tool call id, when the change came from an agent tool.
  final String? toolCallId;

  ChangeEntry({
    required this.id,
    required this.sectionId,
    required this.kind,
    required this.turnId,
    this.field,
    this.beforeThisEdit,
    this.afterThisEdit,
    this.baseAtLastSave,
    this.toolCallId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// The value carried by [pane] for this entry.
  ///
  /// [current] is supplied by the caller because the live value is read from
  /// the document at review time (it is not stored on the entry).
  String? valueForPane(ReviewPane pane, {String? current}) {
    switch (pane) {
      case ReviewPane.base:
        return baseAtLastSave;
      case ReviewPane.thisEdit:
        return afterThisEdit;
      case ReviewPane.current:
        return current;
    }
  }

  /// A one-line human summary for the change-log row.
  String get summary {
    switch (kind) {
      case ChangeKind.content:
        return 'Set content';
      case ChangeKind.formField:
        return 'Set field ${field ?? ''}'.trimRight();
      case ChangeKind.listAdd:
        return 'Add list item';
      case ChangeKind.listRemove:
        return 'Remove list item';
      case ChangeKind.review:
        return 'Review decision';
    }
  }
}
