import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

void main() {
  const a = TextStyle(color: Color(0xFF0000AA));
  const b = TextStyle(color: Color(0xFF00BB00));

  test('highlightedInlineSpans: runs over the whole text, later spans win', () {
    final spans = highlightedInlineSpans('abcdef', const [
      HighlightSpan(start: 1, end: 4, style: a),
      HighlightSpan(start: 3, end: 5, style: b),
    ]);
    expect(
      [for (final s in spans.cast<TextSpan>()) (s.text, s.style)],
      [('a', null), ('bc', a), ('de', b), ('f', null)],
    );
  });

  test('highlightedInlineSpans: no spans, one plain run; empty, none', () {
    expect(
      [
        for (final s in highlightedInlineSpans('x', const []).cast<TextSpan>())
          (s.text, s.style),
      ],
      [('x', null)],
    );
    expect(highlightedInlineSpans('', const []), isEmpty);
  });

  test('HighlightTheme: exact class first, then the dotted prefix', () {
    const theme = HighlightTheme({'literal': a, 'literal.null': b});
    expect(theme.styleFor('literal.null'), b);
    expect(theme.styleFor('literal.boolean'), a);
    expect(theme.styleFor('string'), isNull);
  });

  test('highlighterForLanguage: names and aliases, unknown is null', () {
    expect(highlighterForLanguage('YML'), isA<YamlHighlighter>());
    expect(highlighterForLanguage('md'), isA<MarkdownHighlighter>());
    expect(highlighterForLanguage('json'), isA<JsonHighlighter>());
    expect(highlighterForLanguage('zsh'), isA<ShellHighlighter>());
    expect(highlighterForLanguage('dotenv'), isA<EnvHighlighter>());
    expect(highlighterForLanguage('python'), isNull);
    expect(highlighterForLanguage(null), isNull);
  });
}
