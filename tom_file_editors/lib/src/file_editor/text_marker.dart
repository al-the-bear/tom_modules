/// Markers on a range of a source's text — a parse error, a schema finding,
/// a hint — drawn by [TomTextSource] as a wavy underline in the colour of
/// their severity.
///
/// The markers are neutral: an editor maps its own findings (a YAML parse
/// error, a schema validation result) onto them.
library;

import 'package:flutter/painting.dart';

/// How serious a [TomTextMarker] is: it decides the underline's colour.
enum TomTextMarkerSeverity {
  /// A red underline.
  error,

  /// A yellow underline.
  warning,

  /// A blue underline.
  info,
}

/// A marker on the text from [start] (inclusive) to [end] (exclusive), with
/// the [message] that says why.
class TomTextMarker {
  const TomTextMarker({
    required this.start,
    required this.end,
    required this.message,
    this.severity = TomTextMarkerSeverity.error,
    this.line,
    this.column,
  });

  /// Offset of the first marked character (inclusive).
  final int start;

  /// Offset past the last marked character (exclusive).
  final int end;

  /// What the marker says.
  final String message;

  /// How serious it is.
  final TomTextMarkerSeverity severity;

  /// The 1-based line the marker starts on, when the producer knows it.
  final int? line;

  /// The 1-based column the marker starts at, when the producer knows it.
  final int? column;

  /// The underline's colour for [severity].
  Color get color => tomTextMarkerColor(severity);

  @override
  bool operator ==(Object other) =>
      other is TomTextMarker &&
      other.start == start &&
      other.end == end &&
      other.message == message &&
      other.severity == severity &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(start, end, message, severity, line, column);

  @override
  String toString() =>
      'TomTextMarker(${severity.name} $start..$end${line == null ? '' : ' at $line:$column'}: $message)';
}

/// The underline colour of a marker of [severity].
Color tomTextMarkerColor(TomTextMarkerSeverity severity) => switch (severity) {
  TomTextMarkerSeverity.error => const Color(0xFFF44747),
  TomTextMarkerSeverity.warning => const Color(0xFFCCA700),
  TomTextMarkerSeverity.info => const Color(0xFF569CD6),
};
