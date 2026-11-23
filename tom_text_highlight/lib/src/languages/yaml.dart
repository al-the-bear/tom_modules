/// YAML: comments, document markers, sequence dashes, keys and their colons,
/// quoted and plain scalars, booleans, nulls, numbers, block scalar
/// indicators and flow brackets.
library;

import '../token_highlighter.dart';

/// The YAML highlighter both editor families use.
///
/// It works line by line and keeps no state between lines. Its token
/// classes:
///
/// | Class | What |
/// | --- | --- |
/// | `comment` | a whole-line comment, or a trailing ` #` comment outside quotes |
/// | `meta` | a document marker, `---` or `...` |
/// | `bullet` | a sequence dash (`- `), each of a nested `- - ` |
/// | `attr` | a mapping key (quoted or plain) |
/// | `punctuation.colon` | the colon after a key |
/// | `string` | a quoted scalar |
/// | `plain` | an unquoted scalar that is no boolean, null or number |
/// | `literal.boolean` | `true` `false` `yes` `no` `on` `off`, any case |
/// | `literal.null` | `null` or `~` |
/// | `number` | an integer or a decimal number |
/// | `punctuation.block` | a block scalar indicator (`\|`, `>`, `\|-`, `>+2`, ...) |
/// | `punctuation.bracket` | `[ ] { }` outside quotes in a value |
class YamlHighlighter extends TokenHighlighter {
  YamlHighlighter({super.theme});

  @override
  List<HighlightToken> tokenize(String source) {
    final tokens = <HighlightToken>[];
    var offset = 0;
    for (final line in source.split('\n')) {
      _line(line, offset, tokens);
      offset += line.length + 1;
    }
    return tokens;
  }

  void _line(String line, int o, List<HighlightToken> tokens) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return;
    final indent = line.length - trimmed.length;
    if (trimmed.startsWith('#')) {
      tokens.add(HighlightToken(o + indent, o + line.length, 'comment'));
      return;
    }
    final marker = trimmed.trimRight();
    if (marker == '---' || marker == '...') {
      tokens.add(
        HighlightToken(o + indent, o + indent + marker.length, 'meta'),
      );
      return;
    }
    var pos = indent;
    while (pos < line.length &&
        line[pos] == '-' &&
        (pos + 1 == line.length || _isSpace(line[pos + 1]))) {
      tokens.add(HighlightToken(o + pos, o + pos + 1, 'bullet'));
      pos++;
      while (pos < line.length && _isSpace(line[pos])) {
        pos++;
      }
    }
    final commentAt = _commentIndex(line, pos);
    final content = line.substring(pos, commentAt ?? line.length);
    final colon = _keyColon(content);
    if (colon > 0) {
      final key = content.substring(0, colon).trimRight();
      tokens.add(HighlightToken(o + pos, o + pos + key.length, 'attr'));
      tokens.add(
        HighlightToken(
          o + pos + colon,
          o + pos + colon + 1,
          'punctuation.colon',
        ),
      );
      _value(content.substring(colon + 1), o + pos + colon + 1, tokens);
    } else {
      _value(content, o + pos, tokens);
    }
    if (commentAt != null) {
      tokens.add(HighlightToken(o + commentAt, o + line.length, 'comment'));
    }
  }

  void _value(String text, int base, List<HighlightToken> tokens) {
    final value = text.trim();
    if (value.isEmpty) return;
    final start = base + (text.length - text.trimLeft().length);
    final end = start + value.length;
    tokens.add(HighlightToken(start, end, _classify(value)));
    var single = false;
    var double = false;
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c == "'" && !double) {
        single = !single;
      } else if (c == '"' && !single) {
        double = !double;
      } else if (!single &&
          !double &&
          (c == '[' || c == ']' || c == '{' || c == '}')) {
        tokens.add(
          HighlightToken(start + i, start + i + 1, 'punctuation.bracket'),
        );
      }
    }
  }

  static final RegExp _blockScalar = RegExp(r'^[|>]([+-]?[0-9]?|[0-9][+-])$');

  String _classify(String value) {
    if (value.length > 1 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return 'string';
    }
    if (_blockScalar.hasMatch(value)) return 'punctuation.block';
    switch (value.toLowerCase()) {
      case 'true' || 'false' || 'yes' || 'no' || 'on' || 'off':
        return 'literal.boolean';
      case 'null' || '~':
        return 'literal.null';
    }
    if (double.tryParse(value) != null) return 'number';
    return 'plain';
  }

  /// The colon that ends a key: outside quotes and followed by a space, a
  /// tab or the end; -1 when there is none.
  int _keyColon(String content) {
    var single = false;
    var double = false;
    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == "'" && !double) single = !single;
      if (c == '"' && !single) double = !double;
      if (c == ':' &&
          !single &&
          !double &&
          (i + 1 == content.length || _isSpace(content[i + 1]))) {
        return i;
      }
    }
    return -1;
  }

  /// Where a trailing comment starts: a `#` outside quotes after a space or
  /// a tab, at or after [from]; null when there is none.
  int? _commentIndex(String line, int from) {
    var single = false;
    var double = false;
    for (var i = from; i < line.length; i++) {
      final c = line[i];
      if (c == "'" && !double) single = !single;
      if (c == '"' && !single) double = !double;
      if (c == '#' && !single && !double && i > 0 && _isSpace(line[i - 1])) {
        return i;
      }
    }
    return null;
  }

  static bool _isSpace(String c) => c == ' ' || c == '\t';
}
