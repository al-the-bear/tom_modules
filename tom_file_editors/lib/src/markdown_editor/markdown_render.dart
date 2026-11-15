/// A Markdown file drawn for reading.
///
/// Drawn from the `markdown` package's GitHub-flavoured AST, with the two
/// things a quest document carries that a Markdown renderer usually throws
/// away kept visible: front matter, as a muted block at the top, and HTML
/// comments — the `<!-- docspec: … -->` lines the document checks read — as
/// muted notes where they stand. Links are handed to the host, which opens a
/// file in a tab, reveals a folder or scrolls to an anchor; an image on the
/// web is fetched, and any other is read through [TomMarkdownBody.images].
///
/// One renderer serves both a file and a short text: [TomMarkdownRendered] is
/// a file's scrolling, selectable page; [TomMarkdownBody] is the body alone,
/// in the document style or, with `compact`, in the denser style of a model's
/// answer in the AI trail or a todo's notes.
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;

import 'package:tom_ui_support/tom_ui_support.dart';
import 'markdown_outline.dart';

/// Reads the image a Markdown file names by [src], as the file writes it —
/// relative to the file, or absolute. Null when there is none.
typedef TomMarkdownImageLoader = Future<Uint8List?> Function(String src);

/// A Markdown file's rendered page: [TomMarkdownBody] in the document style,
/// scrolling and selectable.
class TomMarkdownRendered extends StatelessWidget {
  const TomMarkdownRendered({
    super.key,
    required this.markdown,
    this.images,
    this.onLink,
    this.controller,
    this.headingKeys,
  });

  final String markdown;

  /// Reads an image that is not on the web; without it such an image is shown
  /// as its alternative text.
  final TomMarkdownImageLoader? images;

  /// A link was followed — its target as written.
  final ValueChanged<String>? onLink;

  final ScrollController? controller;

  /// Filled with one key per heading, in outline order, so the outline and
  /// `#anchor` links can scroll to it.
  final List<GlobalKey>? headingKeys;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        key: const Key('tom-markdown-rendered'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SelectionArea(
          child: TomMarkdownBody(
            markdown: markdown,
            images: images,
            onLink: onLink,
            headingKeys: headingKeys,
          ),
        ),
      );
}

/// [markdown] rendered as a column of widgets, without a scroll view and
/// without its own selection area — the caller decides both.
///
/// The document style draws a file: body text at reading size, headings with
/// a rule under the first two levels, wide gaps. `compact` draws a short text
/// inside another surface — a model's answer, a todo's notes: body text at
/// the surface's size, headings without rules, narrow gaps.
class TomMarkdownBody extends StatefulWidget {
  const TomMarkdownBody({
    super.key,
    required this.markdown,
    this.images,
    this.onLink,
    this.headingKeys,
    this.compact = false,
  });

  final String markdown;

  /// Reads an image that is not on the web; without it such an image is shown
  /// as its alternative text.
  final TomMarkdownImageLoader? images;

  /// A link was followed — its target as written.
  final ValueChanged<String>? onLink;

  /// Filled with one key per heading, in outline order.
  final List<GlobalKey>? headingKeys;

  /// The dense style of a short text inside another surface.
  final bool compact;

  @override
  State<TomMarkdownBody> createState() => _BodyState();
}

class _BodyState extends State<TomMarkdownBody> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final lines = widget.markdown
        .split('\n')
        .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
        .toList();
    final front = tomFrontMatterLines(lines);
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(lines.sublist(front));
    final keys = widget.headingKeys;
    keys?.clear();
    final painter = _Painter(
      context: context,
      images: widget.images,
      onLink: widget.onLink,
      recognizers: _recognizers,
      headingKeys: keys,
      compact: widget.compact,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (front > 0)
          painter.muted(
            lines.sublist(0, front).join('\n'),
            key: const Key('tom-markdown-front-matter'),
            monospace: true,
          ),
        for (final node in nodes) ...painter.block(node, 0),
      ],
    );
  }
}

class _Painter {
  _Painter({
    required this.context,
    required this.images,
    required this.onLink,
    required this.recognizers,
    required this.headingKeys,
    this.compact = false,
  })  : theme = Theme.of(context),
        scheme = Theme.of(context).colorScheme;

  final BuildContext context;
  final TomMarkdownImageLoader? images;
  final ValueChanged<String>? onLink;
  final List<TapGestureRecognizer> recognizers;
  final List<GlobalKey>? headingKeys;
  final bool compact;
  final ThemeData theme;
  final ColorScheme scheme;

  final Map<String, int> _counts = {};

  /// A key for the next block of [kind]: `tom-markdown-<kind>-<n>`,
  /// numbered from 0 in the order the blocks appear. Numbered because a
  /// document holds many code blocks, tables, comments and images, and
  /// siblings may not share a key.
  Key _key(String kind) {
    final n = _counts[kind] ?? 0;
    _counts[kind] = n + 1;
    return Key('tom-markdown-$kind-$n');
  }

  TextStyle get _body => compact
      ? theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurface)
      : theme.textTheme.bodyLarge!
          .copyWith(color: scheme.onSurface, height: 1.45);

  TextStyle get _mono => _body.copyWith(
      fontFamily: 'monospace',
      fontSize: (_body.fontSize ?? 14) * 0.9,
      height: 1.35);

  Widget muted(String text, {Key? key, bool monospace = false}) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: (monospace ? _mono : theme.textTheme.bodySmall!)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      );

  bool _isComment(String text) => text.trimLeft().startsWith('<!--');

  static final RegExp _detailsOpen = RegExp(
      r'^<details(?:\s[^>]*)?>\s*<summary>(.*?)</summary>\s*$',
      dotAll: true);

  /// `<details><summary>…</summary>` as the label it is — the AI trail writes
  /// one above every tool result — rather than as the tags. The content stays
  /// shown: this view is read-only, and a fold would hide what is being read.
  Widget _summary(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          key: _key('details'),
          children: [
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                label.trim(),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  List<Widget> block(md.Node node, int depth) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isEmpty) return const [];
      if (_detailsOpen.firstMatch(text) case final open?) {
        return [_summary(open.group(1)!)];
      }
      if (text == '</details>') return const [];
      return [
        _isComment(text)
            ? muted(text, key: _key('comment'))
            : muted(text, monospace: true),
      ];
    }
    if (node is! md.Element) return const [];
    final gap = SizedBox(height: compact ? 4 : 10);
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        final key = GlobalKey();
        headingKeys?.add(key);
        final style = (compact
                ? switch (level) {
                    1 => theme.textTheme.titleLarge,
                    2 => theme.textTheme.titleMedium,
                    _ => theme.textTheme.titleSmall,
                  }
                : switch (level) {
                    1 => theme.textTheme.headlineMedium,
                    2 => theme.textTheme.headlineSmall,
                    3 => theme.textTheme.titleLarge,
                    4 => theme.textTheme.titleMedium,
                    _ => theme.textTheme.titleSmall,
                  })!
            .copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600);
        return [
          Padding(
            key: key,
            padding: compact
                ? const EdgeInsets.only(top: 6, bottom: 2)
                : EdgeInsets.only(top: level <= 2 ? 18 : 12, bottom: 6),
            child: Text.rich(TextSpan(
                style: style, children: _inlines(node.children, style))),
          ),
          if (!compact && level <= 2)
            Divider(height: 1, color: scheme.outlineVariant),
          if (!compact && level <= 2) gap,
        ];
      case 'p':
        return [_paragraph(node.children), gap];
      case 'hr':
        return [Divider(color: scheme.outlineVariant), gap];
      case 'blockquote':
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(color: scheme.outlineVariant, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in node.children ?? const <md.Node>[])
                  ...block(c, depth),
              ],
            ),
          ),
        ];
      case 'pre':
        return [_code(node), gap];
      case 'ul' || 'ol':
        return [_list(node, depth), if (depth == 0) gap];
      case 'table':
        return [_table(node), gap];
      default:
        return [_paragraph(node.children), gap];
    }
  }

  Widget _paragraph(List<md.Node>? children) {
    final nodes = children ?? const <md.Node>[];
    // A paragraph that is one image is drawn as the image.
    if (nodes.length == 1 &&
        nodes.single is md.Element &&
        (nodes.single as md.Element).tag == 'img') {
      return _image(nodes.single as md.Element);
    }
    return Text.rich(TextSpan(style: _body, children: _inlines(nodes, _body)));
  }

  Widget _list(md.Element list, int depth) {
    final ordered = list.tag == 'ol';
    var n = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = <Widget>[];
    for (final item in list.children ?? const <md.Node>[]) {
      if (item is! md.Element) continue;
      var children = item.children ?? const <md.Node>[];
      Widget marker;
      final first = children.isEmpty ? null : children.first;
      if (first is md.Element && first.tag == 'input') {
        final checked = first.attributes['checked'] == 'true';
        marker = Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: 18,
          color: checked ? scheme.primary : scheme.onSurfaceVariant,
        );
        children = children.sublist(1);
      } else {
        marker = Text(ordered ? '${n++}.' : '•', style: _body);
      }
      final blocks = <Widget>[];
      final inline = <md.Node>[];
      void flush() {
        if (inline.isEmpty) return;
        blocks.add(_paragraph(List.of(inline)));
        inline.clear();
      }

      for (final c in children) {
        if (c is md.Element &&
            const {'p', 'ul', 'ol', 'pre', 'blockquote', 'table'}
                .contains(c.tag)) {
          flush();
          blocks.addAll(c.tag == 'p'
              ? [_paragraph(c.children)]
              : block(c, depth + 1));
        } else {
          inline.add(c);
        }
      }
      flush();
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Align(alignment: Alignment.topRight, child: marker),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: blocks,
              ),
            ),
          ],
        ),
      ));
    }
    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }

  Widget _code(md.Element pre) {
    final codeNode = (pre.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .firstOrNull;
    final source = (codeNode?.textContent ?? pre.textContent)
        .replaceFirst(RegExp(r'\n$'), '');
    final language =
        codeNode?.attributes['class']?.replaceFirst('language-', '');
    return Container(
      key: _key('code'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(style: _mono, children: _highlight(source, language)),
        ),
      ),
    );
  }

  /// [source] highlighted as [language], or as plain text when the language
  /// is unknown or absent.
  List<InlineSpan> _highlight(String source, String? language) {
    hl.Result result;
    try {
      if (language == null || language.isEmpty) {
        return [TextSpan(text: source)];
      }
      result = hl.highlight.parse(source, language: language);
    } on Object {
      return [TextSpan(text: source)];
    }
    final palette = _palette();
    List<InlineSpan> spans(List<hl.Node>? nodes, String? inherited) => [
          for (final n in nodes ?? const <hl.Node>[])
            if (n.value != null)
              TextSpan(
                text: n.value,
                style: _styleFor(n.className ?? inherited, palette),
              )
            else
              TextSpan(
                style: _styleFor(n.className ?? inherited, palette),
                children: spans(n.children, n.className ?? inherited),
              ),
        ];
    return spans(result.nodes, null);
  }

  /// The code-block palette: the usual syntax hues, each moved in lightness
  /// until it reads at AA on the block's background (wonetestb4) — the
  /// light-theme orange and olive were under 4.5:1 on
  /// `surfaceContainerHighest`.
  Map<String, Color> _palette() {
    final dark = theme.brightness == Brightness.dark;
    final background = scheme.surfaceContainerHighest;
    Color hue(int onDark, int onLight) =>
        tomReadableOn(Color(dark ? onDark : onLight), background);
    return {
      'keyword': hue(0xFFC792EA, 0xFF7B1FA2),
      'built_in': hue(0xFF82AAFF, 0xFF1565C0),
      'type': hue(0xFF82AAFF, 0xFF1565C0),
      'string': hue(0xFFC3E88D, 0xFF2E7D32),
      'number': hue(0xFFF78C6C, 0xFFBF360C),
      'literal': hue(0xFFF78C6C, 0xFFBF360C),
      'comment': scheme.onSurfaceVariant,
      'title': hue(0xFFFFCB6B, 0xFF8D6E00),
      'attr': hue(0xFFFFCB6B, 0xFF8D6E00),
      'meta': scheme.onSurfaceVariant,
    };
  }

  TextStyle? _styleFor(String? className, Map<String, Color> palette) {
    if (className == null) return null;
    final color = palette[className] ?? palette[className.split('.').first];
    if (color == null) return null;
    return TextStyle(
      color: color,
      fontStyle: className == 'comment' ? FontStyle.italic : null,
    );
  }

  Widget _table(md.Element table) {
    final rows = <md.Element>[];
    for (final section in (table.children ?? const <md.Node>[])
        .whereType<md.Element>()) {
      rows.addAll((section.children ?? const <md.Node>[])
          .whereType<md.Element>());
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((r) => (r.children ?? const []).whereType<md.Element>().length)
        .fold(0, (a, b) => a > b ? a : b);
    TextAlign alignOf(md.Element cell) => switch (cell.attributes['align']) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        };
    return SingleChildScrollView(
      key: _key('table'),
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: scheme.outlineVariant),
        children: [
          for (final row in rows)
            TableRow(
              decoration: (row.children ?? const [])
                      .whereType<md.Element>()
                      .any((c) => c.tag == 'th')
                  ? BoxDecoration(color: scheme.surfaceContainerHighest)
                  : null,
              children: [
                for (var i = 0; i < columns; i++)
                  Builder(builder: (context) {
                    final cells =
                        (row.children ?? const []).whereType<md.Element>().toList();
                    if (i >= cells.length) return const SizedBox.shrink();
                    final cell = cells[i];
                    final style = cell.tag == 'th'
                        ? _body.copyWith(fontWeight: FontWeight.w600)
                        : _body;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text.rich(
                        TextSpan(
                            style: style,
                            children: _inlines(cell.children, style)),
                        textAlign: alignOf(cell),
                      ),
                    );
                  }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _image(md.Element img) {
    final src = img.attributes['src'] ?? '';
    final alt = img.attributes['alt'] ?? src;
    Widget fallback() => muted('[image: $alt]');
    final uri = Uri.tryParse(src);
    if (uri == null || src.isEmpty) return fallback();
    if (uri.hasScheme && uri.scheme != 'file') {
      return Image.network(src, errorBuilder: (_, _, _) => fallback());
    }
    final load = images;
    if (load == null) return fallback();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _LoadedImage(
          key: _key('image'),
          load: () => load(Uri.decodeFull(uri.path)),
          fallback: fallback,
        ),
      ),
    );
  }

  List<InlineSpan> _inlines(List<md.Node>? nodes, TextStyle base) {
    final out = <InlineSpan>[];
    for (final node in nodes ?? const <md.Node>[]) {
      out.addAll(_inline(node, base));
    }
    return out;
  }

  List<InlineSpan> _inline(md.Node node, TextStyle base) {
    if (node is md.Text) {
      final text = node.text;
      if (_isComment(text)) {
        return [
          TextSpan(
            text: text,
            style: base.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
              fontSize: (base.fontSize ?? 14) * 0.85,
            ),
          ),
        ];
      }
      // A line break inside a paragraph is a soft break: a space.
      return [TextSpan(text: _unescape(text).replaceAll('\n', ' '))];
    }
    if (node is! md.Element) return const [];
    final children = node.children;
    switch (node.tag) {
      case 'strong':
        final s = base.copyWith(fontWeight: FontWeight.w700);
        return [TextSpan(style: s, children: _inlines(children, s))];
      case 'em':
        final s = base.copyWith(fontStyle: FontStyle.italic);
        return [TextSpan(style: s, children: _inlines(children, s))];
      case 'del':
        final s = base.copyWith(decoration: TextDecoration.lineThrough);
        return [TextSpan(style: s, children: _inlines(children, s))];
      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: _mono.copyWith(
              backgroundColor: scheme.surfaceContainerHighest,
              fontSize: (base.fontSize ?? 14) * 0.9,
            ),
          ),
        ];
      case 'br':
        return [const TextSpan(text: '\n')];
      case 'a':
        final href = node.attributes['href'] ?? '';
        final s = base.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
        );
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onLink?.call(href);
        recognizers.add(recognizer);
        return [
          TextSpan(
            style: s,
            recognizer: recognizer,
            children: [
              for (final c in _inlines(children, s))
                c is TextSpan
                    ? TextSpan(
                        text: c.text,
                        style: c.style,
                        children: c.children,
                        recognizer: recognizer,
                      )
                    : c,
            ],
          ),
        ];
      case 'img':
        return [WidgetSpan(child: _image(node))];
      case 'input':
        final checked = node.attributes['checked'] == 'true';
        return [
          WidgetSpan(
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
            ),
          ),
        ];
      default:
        return _inlines(children, base);
    }
  }

  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

/// An image read once, drawn when its bytes arrive.
class _LoadedImage extends StatefulWidget {
  const _LoadedImage({super.key, required this.load, required this.fallback});

  final Future<Uint8List?> Function() load;
  final Widget Function() fallback;

  @override
  State<_LoadedImage> createState() => _LoadedImageState();
}

class _LoadedImageState extends State<_LoadedImage> {
  late final Future<Uint8List?> _bytes = widget.load().then(
        (bytes) => bytes,
        onError: (Object _) => null,
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return snapshot.connectionState == ConnectionState.done
                ? widget.fallback()
                : const SizedBox(height: 24);
          }
          return Image.memory(
            bytes,
            errorBuilder: (_, _, _) => widget.fallback(),
          );
        },
      );
}
