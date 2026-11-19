import 'validation_error.dart';

/// Propagates validation errors upward through a path hierarchy.
///
/// Given a list of validation errors at leaf positions, the propagator
/// generates synthetic "descendant has error" entries for every ancestor
/// path. This allows collapsed tree nodes to show error indicators even
/// when the actual problem is deeply nested.
///
/// ```dart
/// final errors = [
///   ValidationError(path: ['a', 'b', 'c'], message: 'bad value'),
/// ];
/// final propagated = ErrorPropagator.propagate(errors);
/// // propagated keys: 'a > b > c', 'a > b', 'a', ''
/// ```
class ErrorPropagator {
  const ErrorPropagator._();

  /// Propagate errors to all ancestor paths.
  ///
  /// Returns a map keyed by path hash (joined with '>') to all errors
  /// that are at or beneath that path. The empty string key `''` represents
  /// the root.
  static Map<String, List<ValidationError>> propagate(
    List<ValidationError> errors,
  ) {
    final result = <String, List<ValidationError>>{};

    for (var error in errors) {
      // Add the error at its own path
      var key = _pathKey(error.path);
      result.putIfAbsent(key, () => []).add(error);

      // Add to every ancestor path
      for (var i = error.path.length - 1; i >= 0; i--) {
        var ancestorKey = _pathKey(error.path.sublist(0, i));
        result.putIfAbsent(ancestorKey, () => []).add(error);
      }
    }

    return result;
  }

  /// Get a summary for a specific path: how many errors and warnings
  /// exist at or below that path.
  static ({int errors, int warnings}) countAt(
    Map<String, List<ValidationError>> propagated,
    List<Object> path,
  ) {
    var key = _pathKey(path);
    var list = propagated[key];
    if (list == null || list.isEmpty) return (errors: 0, warnings: 0);

    var errorCount = 0;
    var warningCount = 0;
    for (var e in list) {
      if (e.severity == ValidationSeverity.error) {
        errorCount++;
      } else if (e.severity == ValidationSeverity.warning) {
        warningCount++;
      }
    }
    return (errors: errorCount, warnings: warningCount);
  }

  /// Get direct errors at a specific path (not propagated from descendants).
  static List<ValidationError> directErrorsAt(
    List<ValidationError> allErrors,
    List<Object> path,
  ) {
    var key = _pathKey(path);
    return allErrors.where((e) => _pathKey(e.path) == key).toList();
  }

  static String _pathKey(List<Object> path) =>
      path.map((e) => e.toString()).join('>');
}
