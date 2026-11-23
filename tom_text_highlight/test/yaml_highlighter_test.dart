import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

/// The tokens of [source] as `(text, class)` pairs, in order.
List<(String, String)> tokensOf(TokenHighlighter h, String source) => [
  for (final t in h.tokenize(source))
    (source.substring(t.start, t.end), t.type),
];

void main() {
  test('YAML: the tokens of a sample', () {
    const sample = '''
# A config
---
name: "tom app"   # quoted
version: 1.2
enabled: Yes
missing: ~
note: plain text
block: |-
- item
  - - nested: [a, b]
"quoted key": 'v'
url: http://x:80/a
...''';
    expect(tokensOf(YamlHighlighter(), sample), [
      ('# A config', 'comment'),
      ('---', 'meta'),
      ('name', 'attr'),
      (':', 'punctuation.colon'),
      ('"tom app"', 'string'),
      ('# quoted', 'comment'),
      ('version', 'attr'),
      (':', 'punctuation.colon'),
      ('1.2', 'number'),
      ('enabled', 'attr'),
      (':', 'punctuation.colon'),
      ('Yes', 'literal.boolean'),
      ('missing', 'attr'),
      (':', 'punctuation.colon'),
      ('~', 'literal.null'),
      ('note', 'attr'),
      (':', 'punctuation.colon'),
      ('plain text', 'plain'),
      ('block', 'attr'),
      (':', 'punctuation.colon'),
      ('|-', 'punctuation.block'),
      ('-', 'bullet'),
      ('item', 'plain'),
      ('-', 'bullet'),
      ('-', 'bullet'),
      ('nested', 'attr'),
      (':', 'punctuation.colon'),
      ('[a, b]', 'plain'),
      ('[', 'punctuation.bracket'),
      (']', 'punctuation.bracket'),
      ('"quoted key"', 'attr'),
      (':', 'punctuation.colon'),
      ("'v'", 'string'),
      ('url', 'attr'),
      (':', 'punctuation.colon'),
      ('http://x:80/a', 'plain'),
      ('...', 'meta'),
    ]);
  });

  test('YAML: a # inside quotes or a word is no comment', () {
    expect(tokensOf(YamlHighlighter(), 'a: "x # y"#z'), [
      ('a', 'attr'),
      (':', 'punctuation.colon'),
      ('"x # y"#z', 'plain'),
    ]);
  });

  test('YAML: the theme styles the classes it knows, by dotted fallback', () {
    const key = TextStyle(color: Color(0xFF000001));
    const literal = TextStyle(color: Color(0xFF000002));
    final h = YamlHighlighter(
      theme: const HighlightTheme({'attr': key, 'literal': literal}),
    );
    final spans = h.highlight('a: true\nb: x');
    expect(
      [for (final s in spans) (s.start, s.end, s.style, s.type)],
      [
        (0, 1, key, 'attr'),
        (3, 7, literal, 'literal.boolean'),
        (8, 9, key, 'attr'),
      ],
    );
  });
}
