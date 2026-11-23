/// `.env` files: comments, `export`, keys, the `=`, values and the variables
/// they refer to.
library;

import '../token_highlighter.dart';

/// The `.env` highlighter. Its token classes:
///
/// | Class | What |
/// | --- | --- |
/// | `comment` | a whole-line `#` comment, or a ` #` comment after an unquoted or closed value |
/// | `keyword` | a leading `export` |
/// | `attr` | the key |
/// | `punctuation` | the `=` |
/// | `string` | the value, quoted or not (a quoted one may span lines) |
/// | `variable` | `$NAME` and `${NAME}` in an unquoted or double-quoted value |
///
/// A line that is no comment and no `KEY=` assignment stays plain.
class EnvHighlighter extends TokenHighlighter {
  EnvHighlighter({super.theme});

  static final RegExp _assignment = RegExp(
    r'^([ \t]*)(export[ \t]+)?([A-Za-z_][A-Za-z0-9_.-]*)([ \t]*)=',
  );
  static final RegExp _variable = RegExp(
    r'\$(?:\{[^}\n]*\}|[A-Za-z_][A-Za-z0-9_]*)',
  );

  @override
  List<HighlightToken> tokenize(String source) {
    final tokens = <HighlightToken>[];
    var i = 0;
    while (i < source.length) {
      final nl = source.indexOf('\n', i);
      final lineEnd = nl < 0 ? source.length : nl;
      final line = source.substring(i, lineEnd);
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) {
        tokens.add(
          HighlightToken(i + line.length - trimmed.length, lineEnd, 'comment'),
        );
        i = lineEnd + 1;
        continue;
      }
      final m = _assignment.firstMatch(line);
      if (m == null) {
        i = lineEnd + 1;
        continue;
      }
      var at = i + m.group(1)!.length;
      if (m.group(2) != null) {
        tokens.add(HighlightToken(at, at + 'export'.length, 'keyword'));
        at += m.group(2)!.length;
      }
      final key = m.group(3)!;
      tokens.add(HighlightToken(at, at + key.length, 'attr'));
      at += key.length + m.group(4)!.length;
      tokens.add(HighlightToken(at, at + 1, 'punctuation'));
      i = _value(source, at + 1, lineEnd, tokens);
    }
    return tokens;
  }

  /// Tokens of the value starting at [start]; answers where the next line
  /// starts.
  int _value(String s, int start, int lineEnd, List<HighlightToken> tokens) {
    var v = start;
    while (v < lineEnd && (s[v] == ' ' || s[v] == '\t')) {
      v++;
    }
    if (v < s.length && (s[v] == '"' || s[v] == "'")) {
      final quote = s[v];
      var j = v + 1;
      while (j < s.length && s[j] != quote) {
        j += quote == '"' && s[j] == '\\' ? 2 : 1;
      }
      final end = j < s.length ? j + 1 : s.length;
      tokens.add(HighlightToken(v, end, 'string'));
      if (quote == '"') _variables(s, v, end, tokens);
      final nl = s.indexOf('\n', end);
      final after = nl < 0 ? s.length : nl;
      final hash = s.indexOf('#', end);
      if (hash >= 0 && hash < after) {
        tokens.add(HighlightToken(hash, after, 'comment'));
      }
      return after + 1;
    }
    var end = lineEnd;
    int? comment;
    for (var j = v; j < lineEnd; j++) {
      if (s[j] == '#' && (j == v || s[j - 1] == ' ' || s[j - 1] == '\t')) {
        comment = j;
        end = j;
        break;
      }
    }
    while (end > v && (s[end - 1] == ' ' || s[end - 1] == '\t')) {
      end--;
    }
    if (end > v) {
      tokens.add(HighlightToken(v, end, 'string'));
      _variables(s, v, end, tokens);
    }
    if (comment != null) {
      tokens.add(HighlightToken(comment, lineEnd, 'comment'));
    }
    return lineEnd + 1;
  }

  void _variables(String s, int start, int end, List<HighlightToken> tokens) {
    for (final m in _variable.allMatches(s.substring(start, end))) {
      tokens.add(HighlightToken(start + m.start, start + m.end, 'variable'));
    }
  }
}
