## 1.0.0

The package was `tom_forge_files` in the `tom_forge` repository; it is now
`tom_file_session` in `tom_modules`, with the barrel
`package:tom_file_session/tom_file_session.dart`. Type names are unchanged. It
no longer depends on `tom_forge_core`: `ForgeFileSession` keeps its own
listeners (`addListener`, `removeListener`, `dispose`).

- The editing session of one file over the file-system contract of
  `tom_file_system`: encoding, byte-order mark and line endings written back as
  read, edits as splices, a save that checks the disk first and never writes
  over a changed file, external-change handling (keep mine, take theirs,
  merge), and a history of its own.
- The tree filter: ordered rules, the last match deciding, with the presets
  *All files*, *Text files* and *Tom quest folder*.
- The `.env` codec: entries, commented-out entries, section comments and
  inline comments, edited one line at a time, with a masked rendering.
