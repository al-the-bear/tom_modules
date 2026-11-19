/// Severity levels for validation errors.
enum ValidationSeverity {
  /// A hard error — the document is structurally invalid.
  error,

  /// A warning — the document is technically valid but has issues.
  warning,

  /// An informational hint — suggestions or documentation.
  info,
}

/// A single validation error with path, message, and severity.
///
/// Used by the validation framework to report schema violations in
/// tree-based editors. The [path] identifies the exact node, enabling
/// error badges, tooltips, and click-to-navigate behavior.
///
/// ```dart
/// final error = ValidationError(
///   path: ['prompt', 'meta-data', 'id'],
///   message: 'Expected type "string", got "integer"',
///   severity: ValidationSeverity.error,
///   code: 'type_mismatch',
/// );
/// ```
class ValidationError {
  /// The path to the node that has the error.
  ///
  /// Each element is a key (for maps) or index (for lists).
  final List<Object> path;

  /// Human-readable error message.
  final String message;

  /// Severity of this error.
  final ValidationSeverity severity;

  /// Optional machine-readable error code (e.g., "type_mismatch").
  final String? code;

  const ValidationError({
    required this.path,
    required this.message,
    this.severity = ValidationSeverity.error,
    this.code,
  });

  /// The path formatted as a breadcrumb string (e.g., "prompt > meta-data > id").
  String get pathString => path.map((e) => e.toString()).join(' > ');

  @override
  String toString() =>
      '${severity.name}: $pathString — $message${code != null ? ' [$code]' : ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationError &&
          runtimeType == other.runtimeType &&
          _listEquals(path, other.path) &&
          message == other.message &&
          severity == other.severity &&
          code == other.code;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(path),
        message,
        severity,
        code,
      );

  static bool _listEquals(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
