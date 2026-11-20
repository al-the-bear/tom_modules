# Changelog

## 0.2.0

- `ForgeSessionFile` and `ForgeSessionFileFrame`, taken out of Tom Forge's
  `tom_forge_file_editors`: the binding of an editor's controller to a
  `ForgeFileSession` and the file's state drawn above the editor.
- The frame now shows a file deleted on disk (`ForgeFileSession.deletedOnDisk`;
  a save writes it again). It drew that state only from an external change,
  which the session never sets for a deletion.

## 0.1.0

First version, from the Webwork application's `tom_reusable_ui` package, which is split into nine Tom UI modules in `tom_modules` (`tom_ui_support`, `tom_ui_testing`, `tom_host_ui`, `tom_credentials_ui`, `tom_sync_ui`, `tom_calendar_ui`, `tom_file_editors`, `tom_todo_ui`, `tom_ai_trail_ui`). Type and function names are unchanged; `TomTrailMarkdown` is gone: `TomMarkdownBody` with `compact: true` draws a short text, and `TomMarkdownRendered` is a file's page over it.
