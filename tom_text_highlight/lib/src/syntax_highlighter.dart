import 'package:flutter/painting.dart';

/// A span of highlighted text in a source document.
class HighlightSpan {
  /// Offset of the first character (inclusive).
  final int start;

  /// Offset past the last character (exclusive).
  final int end;

  /// The style to apply to this span.
  final TextStyle style;

  /// Optional semantic type label (e.g., "key", "string", "comment").
  final String? type;

  const HighlightSpan({
    required this.start,
    required this.end,
    required this.style,
    this.type,
  });

  @override
  String toString() => 'HighlightSpan($start, $end, $type)';
}

/// Abstract interface for syntax highlighting engines.
///
/// Implementations process source text and return a list of [HighlightSpan]s
/// indicating how each region should be styled. Spans may overlap; a source
/// view applies them in order, with later spans overriding earlier ones
/// (`highlightedInlineSpans` does the same).
///
/// ```dart
/// class MyHighlighter extends SyntaxHighlighter {
///   @override
///   List<HighlightSpan> highlight(String source) {
///     // tokenize and return spans
///   }
/// }
/// ```
abstract class SyntaxHighlighter {
  /// Compute highlight spans for the given [source] text.
  List<HighlightSpan> highlight(String source);

  /// Optional: incrementally update highlights when text changes.
  ///
  /// Default implementation calls [highlight] on the full text.
  /// Subclasses may override for incremental parsing.
  List<HighlightSpan> updateHighlights(
    String source, {
    required int changeStart,
    required int changeEnd,
    required int insertedLength,
    List<HighlightSpan>? previousSpans,
  }) {
    return highlight(source);
  }
}
