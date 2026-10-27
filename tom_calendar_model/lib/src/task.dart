/// A task as iCalendar carries it — a `VTODO`.
library;

/// The RFC 5545 `STATUS` of a `VTODO`.
enum CalendarTaskStatus {
  /// `NEEDS-ACTION`: work has not started.
  needsAction('NEEDS-ACTION'),

  /// `IN-PROCESS`.
  inProcess('IN-PROCESS'),

  /// `COMPLETED`.
  completed('COMPLETED'),

  /// `CANCELLED`.
  cancelled('CANCELLED');

  const CalendarTaskStatus(this.wire);

  /// The value as RFC 5545 writes it.
  final String wire;

  /// The status [wire] names, or null for one RFC 5545 does not define.
  static CalendarTaskStatus? fromWire(String wire) {
    for (final status in values) {
      if (status.wire == wire.toUpperCase()) return status;
    }
    return null;
  }
}

/// One task: the fields a `VTODO` carries, plus the producer's own facets the
/// codec writes as extension properties.
///
/// A value: two tasks are equal when every field is.
final class CalendarTask {
  /// The `UID`.
  final String id;

  /// The `SUMMARY`.
  final String title;

  final String? description;

  final CalendarTaskStatus status;

  /// The RFC 5545 §3.8.1.9 priority: 1 (highest) to 9 (lowest), or null for
  /// "undefined" (0 on the wire).
  final int? priority;

  /// The due **date**, as UTC midnight. A timed `DUE` keeps only its date.
  final DateTime? due;

  /// How long the task is expected to take, as the producer writes it.
  final String? estimate;

  final List<String> tags;

  /// The ids of the tasks this one waits for.
  final List<String> dependencies;

  /// The producer's other facets — anything RFC 5545 has no property for —
  /// carried as one JSON object so an export of its own tasks stays lossless.
  /// The codec does not look inside.
  final Map<String, Object?>? fields;

  CalendarTask({
    required this.id,
    required this.title,
    this.description,
    this.status = CalendarTaskStatus.needsAction,
    this.priority,
    DateTime? due,
    this.estimate,
    List<String> tags = const [],
    List<String> dependencies = const [],
    this.fields,
  }) : due = due == null ? null : DateTime.utc(due.year, due.month, due.day),
       tags = List.unmodifiable(tags),
       dependencies = List.unmodifiable(dependencies) {
    final p = priority;
    if (p != null && (p < 1 || p > 9)) {
      throw ArgumentError.value(p, 'priority', 'is 1 to 9, or null');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarTask &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.status == status &&
      other.priority == priority &&
      other.due == due &&
      other.estimate == estimate &&
      _sameList(other.tags, tags) &&
      _sameList(other.dependencies, dependencies) &&
      _sameJson(other.fields, fields);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    status,
    priority,
    due,
    estimate,
    Object.hashAll(tags),
    Object.hashAll(dependencies),
  );

  @override
  String toString() => 'CalendarTask($id "$title" ${status.wire})';

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_sameJson(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameJson(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
