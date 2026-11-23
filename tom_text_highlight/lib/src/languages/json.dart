/// JSON (and the comments of JSON with comments): keys, strings, numbers,
/// literals, punctuation and comments.
library;

import '../token_highlighter.dart';

/// The JSON highlighter. Its token classes:
///
/// | Class | What |
/// | --- | --- |
/// | `attr` | an object key: a string followed by a colon |
/// | `string` | any other string |
/// | `number` | a number |
/// | `literal` | `true`, `false`, `null` |
/// | `punctuation` | `{ } [ ] , :` |
/// | `comment` | `// ...` and `/* ... */` (JSON with comments) |
///
/// An unterminated string ends at its line's end; anything else the grammar
/// does not know stays plain.
class JsonHighlighter extends TokenHighlighter {
  JsonHighlighter({super.theme});

  static final RegExp _number = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  static final RegExp _word = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

  @override
  List<HighlightToken> tokenize(String source) {
    final tokens = <HighlightToken>[];
    var i = 0;
    while (i < source.length) {
      final c = source[i];
      if (c == '"') {
        var j = i + 1;
        while (j < source.length && source[j] != '"' && source[j] != '\n') {
          j += source[j] == '\\' ? 2 : 1;
        }
        final end = j < source.length && source[j] == '"' ? j + 1 : j;
        var k = end;
        while (k < source.length && ' \t\r\n'.contains(source[k])) {
          k++;
        }
        final isKey = k < source.length && source[k] == ':';
        tokens.add(HighlightToken(i, end, isKey ? 'attr' : 'string'));
        i = end;
      } else if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
        final nl = source.indexOf('\n', i);
        final end = nl < 0 ? source.length : nl;
        tokens.add(HighlightToken(i, end, 'comment'));
        i = end;
      } else if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
        final close = source.indexOf('*/', i + 2);
        final end = close < 0 ? source.length : close + 2;
        tokens.add(HighlightToken(i, end, 'comment'));
        i = end;
      } else if ('{}[],:'.contains(c)) {
        tokens.add(HighlightToken(i, i + 1, 'punctuation'));
        i++;
      } else if (c == '-' || _isDigit(c)) {
        final m = _number.matchAsPrefix(source, i);
        if (m == null || m.end == i) {
          i++;
        } else {
          tokens.add(HighlightToken(i, m.end, 'number'));
          i = m.end;
        }
      } else if (_word.matchAsPrefix(source, i) case final m?) {
        final word = m.group(0)!;
        if (word == 'true' || word == 'false' || word == 'null') {
          tokens.add(HighlightToken(i, m.end, 'literal'));
        }
        i = m.end;
      } else {
        i++;
      }
    }
    return tokens;
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }
}
