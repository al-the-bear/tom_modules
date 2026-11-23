import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

import 'yaml_highlighter_test.dart' show tokensOf;

void main() {
  test('.env: the tokens of a sample', () {
    const sample = r'''
# Secrets
API_KEY=abc123 # inline
export HOST = "db.$DOMAIN"
QUOTED='literal $NOT'
MULTI="line one
line two"
not an assignment''';
    expect(tokensOf(EnvHighlighter(), sample), [
      ('# Secrets', 'comment'),
      ('API_KEY', 'attr'),
      ('=', 'punctuation'),
      ('abc123', 'string'),
      ('# inline', 'comment'),
      ('export', 'keyword'),
      ('HOST', 'attr'),
      ('=', 'punctuation'),
      (r'"db.$DOMAIN"', 'string'),
      (r'$DOMAIN', 'variable'),
      ('QUOTED', 'attr'),
      ('=', 'punctuation'),
      (r"'literal $NOT'", 'string'),
      ('MULTI', 'attr'),
      ('=', 'punctuation'),
      ('"line one\nline two"', 'string'),
    ]);
  });
}
