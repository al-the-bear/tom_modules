# Changelog

## Unreleased

- Highlighting goes through the one highlighter interface of the new
  package `tom_text_highlight` (re-exported): `TomTextSource.highlighter` is
  a `SyntaxHighlighter` (the `TomSourceHighlighter` function type is gone);
  `tomYamlSourceHighlighter` / `tomMarkdownSourceHighlighter` give the
  source editor's YAML and Markdown highlighters in the Material colours
  (`tomYamlSourceTheme`, `tomMarkdownSourceTheme`), and `tomYamlHighlight` /
  `tomMarkdownHighlight` still answer spans, styled as before. The YAML
  tokenizer is the one Tom Forge's YAML editor uses.
- Fenced code in the Markdown renderer is highlighted by
  `tom_text_highlight` (YAML, Markdown, JSON, shell, `.env`) in the same
  palette; code in another language is plain. The `highlight` package is no
  longer a dependency.
- `ForgeSessionFile` and `ForgeSessionFileFrame` moved to the new package
  `tom_file_session_ui` (Flutter and `tom_file_session` only), which this
  package depends on and re-exports, so its users are unchanged. Tom Forge's
  kit and `tom_forge_shared_ui` take the same implementation instead of a
  copy. `tom_file_session_ui` 0.1.0 is on pub.dev, so this package's staged
  copy takes it as a version (`^0.1.0`).

## 0.2.0

- `ForgeSessionFile` and `ForgeSessionFileFrame`, taken out of Tom Forge's
  `tom_forge_file_editors`: the binding of an editor's controller to a
  `ForgeFileSession` and the file's state drawn above the editor.
- The frame now shows a file deleted on disk (`ForgeFileSession.deletedOnDisk`;
  a save writes it again). It drew that state only from an external change,
  which the session never sets for a deletion.

## 0.1.0

First version, from the Webwork application's `tom_reusable_ui` package, which is split into nine Tom UI modules in `tom_modules` (`tom_ui_support`, `tom_ui_testing`, `tom_host_ui`, `tom_credentials_ui`, `tom_sync_ui`, `tom_calendar_ui`, `tom_file_editors`, `tom_todo_ui`, `tom_ai_trail_ui`). Type and function names are unchanged; `TomTrailMarkdown` is gone: `TomMarkdownBody` with `compact: true` draws a short text, and `TomMarkdownRendered` is a file's page over it.
