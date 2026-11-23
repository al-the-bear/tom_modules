/// YAML highlighting for the source editor — comments, keys,
/// sequence dashes, document markers and quoted strings — through the shared
/// [YamlHighlighter] of `tom_text_highlight`.
library;

import 'package:flutter/material.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

/// The source editor's YAML colours, from the Material [colors]: keys in
/// the primary colour, comments muted and italic, dashes and document
/// markers in the secondary colour, quoted strings in the tertiary one.
/// Everything else keeps the editor's text colour.
HighlightTheme tomYamlSourceTheme(ColorScheme colors) => HighlightTheme({
  'attr': TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
  'comment': TextStyle(
    color: colors.onSurfaceVariant,
    fontStyle: FontStyle.italic,
  ),
  'bullet': TextStyle(color: colors.secondary),
  'meta': TextStyle(color: colors.secondary),
  'string': TextStyle(color: colors.tertiary),
});

/// The source editor's YAML highlighter in [colors], for
/// [TomTextSource.highlighter](../file_editor/text_source.dart).
SyntaxHighlighter tomYamlSourceHighlighter(ColorScheme colors) =>
    YamlHighlighter(theme: tomYamlSourceTheme(colors));

/// Spans covering [text], highlighted as YAML.
List<InlineSpan> tomYamlHighlight(String text, ColorScheme colors) =>
    highlightedInlineSpans(
      text,
      tomYamlSourceHighlighter(colors).highlight(text),
    );
