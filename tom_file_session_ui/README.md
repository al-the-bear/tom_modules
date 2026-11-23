# tom_file_session_ui

The binding of an editor to a `tom_file_session` session, and the frame that
shows the file's state above the editor.

- `ForgeSessionFile` follows a `ForgeFileSession`: it hands the editor's text
  to the session, reports the session's state and changes, and saves through
  it.
- `ForgeSessionFileFrame` draws the file's state above the editor: loading,
  not readable, a refusal, a read-only notice, the file deleted on disk (a
  save writes it again), or a change on disk with the choice between the two
  texts.

It depends on Flutter and `tom_file_session` only. That is why it is a package
of its own: `tom_file_editors` re-exports it, and Tom Forge's layout-free kit
(`tom_forge_kit`, the binding) and `tom_forge_shared_ui` (the frame) take it
without the highlighting, schema and Markdown packages `tom_file_editors`
brings.

## Tests

`test/forge_session_file_test.dart`.
