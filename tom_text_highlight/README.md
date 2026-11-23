# tom_text_highlight

The one syntax-highlighting interface of the Tom editors, and light
highlighters of our own.

- `SyntaxHighlighter` computes `HighlightSpan`s (offsets, a style and a token
  class) for a source text. A source view applies them in order, a later span
  overriding an earlier one; `highlightedInlineSpans` turns them into
  `InlineSpan`s for a `TextEditingController.buildTextSpan` or a `Text.rich`.
- `TokenHighlighter` is a `SyntaxHighlighter` that tokenizes into token
  classes and styles them with a `HighlightTheme`. The class names follow
  highlight.js (`comment`, `string`, `number`, `literal`, `keyword`, `attr`,
  `meta`, `bullet`, `section`, ...), so a highlight.js-style colour map styles
  them; a dotted class (`literal.boolean`, `punctuation.colon`) falls back to
  its first part when the theme has no entry for it.
- Highlighters: `YamlHighlighter`, `MarkdownHighlighter`, `JsonHighlighter`,
  `ShellHighlighter` and `EnvHighlighter`. `highlighterForLanguage` picks one
  for a fenced code block's language (`yaml`/`yml`, `markdown`/`md`, `json`,
  `bash`/`sh`/`shell`/`zsh`, `env`/`dotenv`); for any other language it asks
  the fallbacks registered with `registerHighlighterFallback`, in order, and
  answers null when none knows it. Nothing is registered by default:
  `tom_highlight_js` registers every highlight.js language for an
  application that wants them (`registerHighlightJsLanguages()`).

It depends on Flutter only, so both Tom Forge's editors and `tom_file_editors`
take it. A heavy highlighter (the Dart analyzer's) is a package of its own
that implements the same interface.

## Tests

`test/` holds a test per highlighter with the tokens of a sample, and the
tests of the theme and the span builder.
