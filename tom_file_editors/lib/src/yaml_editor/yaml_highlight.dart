/// YAML highlighting for the source editor — comments, keys,
/// sequence dashes, document markers, quoted strings and literal scalars.
library;

import 'package:flutter/material.dart';

final RegExp _key = RegExp(
  r'''^(\s*(?:-\s+)*)((?:"[^"]*"|'[^']*'|[^\s#:'"][^#:]*?))(\s*:)(\s|$)''',
);
final RegExp _comment = RegExp(r'(^|\s)#.*$');

/// Spans covering [text], highlighted as YAML.
List<InlineSpan> tomYamlHighlight(String text, ColorScheme colors) {
  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  final keyStyle = TextStyle(
    color: colors.primary,
    fontWeight: FontWeight.w600,
  );
  final commentStyle = TextStyle(
    color: colors.onSurfaceVariant,
    fontStyle: FontStyle.italic,
  );
  final markerStyle = TextStyle(color: colors.secondary);
  final stringStyle = TextStyle(color: colors.tertiary);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final t = line.trimLeft();
    if (t.startsWith('#')) {
      spans.add(TextSpan(text: line, style: commentStyle));
    } else if (t == '---' || t == '...') {
      spans.add(TextSpan(text: line, style: markerStyle));
    } else {
      // A trailing comment, outside quotes, is split off first.
      String? comment;
      final c = _comment.firstMatch(line);
      if (c != null && !_insideQuotes(line, c.start)) {
        comment = line.substring(c.start);
        line = line.substring(0, c.start);
      }
      final k = _key.firstMatch(line);
      if (k != null) {
        final prefix = k.group(1)!;
        spans.add(TextSpan(text: prefix, style: markerStyle));
        spans.add(TextSpan(text: k.group(2), style: keyStyle));
        spans.add(TextSpan(text: k.group(3)));
        spans.add(
          _value(
            line.substring(
              k.start +
                  k.group(1)!.length +
                  k.group(2)!.length +
                  k.group(3)!.length,
            ),
            stringStyle,
          ),
        );
      } else {
        final dash = RegExp(r'^(\s*(?:-\s+)+)').firstMatch(line);
        if (dash != null) {
          spans.add(TextSpan(text: dash.group(1), style: markerStyle));
          spans.add(_value(line.substring(dash.end), stringStyle));
        } else {
          spans.add(_value(line, stringStyle));
        }
      }
      if (comment != null) {
        spans.add(TextSpan(text: comment, style: commentStyle));
      }
    }
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return spans;
}

TextSpan _value(String text, TextStyle stringStyle) {
  final t = text.trim();
  final quoted =
      (t.startsWith('"') && t.endsWith('"') && t.length > 1) ||
      (t.startsWith("'") && t.endsWith("'") && t.length > 1);
  return TextSpan(text: text, style: quoted ? stringStyle : null);
}

bool _insideQuotes(String line, int at) {
  var dq = false;
  var sq = false;
  for (var i = 0; i < at; i++) {
    final c = line[i];
    if (c == '"' && !sq) dq = !dq;
    if (c == "'" && !dq) sq = !sq;
  }
  return dq || sq;
}
