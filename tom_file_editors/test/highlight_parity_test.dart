// The source views look as before: the shared highlighters, in the source
// editor's colours, give every visible character the style the source
// editor's own YAML and Markdown highlighters gave it. The former
// highlighters are kept below, verbatim, as the reference.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_editors/tom_file_editors.dart';

/// The style of every character of [spans] (flattened, parent styles merged).
List<TextStyle?> charStyles(List<InlineSpan> spans) {
  final out = <TextStyle?>[];
  void walk(InlineSpan s, TextStyle? inherited) {
    if (s is! TextSpan) return;
    final style = inherited == null ? s.style : inherited.merge(s.style);
    for (var i = 0; i < (s.text?.length ?? 0); i++) {
      out.add(style);
    }
    for (final c in s.children ?? const <InlineSpan>[]) {
      walk(c, style);
    }
  }

  for (final s in spans) {
    walk(s, null);
  }
  return out;
}

/// The offsets of [text]'s visible characters whose style differs.
List<int> visibleDifferences(
  String text,
  List<InlineSpan> before,
  List<InlineSpan> after,
) {
  final a = charStyles(before);
  final b = charStyles(after);
  expect(a.whereType<TextStyle>(), isNotEmpty);
  expect(a.length, text.length);
  expect(b.length, text.length);
  return [
    for (var i = 0; i < text.length; i++)
      if (text[i].trim().isNotEmpty && a[i] != b[i]) i,
  ];
}

const yamlSample = r'''
# Todos of the quest
---
todos:
  - id: forgerestruct8_akwc-highlight
    title: "One highlighter interface"
    status: in-progress   # claimed
    priority: high
    tags: [forge, 'highlight']
    references:
      - path: tom_forge/tom_editors_shared/lib/src/text_editor/x.dart
      - url: https://example.com/a#b
    notes: |
      Several lines
      of notes.
    count: 3
    done: false
    blocked_by: ~
    "quoted key": 'quoted value'
    plain: value with: colon inside
...
''';

const markdownSample = '''
<!-- docspec: quest/1 -->
# Title

Some **bold**, *italic*, __strong__, _em_, `code` and [link](a.md).
![image](img.png)

- item
  * nested item
1. first
2) second
- [ ] open task
- [x] done task

> A quote with **bold**

```yaml
key: value
# not a heading
```

<!--
a block comment
-->
Text with <!-- an inline comment --> inside.
## Heading two
   ### Indented heading
''';

void main() {
  for (final brightness in Brightness.values) {
    final colors = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: brightness,
    );
    test('YAML ($brightness): every visible character styled as before', () {
      expect(
        visibleDifferences(
          yamlSample,
          legacyYamlHighlight(yamlSample, colors),
          tomYamlHighlight(yamlSample, colors),
        ),
        isEmpty,
      );
    });
    test('Markdown ($brightness): every visible character styled as '
        'before', () {
      expect(
        visibleDifferences(
          markdownSample,
          legacyMarkdownHighlight(markdownSample, colors),
          tomMarkdownHighlight(markdownSample, colors),
        ),
        isEmpty,
      );
    });
  }
}

// ---------------------------------------------------------------------------
// The former highlighters, verbatim (renamed), as the reference.
// ---------------------------------------------------------------------------

final RegExp _key = RegExp(
  r'''^(\s*(?:-\s+)*)((?:"[^"]*"|'[^']*'|[^\s#:'"][^#:]*?))(\s*:)(\s|$)''',
);
final RegExp _comment = RegExp(r'(^|\s)#.*$');

/// Spans covering [text], highlighted as YAML.
List<InlineSpan> legacyYamlHighlight(String text, ColorScheme colors) {
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

/// Spans covering [text], highlighted as Markdown.
List<InlineSpan> legacyMarkdownHighlight(String text, ColorScheme colors) {
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
      lineStyle = TextStyle(
        color: colors.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      );
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
      s = TextStyle(
        color: colors.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      );
    }
    out.add(TextSpan(text: m.group(0), style: s));
    at = m.end;
  }
  if (at < rest.length) out.add(TextSpan(text: rest.substring(at)));
  return out;
}
