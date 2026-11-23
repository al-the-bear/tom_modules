# Changelog

## 0.1.0

- `SyntaxHighlighter` and `HighlightSpan`, moved here from Tom Forge's
  `tom_editors_shared` (which re-exports them for one release), so that the
  Forge editors and `tom_file_editors` highlight through one interface.
- `HighlightTheme` (token class to style, with dotted fallback),
  `TokenHighlighter` (a tokenizer styled by a theme) and
  `highlightedInlineSpans` (spans to `InlineSpan`s for a text field or
  `Text.rich`).
- Highlighters for YAML (`YamlHighlighter`, the merge of the YAML editor's
  and `tom_file_editors`' two), Markdown, JSON, shell and `.env`, and
  `highlighterForLanguage` for a fenced code block's language name.
- Published on pub.dev; `tom_file_editors` takes it as a version from its
  staged copy.
