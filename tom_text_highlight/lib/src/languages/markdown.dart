/// Markdown: heading lines, list markers, fences and their code, HTML
/// comments, block quotes, inline code, emphasis and links.
library;

import '../token_highlighter.dart';

/// The Markdown source highlighter.
///
/// Line by line, with two states carried over: inside a fenced block, and
/// inside a multi-line HTML comment. Its token classes:
///
/// | Class | What |
/// | --- | --- |
/// | `code.block` | a fence line (` ``` ` or `~~~`) and every line inside the fence |
/// | `comment` | an HTML comment: the lines of a block one, or an inline `<!-- -->` |
/// | `section` | a heading line (`#` to `######`, up to three spaces in) |
/// | `quote` | a block quote line |
/// | `bullet` | a list marker, with a task box (`- [x] `) |
/// | `code.inline` | `` `code` `` |
/// | `strong` | `**text**` or `__text__` |
/// | `emphasis` | `*text*` or `_text_` |
/// | `link` | `[text](target)` and `![alt](src)` |
class MarkdownHighlighter extends TokenHighlighter {
  MarkdownHighlighter({super.theme});

  static final RegExp _heading = RegExp(r'^ {0,3}#{1,6}(\s|$)');
  static final RegExp _marker = RegExp(
    r'^(\s*)([-*+]|\d+[.)])(\s+\[[ xX]\])?\s',
  );
  static final RegExp _inline = RegExp(
    r'(`[^`\n]+`)|(\*\*[^*\n]+\*\*|__[^_\n]+__)|(\*[^*\s][^*\n]*\*|_[^_\s][^_\n]*_)|(!?\[[^\]\n]*\]\([^)\n]*\))|(<!--.*?-->)',
  );

  @override
  List<HighlightToken> tokenize(String source) {
    final tokens = <HighlightToken>[];
    var offset = 0;
    var fenced = false;
    var comment = false;
    for (final line in source.split('\n')) {
      final t = line.trimLeft();
      final isFence = t.startsWith('```') || t.startsWith('~~~');
      String? lineType;
      if (isFence || fenced) {
        lineType = 'code.block';
      } else if (comment || t.startsWith('<!--')) {
        lineType = 'comment';
      } else if (_heading.hasMatch(line)) {
        lineType = 'section';
      } else if (t.startsWith('>')) {
        lineType = 'quote';
      }
      final opensComment = !fenced && t.contains('<!--') && !t.contains('-->');
      final closesComment = comment && t.contains('-->');
      if (isFence) fenced = !fenced;
      if (lineType != null) {
        if (line.isNotEmpty) {
          tokens.add(HighlightToken(offset, offset + line.length, lineType));
        }
      } else {
        _inlineTokens(line, offset, tokens);
      }
      if (opensComment) comment = true;
      if (closesComment) comment = false;
      offset += line.length + 1;
    }
    return tokens;
  }

  void _inlineTokens(String line, int offset, List<HighlightToken> tokens) {
    var at = 0;
    final marker = _marker.firstMatch(line);
    if (marker != null) {
      tokens.add(HighlightToken(offset, offset + marker.end, 'bullet'));
      at = marker.end;
    }
    final rest = line.substring(at);
    final base = offset + at;
    for (final m in _inline.allMatches(rest)) {
      final String type;
      if (m.group(1) != null) {
        type = 'code.inline';
      } else if (m.group(2) != null) {
        type = 'strong';
      } else if (m.group(3) != null) {
        type = 'emphasis';
      } else if (m.group(4) != null) {
        type = 'link';
      } else {
        type = 'comment';
      }
      tokens.add(HighlightToken(base + m.start, base + m.end, type));
    }
  }
}
