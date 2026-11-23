/// Markdown highlighting for the source editor — heading lines,
/// list markers, fences and their code, HTML comments, block quotes, inline
/// code, emphasis and links — through the shared [MarkdownHighlighter] of
/// `tom_text_highlight`.
library;

import 'package:flutter/material.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

/// The source editor's Markdown colours, from the Material [colors].
HighlightTheme tomMarkdownSourceTheme(ColorScheme colors) => HighlightTheme({
  'code.block': TextStyle(color: colors.tertiary),
  'code.inline': TextStyle(
    color: colors.tertiary,
    backgroundColor: colors.surfaceContainerHighest,
  ),
  'comment': TextStyle(
    color: colors.onSurfaceVariant,
    fontStyle: FontStyle.italic,
  ),
  'section': TextStyle(color: colors.primary, fontWeight: FontWeight.w700),
  'quote': TextStyle(color: colors.secondary),
  'bullet': TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
  'strong': const TextStyle(fontWeight: FontWeight.w700),
  'emphasis': const TextStyle(fontStyle: FontStyle.italic),
  'link': TextStyle(color: colors.primary),
});

/// The source editor's Markdown highlighter in [colors].
SyntaxHighlighter tomMarkdownSourceHighlighter(ColorScheme colors) =>
    MarkdownHighlighter(theme: tomMarkdownSourceTheme(colors));

/// Spans covering [text], highlighted as Markdown.
List<InlineSpan> tomMarkdownHighlight(String text, ColorScheme colors) =>
    highlightedInlineSpans(
      text,
      tomMarkdownSourceHighlighter(colors).highlight(text),
    );
