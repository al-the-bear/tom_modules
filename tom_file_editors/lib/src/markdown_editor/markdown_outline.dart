/// The headings of a Markdown file, read from its source.
///
/// The outline is read from the text, not from a rendering, because it serves
/// all three view modes: in the source view a heading is a line to jump to,
/// in the rendered view a widget, and the line is what both share. Headings
/// inside front matter and fenced code are not headings.
library;

/// One heading of a Markdown file.
class TomMarkdownHeading {
  const TomMarkdownHeading({
    required this.level,
    required this.text,
    required this.line,
    required this.slug,
  });

  /// 1–6.
  final int level;

  /// The heading's text, markers removed.
  final String text;

  /// The 0-based line the heading starts on.
  final int line;

  /// Its anchor, as GitHub forms one: what `#anchor` links name.
  final String slug;
}

final RegExp _atx = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$');
final RegExp _setext = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');

/// The length of the front matter in [lines], or 0 when there is none.
int tomFrontMatterLines(List<String> lines) {
  if (lines.isEmpty || lines.first.trimRight() != '---') return 0;
  for (var i = 1; i < lines.length; i++) {
    final t = lines[i].trimRight();
    if (t == '---' || t == '...') return i + 1;
  }
  return 0;
}

/// The headings of [markdown], in order.
List<TomMarkdownHeading> tomMarkdownOutline(String markdown) {
  final lines = markdown.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  final out = <TomMarkdownHeading>[];
  final slugs = <String, int>{};
  String unique(String slug) {
    final n = slugs[slug] ?? 0;
    slugs[slug] = n + 1;
    return n == 0 ? slug : '$slug-$n';
  }

  var fence = '';
  for (var i = tomFrontMatterLines(lines); i < lines.length; i++) {
    final line = lines[i];
    final t = line.trimLeft();
    if (fence.isEmpty && (t.startsWith('```') || t.startsWith('~~~'))) {
      fence = t.substring(0, 3);
      continue;
    }
    if (fence.isNotEmpty) {
      if (t.startsWith(fence)) fence = '';
      continue;
    }
    final atx = _atx.firstMatch(line);
    if (atx != null) {
      final text = _plain(atx.group(2) ?? '');
      out.add(TomMarkdownHeading(
        level: atx.group(1)!.length,
        text: text,
        line: i,
        slug: unique(tomMarkdownSlug(text)),
      ));
      continue;
    }
    if (i > 0 &&
        _setext.hasMatch(line) &&
        lines[i - 1].trim().isNotEmpty &&
        !_atx.hasMatch(lines[i - 1]) &&
        !lines[i - 1].trimLeft().startsWith(RegExp(r'[-*+>|]'))) {
      final text = _plain(lines[i - 1].trim());
      out.add(TomMarkdownHeading(
        level: line.trim().startsWith('=') ? 1 : 2,
        text: text,
        line: i - 1,
        slug: unique(tomMarkdownSlug(text)),
      ));
    }
  }
  return out;
}

/// [text] with inline Markdown markers removed: what a reader sees.
String _plain(String text) => text
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'[*_`~]'), '')
    .trim();

/// GitHub's anchor for a heading: lower case, punctuation dropped, spaces
/// as `-`.
String tomMarkdownSlug(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'\s'), '-');
