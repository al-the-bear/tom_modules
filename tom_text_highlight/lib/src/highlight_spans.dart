import 'package:flutter/painting.dart';

import 'syntax_highlighter.dart';

/// [source] as runs of [TextSpan]s styled by [spans], for a
/// `TextEditingController.buildTextSpan` or a `Text.rich`.
///
/// The spans are applied in order, a later one replacing an earlier one's
/// style where they overlap; text no span covers has no style of its own and
/// takes the parent's. Neighbouring characters with the same style form one
/// run. The runs cover the whole of [source].
List<InlineSpan> highlightedInlineSpans(
  String source,
  List<HighlightSpan> spans,
) {
  if (source.isEmpty) return const <InlineSpan>[];
  if (spans.isEmpty) return <InlineSpan>[TextSpan(text: source)];
  final length = source.length;
  final styles = List<TextStyle?>.filled(length, null);
  for (final span in spans) {
    final start = span.start.clamp(0, length);
    final end = span.end.clamp(0, length);
    for (var i = start; i < end; i++) {
      styles[i] = span.style;
    }
  }
  final out = <InlineSpan>[];
  var runStart = 0;
  for (var i = 1; i <= length; i++) {
    if (i == length || styles[i] != styles[runStart]) {
      out.add(
        TextSpan(text: source.substring(runStart, i), style: styles[runStart]),
      );
      runStart = i;
    }
  }
  return out;
}
