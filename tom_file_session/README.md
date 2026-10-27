# tom_file_session

Published on pub.dev as [`tom_file_session` 1.0.0](https://pub.dev/packages/tom_file_session).

What an editor and a file browser build on the file-system contract of
`tom_file_system`: the editing session of one file, the filter that decides
what a file tree shows, and the `.env` codec. Pure Dart: no `dart:io`, no
Flutter, so a browser build links it.

```dart
import 'package:tom_file_system/io.dart';
import 'package:tom_file_session/tom_file_session.dart';

final fs = TomLocalFileSystem('/path/to/folder');
final session = ForgeFileSession(fileSystem: fs, path: 'notes/today.md');
await session.load();
session.edit('${session.text}- one more line\n', 'Append');
if (await session.save() == ForgeFileSaveOutcome.conflict) {
  // Changed on disk since it was read: session.external holds theirs.
}
```

## The editing session — `ForgeFileSession`

One file, read once and edited in memory, shared by every view of it:

- **Bytes.** Decoded once — UTF-8, UTF-8 behind a byte-order mark, or UTF-16
  behind its mark — and written back in the same encoding. Every edit is a
  splice into the decoded text, so the line endings and every byte outside the
  edit stay as they were. Opening never writes.
- **Save.** Before writing, the disk is checked; a file that changed since it
  was read is never written over (`ForgeFileSaveOutcome.conflict`), because
  the write carries the revision it was read at.
- **External changes.** `checkExternal` compares the disk with what was read:
  a clean session reloads with a notice, a dirty one holds the other version
  (`external`) for *keep mine*, *take theirs* or a merged save
  (`saveMerged`). A file deleted on disk is marked; a save recreates it.
- **History.** Undo and redo of its own, one entry per edit or per typing
  burst (`group`), at most a thousand. An act that already wrote to disk —
  moving a todo between files, say — joins it as a `ForgeFileDiskAct`.
- **Limits.** Larger than 2 MiB opens read-only; larger than 50 MiB, binary,
  or unreadable does not open, and says why. What counts as binary is the
  caller's (`isBinary`); by default a file that does not look like text.

Listeners added with `addListener` hear every change of the session's text,
state or history, without being told which; `dispose` drops them. A Flutter
host wraps the session in a `Listenable` of its own.

## The tree filter — `ForgeFilter`

An ordered list of rules — include or exclude a glob, an extension set, hidden
entries, gitignored entries, the archived and deleted siblings of todo files —
and the **last** rule that matches an entry decides; an entry no rule matches
is shown. A hidden or gitignored folder hides everything inside it
(`hidesSubtree`). Rules and filters encode to and decode from plain maps, so a
filter is stored as settings.

`ForgeBuiltInPresets` holds three: *All files*, *Text files* and *Tom quest
folder*. The hiding rules close each list, because with the last match
deciding a later `include` would otherwise show what they hide.

## The `.env` codec — `ForgeEnvFile`

A `.env` file as entries, commented-out entries, section comments and inline
comments. An edit — a value, a rename, a toggle, a delete, an add — changes
one line, keeping its quotes, `export` and comment; every other line stays as
it was. `masked()` renders the file with every value hidden, for a view that
must not show them.

## License

BSD-3-Clause — See [LICENSE](LICENSE) for details.
