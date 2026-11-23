import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

import 'yaml_highlighter_test.dart' show tokensOf;

void main() {
  test('Shell: the tokens of a sample', () {
    const sample = r'''
#!/bin/bash
# build it
for f in *.dart; do
  echo "file $f in ${DIR}" # note
done
export NAME='a#b'
if [ $? -ne 0 ]; then exit 1; fi''';
    expect(tokensOf(ShellHighlighter(), sample), [
      ('#!/bin/bash', 'meta'),
      ('# build it', 'comment'),
      ('for', 'keyword'),
      ('in', 'keyword'),
      ('do', 'keyword'),
      ('echo', 'built_in'),
      (r'"file $f in ${DIR}"', 'string'),
      (r'$f', 'variable'),
      (r'${DIR}', 'variable'),
      ('# note', 'comment'),
      ('done', 'keyword'),
      ('export', 'keyword'),
      ("'a#b'", 'string'),
      ('if', 'keyword'),
      (r'$?', 'variable'),
      ('then', 'keyword'),
      ('exit', 'built_in'),
      ('fi', 'keyword'),
    ]);
  });
}
