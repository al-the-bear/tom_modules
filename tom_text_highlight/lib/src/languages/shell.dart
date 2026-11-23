/// Shell scripts (sh, bash, zsh): comments, the shebang, strings, variables,
/// keywords and builtins.
library;

import '../token_highlighter.dart';

/// The shell highlighter. Its token classes:
///
/// | Class | What |
/// | --- | --- |
/// | `meta` | the shebang line (`#!...` at the very start) |
/// | `comment` | `#` to the line's end, where a word could start |
/// | `string` | a single- or double-quoted string (it may span lines) |
/// | `variable` | `$name`, `${...}`, `$1`, `$@`, `$?` ..., also inside a double-quoted string |
/// | `keyword` | `if then else elif fi for while until do done case esac in function select return export local readonly declare` |
/// | `built_in` | builtins such as `echo cd printf read set source test` |
class ShellHighlighter extends TokenHighlighter {
  ShellHighlighter({super.theme});

  static const Set<String> keywords = {
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', //
    'done', 'case', 'esac', 'in', 'function', 'select', 'return', 'export',
    'local', 'readonly', 'declare', 'unset', 'time',
  };

  static const Set<String> builtins = {
    'echo', 'printf', 'cd', 'pwd', 'exit', 'source', 'alias', 'unalias', //
    'read', 'test', 'eval', 'exec', 'set', 'shift', 'trap', 'wait', 'type',
    'command', 'getopts', 'true', 'false', 'break', 'continue', 'pushd',
    'popd', 'umask', 'ulimit', 'let', 'mapfile', 'shopt', 'jobs', 'kill',
  };

  static final RegExp _variable = RegExp(
    r'\$(?:\{[^}\n]*\}|[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])',
  );
  static final RegExp _word = RegExp(r'[A-Za-z_][A-Za-z0-9_-]*');

  @override
  List<HighlightToken> tokenize(String source) {
    final tokens = <HighlightToken>[];
    var i = 0;
    if (source.startsWith('#!')) {
      final nl = source.indexOf('\n');
      i = nl < 0 ? source.length : nl;
      tokens.add(HighlightToken(0, i, 'meta'));
    }
    while (i < source.length) {
      final c = source[i];
      if (c == '\\') {
        i += 2;
      } else if (c == '#' && _wordStart(source, i)) {
        final nl = source.indexOf('\n', i);
        final end = nl < 0 ? source.length : nl;
        tokens.add(HighlightToken(i, end, 'comment'));
        i = end;
      } else if (c == "'") {
        final close = source.indexOf("'", i + 1);
        final end = close < 0 ? source.length : close + 1;
        tokens.add(HighlightToken(i, end, 'string'));
        i = end;
      } else if (c == '"') {
        var j = i + 1;
        while (j < source.length && source[j] != '"') {
          j += source[j] == '\\' ? 2 : 1;
        }
        final end = j < source.length ? j + 1 : source.length;
        tokens.add(HighlightToken(i, end, 'string'));
        for (final m in _variable.allMatches(source.substring(i, end))) {
          tokens.add(HighlightToken(i + m.start, i + m.end, 'variable'));
        }
        i = end;
      } else if (c == r'$') {
        final m = _variable.matchAsPrefix(source, i);
        if (m == null) {
          i++;
        } else {
          tokens.add(HighlightToken(i, m.end, 'variable'));
          i = m.end;
        }
      } else if (_word.matchAsPrefix(source, i) case final m?
          when _wordStart(source, i)) {
        final word = m.group(0)!;
        final end = m.end;
        final standalone = end == source.length || !_isWordChar(source[end]);
        if (standalone && keywords.contains(word)) {
          tokens.add(HighlightToken(i, end, 'keyword'));
        } else if (standalone && builtins.contains(word)) {
          tokens.add(HighlightToken(i, end, 'built_in'));
        }
        i = end;
      } else {
        i++;
      }
    }
    return tokens;
  }

  static bool _wordStart(String s, int i) =>
      i == 0 || ' \t\n;|&(){}`'.contains(s[i - 1]);

  static final RegExp _wordChar = RegExp(r'[A-Za-z0-9_=./-]');

  static bool _isWordChar(String c) => _wordChar.hasMatch(c);
}
