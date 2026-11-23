import 'highlight_theme.dart';
import 'syntax_highlighter.dart';

/// One token a [TokenHighlighter] found: `[start, end)` of class [type].
class HighlightToken {
  const HighlightToken(this.start, this.end, this.type);

  final int start;
  final int end;

  /// The token class, e.g. `attr` or `literal.boolean`.
  final String type;

  @override
  bool operator ==(Object other) =>
      other is HighlightToken &&
      other.start == start &&
      other.end == end &&
      other.type == type;

  @override
  int get hashCode => Object.hash(start, end, type);

  @override
  String toString() => 'HighlightToken($start, $end, $type)';
}

/// A [SyntaxHighlighter] in two halves: [tokenize] finds the tokens, and
/// [theme] styles them. A token whose class the theme does not style gives
/// no span, so the text there keeps the view's own style.
abstract class TokenHighlighter extends SyntaxHighlighter {
  TokenHighlighter({this.theme = HighlightTheme.none});

  /// The styles of the token classes.
  final HighlightTheme theme;

  /// The tokens of [source], in order; a later token overrides an earlier
  /// one where they overlap.
  List<HighlightToken> tokenize(String source);

  @override
  List<HighlightSpan> highlight(String source) => [
    for (final token in tokenize(source))
      if (theme.styleFor(token.type) case final style?)
        HighlightSpan(
          start: token.start,
          end: token.end,
          style: style,
          type: token.type,
        ),
  ];
}
