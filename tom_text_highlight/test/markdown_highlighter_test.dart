import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

import 'yaml_highlighter_test.dart' show tokensOf;

void main() {
  test('Markdown: the tokens of a sample', () {
    const sample = '''
# Title
Some **bold**, *it*, `code` and [a link](x.md).
- [x] done
1. first
> quoted
<!-- a
comment -->
```dart
var a = 1;
```
text <!-- inline --> _em_''';
    expect(tokensOf(MarkdownHighlighter(), sample), [
      ('# Title', 'section'),
      ('**bold**', 'strong'),
      ('*it*', 'emphasis'),
      ('`code`', 'code.inline'),
      ('[a link](x.md)', 'link'),
      ('- [x] ', 'bullet'),
      ('1. ', 'bullet'),
      ('> quoted', 'quote'),
      ('<!-- a', 'comment'),
      ('comment -->', 'comment'),
      ('```dart', 'code.block'),
      ('var a = 1;', 'code.block'),
      ('```', 'code.block'),
      ('<!-- inline -->', 'comment'),
      ('_em_', 'emphasis'),
    ]);
  });
}
