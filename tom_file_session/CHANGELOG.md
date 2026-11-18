## 1.8.0

- `TomFileSystemBinaryFiles`: the binary save rules (`TomBinaryFiles`) over
  a `TomFileSystem`, for files without a local path — revisions from the
  file system, the temporary target `.<name>.tom-save-<n>` beside the file,
  a replace written with the expected revision (a changed file is a
  conflict), *keep as copy* as `<stem> (copy).<ext>`.
- `TomBinaryFileBytes`: a `TomBinaryFiles` that also reads a file's bytes
  (`readBytes`); a host takes it as the sign to open a document from bytes.

## 1.7.0

- `TomContentSite.onRequest` tells a host of every request the site
  answered as a `TomContentRequest` (method, the path below the token,
  status, bytes), for a debug trail; the token is never part of it.

## 1.6.0

- The main library gains `TomBinaryFiles`, the binary save rules as an
  interface, with the value types `TomFileRevision`,
  `TomBinaryReplaceOutcome` and `TomBinaryReplaceResult` (moved from
  `io.dart`, which still exports them), so a widget library without
  `dart:io` can take file access from its host.
- `TomBinaryFileAccess` implements it and adds `replace(..., force: true)`
  (*keep mine*), `keepAsCopy` (the temporary file renamed to
  `<name> (copy).<ext>`) and `isWritable`.

## 1.5.0

- Adds `package:tom_file_session/io.dart`, for hosts with `dart:io`; the main
  library stays free of it.
  - `TomBinaryFileAccess`: binary saves by the session's rules — the revision
    (size, modification time, SHA-256), a temporary target in the same
    folder, a replace over an unchanged original that keeps its permissions
    (otherwise a conflict that keeps the temporary file), and the clean-up of
    leftover temporary files.
  - `TomLocalContentServer` with `TomContentSite` and `TomContentMount`: a
    local HTTP server on `127.0.0.1` for webviews — a token per site, folder,
    file, asset and receiver mounts, range requests, pre-compressed `.br`
    files, cross-origin isolation headers per mount; it stops when the last
    site closes.
- Depends on `crypto` ^3.0.0.

## 1.4.0

- Takes `tom_todo_model` ^3.0.0 (todo groups: the status `group` and
  `comprised_of`). This package only names todo files, but with ^2.x it kept
  every package that depends on it on a model that refuses a group todo.

## 1.3.0

- Takes `tom_todo_model` ^2.0.0 (repeated todos). This package only names
  todo files (`TomTodoFileName` for the `todoSiblings` filter rule), but with
  ^1.x it kept every package that depends on it and on the 2.x model from
  resolving.

## 1.2.1

- Takes `tom_todo_model` ^1.3.0: a reader of todo files takes the model's
  newest fields (`user_action`, `blocking`, `last_answer`), so a fresh
  resolution never picks a model that reports them as unknown keys.

## 1.2.0

- `ForgeFileSession.historyDepth`: the number of entries the history keeps,
  settable by a host that follows its editor's undo-depth setting; lowering
  it drops the oldest entries at once.

## 1.1.0

- `ForgeFileSession.endGesture`: the typing burst in progress ends (the
  caret moved, the editor lost focus), so the next edit starts a new entry.
- `ForgeFileSession.adoptText`: content from outside the session's history
  (a revision restore) becomes the saved text and clears the history; the
  revision is learned from the file when it holds that text.

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
