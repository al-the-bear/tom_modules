/// What the three-way merge view shows: rows, their sides, and a decision.
library;

/// What the user has decided for one conflicted item.
///
/// A resolution can be a **deletion** — the side they picked deleted the
/// thing — which is why this is a wrapper and not a nullable value: `null`
/// would be indistinguishable from "not decided yet", and confirming a
/// decision nobody made is how content disappears.
class TomMergeResolution {
  /// The chosen version, or null to delete it.
  final Object? value;

  /// Which side it came from, for the label; null once hand-edited.
  final String? source;

  const TomMergeResolution({required this.value, this.source});

  bool get deletes => value == null;
}

/// One version of a conflicted item.
class TomMergeSide {
  /// The pane label: `base`, `ours`, `theirs`, or whatever the row calls it.
  final String label;

  /// The version, or null when this side deleted it.
  final Object? value;

  /// What to say when [value] is null for a reason other than a deletion.
  ///
  /// A null side reads as "deleted on this side" by default. A side whose
  /// content is **unreachable** — retained somewhere that no longer holds it —
  /// is a different fact calling for the opposite decision, and the view
  /// shows the reason instead and offers no button for it.
  final String? absentBecause;

  const TomMergeSide(this.label, this.value, {this.absentBecause});

  /// Whether this side cannot be shown, as distinct from having deleted.
  bool get unreachable => value == null && absentBecause != null;
}

/// One conflict as the view renders it.
///
/// The view knows nothing about what is conflicted: a row names its renderer
/// ([kind]), what the list shows, the sides on offer and the decision it
/// starts on. Adding a kind of conflict means adding a row and a renderer,
/// never touching the list, the selection or the decision bar.
abstract class TomMergeRow {
  const TomMergeRow();

  /// Which renderer of a [TomMergeRendererRegistry] draws this row's versions.
  String get kind;

  /// The container the conflict is in, shown beside the headline.
  String get locator;

  /// Identifies the row across rebuilds and keys its pending decision.
  String get key;

  String get headline;
  String get subtitle;

  /// The versions on offer, in display order. A missing side is simply
  /// absent: the two-pane degradation is this list being shorter.
  List<TomMergeSide> get sides;

  /// The decision this row starts on.
  TomMergeResolution get seed;

  /// Whether the result pane may be edited by hand.
  bool get resultEditable => false;

  /// Whether every side can be shown, so there is something to compare.
  bool get comparable => sides.every((side) => !side.unreachable);

  /// The value the decision takes when the user picks [side] — a copy when
  /// the result is editable, so typing into it cannot write through to the
  /// side the row still renders.
  Object? take(TomMergeSide side) => side.value;

  /// Joins key segments with a NUL, a separator no user-written text holds,
  /// so two different conflicts cannot produce one key.
  static String joinKey(List<String> parts) => parts.join('\u0000');
}
