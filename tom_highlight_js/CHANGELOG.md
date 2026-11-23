# Changelog

## 0.1.0

- `HighlightJsHighlighter`: one highlight.js language (through the
  `highlight` package) as a `tom_text_highlight` `TokenHighlighter`, with
  the highlight.js class names the themes already style.
- `registerHighlightJsLanguages()` registers it as a fallback of
  `highlighterForLanguage` for every name and alias highlight.js knows;
  `tom_text_highlight`'s own highlighters stay first.
- Published on pub.dev (with `tom_text_highlight` 0.2.0).
