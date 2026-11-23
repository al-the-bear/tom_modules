import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

import 'yaml_highlighter_test.dart' show tokensOf;

void main() {
  test('JSON: the tokens of a sample', () {
    const sample = '''
{
  "name": "tom \\"x\\"",
  "n": -1.5e3, // comment
  "ok": [true, null]
}''';
    expect(tokensOf(JsonHighlighter(), sample), [
      ('{', 'punctuation'),
      ('"name"', 'attr'),
      (':', 'punctuation'),
      (r'"tom \"x\""', 'string'),
      (',', 'punctuation'),
      ('"n"', 'attr'),
      (':', 'punctuation'),
      ('-1.5e3', 'number'),
      (',', 'punctuation'),
      ('// comment', 'comment'),
      ('"ok"', 'attr'),
      (':', 'punctuation'),
      ('[', 'punctuation'),
      ('true', 'literal'),
      (',', 'punctuation'),
      ('null', 'literal'),
      (']', 'punctuation'),
      ('}', 'punctuation'),
    ]);
  });
}
