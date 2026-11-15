/// Markdown highlighting for the source editor — heading lines,
/// list markers, fences and their code, HTML comments, block quotes, inline
/// code, emphasis and links.
library;

import 'package:flutter/material.dart';

/// Spans covering [text], highlighted as Markdown.
List<InlineSpan> tomMarkdownHighlight(String text, ColorScheme colors) {
  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  var fenced = false;
  var comment = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trimLeft();
    final isFence = t.startsWith('```') || t.startsWith('~~~');
    TextStyle? lineStyle;
    if (isFence || fenced) {
      lineStyle = TextStyle(color: colors.tertiary);
    } else if (comment || t.startsWith('<!--')) {
      lineStyle = TextStyle(color: colors.onSurfaceVariant, fontStyle: FontStyle.italic);
    } else if (RegExp(r'^ {0,3}#{1,6}(\s|$)').hasMatch(line)) {
      lineStyle = TextStyle(color: colors.primary, fontWeight: FontWeight.w700);
    } else if (t.startsWith('>')) {
      lineStyle = TextStyle(color: colors.secondary);
    }
    final opensComment = !fenced && t.contains('<!--') && !t.contains('-->');
    final closesComment = comment && t.contains('-->');
    if (isFence) fenced = !fenced;
    if (lineStyle != null) {
      spans.add(TextSpan(text: line, style: lineStyle));
    } else {
      spans.addAll(_inlineSpans(line, colors));
    }
    if (opensComment) comment = true;
    if (closesComment) comment = false;
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return spans;
}

final RegExp _inline = RegExp(
  r'(`[^`\n]+`)|(\*\*[^*\n]+\*\*|__[^_\n]+__)|(\*[^*\s][^*\n]*\*|_[^_\s][^_\n]*_)|(!?\[[^\]\n]*\]\([^)\n]*\))|(<!--.*?-->)',
);

List<InlineSpan> _inlineSpans(String line, ColorScheme colors) {
  final out = <InlineSpan>[];
  final marker = RegExp(
    r'^(\s*)([-*+]|\d+[.)])(\s+\[[ xX]\])?\s',
  ).firstMatch(line);
  var rest = line;
  if (marker != null) {
    out.add(
      TextSpan(
        text: marker.group(0),
        style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
      ),
    );
    rest = line.substring(marker.end);
  }
  var at = 0;
  for (final m in _inline.allMatches(rest)) {
    if (m.start > at) out.add(TextSpan(text: rest.substring(at, m.start)));
    final TextStyle s;
    if (m.group(1) != null) {
      s = TextStyle(
        color: colors.tertiary,
        backgroundColor: colors.surfaceContainerHighest,
      );
    } else if (m.group(2) != null) {
      s = const TextStyle(fontWeight: FontWeight.w700);
    } else if (m.group(3) != null) {
      s = const TextStyle(fontStyle: FontStyle.italic);
    } else if (m.group(4) != null) {
      s = TextStyle(color: colors.primary);
    } else {
      s = TextStyle(color: colors.onSurfaceVariant, fontStyle: FontStyle.italic);
    }
    out.add(TextSpan(text: m.group(0), style: s));
    at = m.end;
  }
  if (at < rest.length) out.add(TextSpan(text: rest.substring(at)));
  return out;
}
