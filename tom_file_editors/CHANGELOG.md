# Changelog

## Unreleased

- `TomTextFileEditor` takes `typingPause` (a typing burst also ends after
  that pause without typing; default none) and `handleFindKey`;
  `TomTextSource.handleFindKey: false` lets the find key pass to a host with
  a find of its own (an application's find bar), the header's find button
  still opening the source's. Tom Forge's plain-text editor is built on
  `TomTextFileEditor` with both.
- The source editor takes over Tom Forge's `TextEditorCore` (removed
  there), so the YAML editor's text mode and subtree inspector draw through
  it:
  - markers (`TomTextMarker`, `TomTextMarkerSeverity`, `tomTextMarkerColor`;
    `TomTextSource.markers`): a wavy underline in the severity's colour over
    the highlighting. Neutral types — an editor maps its own findings onto
    them;
  - the line edits as functions (`TomLineEdits`: delete, duplicate, move up
    and down, toggle the line comment) and, through `TomTextSourceState`,
    the line edits, cut, copy, paste, select all, `select` and `selection`
    for a host to bind to its own keys and menus;
  - a look (`TomTextSource.style`, `TomTextSourceStyle`): text and line
    number styles, background, gutter background, a gutter border, the caret
    colour and the caret's line number drawn brighter;
  - `selection` (text from outside shown with the host's selection),
    `selectionRequest`, `onSelectionChanged`, `onValueChanged`,
    `onFocusLost`; `hostOwnsUndo: false` keeps the text field's own undo for
    a scratch draft, `handleHistoryKeys: false` lets the undo and redo keys
    pass to a host with its own key map.
- `TomTextFileEditor` takes a `highlighter`, `onSelectionChanged`,
  `selectionRequest`, `handleHistoryKeys` and `showReadOnlyReason`; leaving
  the source ends the typing burst. The header still shows the encoding and
  line endings.
- `TomTextSource` gained parameters only; `onChanged` is optional now (null
  for a source nobody edits), so the field `TomTextSource.onChanged` is
  nullable — breaking only for code that reads it from the widget.
- The undo and redo keys reach `onUndo` / `onRedo` when the host gives
  them; a source without them lets the keys pass to its ancestors instead
  of swallowing them.
- Highlighting goes through the one highlighter interface of the new
  package `tom_text_highlight` (re-exported): `TomTextSource.highlighter` is
  a `SyntaxHighlighter` (the `TomSourceHighlighter` function type is gone);
  `tomYamlSourceHighlighter` / `tomMarkdownSourceHighlighter` give the
  source editor's YAML and Markdown highlighters in the Material colours
  (`tomYamlSourceTheme`, `tomMarkdownSourceTheme`), and `tomYamlHighlight` /
  `tomMarkdownHighlight` still answer spans, styled as before. The YAML
  tokenizer is the one Tom Forge's YAML editor uses. `tom_text_highlight`
  0.2.0 is on pub.dev, so this package's staged copy takes it as a version
  (`^0.2.0`).
- Breaking: `TomSourceHighlighter` is removed. pub.dev's latest release is
  0.1.0, so this goes out with the next breaking version (0.2.0, together
  with the 0.2.0 section below, which has not been released either).
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
