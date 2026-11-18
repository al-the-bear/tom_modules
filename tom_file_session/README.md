# tom_file_session

Published on pub.dev as [`tom_file_session` 1.3.0](https://pub.dev/packages/tom_file_session).

What an editor and a file browser build on the file-system contract of
`tom_file_system`: the editing session of one file, the filter that decides
what a file tree shows, and the `.env` codec. For hosts with `dart:io`, it
adds the save rules for binary files and a local content server that hands
files to a webview.

## Entry points

| Library | Holds | Runs on |
| --- | --- | --- |
| `package:tom_file_session/tom_file_session.dart` | `ForgeFileSession`, `ForgeFilter` with `ForgeBuiltInPresets`, `ForgeEnvFile`, the `TomBinaryFiles` interface and its value types, `TomFileSystemBinaryFiles` | everywhere: no `dart:io`, no Flutter, so a browser build links it |
| `package:tom_file_session/io.dart` | `TomBinaryFileAccess`, `TomLocalContentServer` | the VM (desktop, server): it uses `dart:io` |

## Components

### The editing session — `ForgeFileSession`

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
  burst (`group`; `endGesture` ends a burst), at most a thousand unless the
  host sets `historyDepth`. `adoptText` takes content from outside the
  history (a revision restore) as the saved text and clears the history. An act that already wrote to disk —
  moving a todo between files, say — joins it as a `ForgeFileDiskAct`.
- **Limits.** Larger than 2 MiB opens read-only; larger than 50 MiB, binary,
  or unreadable does not open, and says why. What counts as binary is the
  caller's (`isBinary`); by default a file that does not look like text.

Listeners added with `addListener` hear every change of the session's text,
state or history, without being told which; `dispose` drops them. A Flutter
host wraps the session in a `Listenable` of its own.

### The tree filter — `ForgeFilter`

An ordered list of rules — include or exclude a glob, an extension set, hidden
entries, gitignored entries, the archived and deleted siblings of todo files —
and the **last** rule that matches an entry decides; an entry no rule matches
is shown. A hidden or gitignored folder hides everything inside it
(`hidesSubtree`). Rules and filters encode to and decode from plain maps, so a
filter is stored as settings.

`ForgeBuiltInPresets` holds three: *All files*, *Text files* and *Tom quest
folder*. The hiding rules close each list, because with the last match
deciding a later `include` would otherwise show what they hide.

### The `.env` codec — `ForgeEnvFile`

A `.env` file as entries, commented-out entries, section comments and inline
comments. An edit — a value, a rename, a toggle, a delete, an add — changes
one line, keeping its quotes, `export` and comment; every other line stays as
it was. `masked()` renders the file with every value hidden, for a view that
must not show them.

### Binary saves — `TomBinaryFileAccess` (`io.dart`)

The session's save rules for files an editor never holds as text — office
documents, PDFs — written by a helper process or received as bytes:

- **Revision.** `revisionOf(path)` gives the size, modification time and
  SHA-256 (streamed, so a large file is not read at once), or `null` when
  there is no file. Whether a file changed for a save is decided by its bytes
  (`sameContent`): a touched file is still the one read.
- **Temporary target.** `temporaryTarget(path)` creates `.<name>.tom-save-<n>`
  in the same folder, so the final rename is atomic and stays on one volume.
- **Replace.** `replace(original, temp, expectedRevision)` renames the
  temporary file over an unchanged original, keeping its permissions, and
  returns the new revision. A changed or deleted original (or one that
  appeared where none was expected, `expectedRevision` `null`) is a
  `conflict`: nothing is written and the temporary file is kept for the
  conflict choice. `save(path, bytes, expectedRevision)` does both steps for
  bytes in memory. `force: true` replaces whatever is there (*keep mine*);
  `keepAsCopy` renames the temporary file to `<name> (copy).<ext>` beside the
  original; `isWritable` says whether the file can be written.
- **Interface.** `TomBinaryFiles` in the main library describes these rules
  without `dart:io`, so a widget library takes them from its host;
  `TomBinaryFileAccess` is its `dart:io` implementation.
- **Files without a local path.** `TomFileSystemBinaryFiles` (main library)
  implements the same rules over a `TomFileSystem` (paths relative to its
  root): the temporary target `.<name>.tom-save-<n>` is a file of the file
  system, `replace` writes with the expected revision (a file changed since is
  a conflict), *keep as copy* writes `<stem> (copy).<ext>`. It is a
  `TomBinaryFileBytes`, which adds `readBytes(path)`: a host that gets one
  opens its documents from bytes instead of a path.
- **Clean-up.** `removeTemporaryFiles(path)` deletes the temporary files left
  beside a file, and nothing else.

```dart
const files = TomBinaryFileAccess();
final read = await files.revisionOf(path);
// ... the helper writes the document to files.temporaryTarget(path) ...
final result = await files.replace(path, temporary, read);
if (!result.replaced) {
  // Changed on disk: offer keep mine / take theirs / save as copy.
}
```

### The local content server — `TomLocalContentServer` (`io.dart`)

An `HttpServer` on `127.0.0.1`, on a free port, in the application's own
process, that serves a webview what it cannot load from `file://`: module
workers, WebAssembly, range requests, cross-origin isolation.

- **Sites and tokens.** Each user opens a `TomContentSite`
  (`TomLocalContentServer.shared.openSite()`) with a random 128-bit token that
  begins every path: `http://127.0.0.1:<port>/<token>/<prefix>/<path>`. An
  unknown token, or a `Host` other than `127.0.0.1` / `localhost`, is refused.
  The server starts with the first site and stops when the last one closes.
- **Mounts** (`TomContentMount`), each under a path prefix, the longest
  matching prefix answering:
  - `folder` — a folder's files; a path out of the folder (`..`, a link
    pointing out) is refused. With `precompressed`, a missing `<name>` is
    served from `<name>.br` with `Content-Encoding: br`, the type of `<name>`
    and never as a partial answer;
  - `file` — one file, at the prefix or under any name after it;
  - `assets` — bytes from a loader, such as a Flutter asset bundle;
  - `receiver` — takes the bytes a page POSTs (the saved document).
- **Range requests.** `folder`, `file` and `assets` answer a single
  `Range: bytes=…` with `206`, an unsatisfiable one with `416`.
- **Headers.** The MIME type by extension (`.mjs`, `.wasm`, `.pdf`, `.data`,
  the office types, …; `mimeTypeOf`), `Cache-Control: no-store`, and per
  mount (`isolated`) the cross-origin isolation headers: COOP `same-origin`,
  COEP `require-corp`, CORP `same-origin`.

```dart
final site = await TomLocalContentServer.shared.openSite();
site.mount('zeta', TomContentMount.folder(cache, isolated: true, precompressed: true));
site.mount('doc', TomContentMount.file(documentPath, isolated: true));
site.mount('save', TomContentMount.receiver((c) => onSaved(c.bytes)));
await webview.loadUrl(site.uriOf('host/zeta.html'));
// ... when the tab closes:
await site.close();
```

## License

BSD-3-Clause — See [LICENSE](LICENSE) for details.
