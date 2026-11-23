import 'package:flutter/painting.dart';

/// The styles of a highlighter's token classes.
///
/// A token class is a highlight.js class name (`comment`, `string`, `attr`,
/// ...) or a dotted refinement of one (`literal.boolean`,
/// `punctuation.colon`). [styleFor] looks the class up, then each shorter
/// prefix, so a theme that only knows `literal` styles `literal.null` too,
/// and one that knows both tells them apart.
class HighlightTheme {
  const HighlightTheme(this.styles);

  /// A theme that styles nothing: every token stays plain.
  static const HighlightTheme none = HighlightTheme(<String, TextStyle>{});

  /// Token class to style.
  final Map<String, TextStyle> styles;

  /// The style of [type], or of its nearest dotted prefix; null when the
  /// theme styles neither.
  TextStyle? styleFor(String type) {
    var t = type;
    while (true) {
      final style = styles[t];
      if (style != null) return style;
      final dot = t.lastIndexOf('.');
      if (dot < 0) return null;
      t = t.substring(0, dot);
    }
  }
}
