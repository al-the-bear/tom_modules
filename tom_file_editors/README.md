# tom_file_editors

Byte-preserving file editors over a tom_file_session session: the host
interface, the session-file binding and frame for an editor with its own
history, the source editor, the text and .env editors, YAML and Markdown
highlighting, the schema cache, and a Markdown renderer for reading files and
short texts.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| File editor host | `lib/src/file_editor/` | What a file editor asks of the application: the file's `tom_file_session` session, its name and path, undo and redo routed through the application, a notice, the protected clipboard (`TomFileEditorHost`). The source editor every file editor edits in (`TomTextSource`: monospaced, line numbers, highlighting, find, undo and redo reaching the host), the session as a `Listenable` (`TomFileSessionListenable`), the YAML highlighter (`tomYamlHighlight`, in `lib/src/yaml_editor/`), and the schema cache (`TomSchemaCache` — the schema a file names in its `# yaml-language-server: $schema=` comment, resolved against the file and compiled once). |
| Session file | re-exported from `tom_file_session_ui` (one implementation, which Tom Forge's kit and shared UI take too) | For an editor whose controller keeps the document's history (Tom Forge's Markdown, YAML, `.env` and todo editors): `ForgeSessionFile` binds the controller to the `ForgeFileSession` — the controller sees `\n` line endings, a CRLF file is written back with CRLF, a save does not write over a file changed on disk — and `ForgeSessionFileFrame` draws the file's state above the editor: loading, missing, refused with the reason, the read-only notice, deleted on disk (a save writes it again), or changed on disk with *Keep mine* and *Take theirs*. |
| Text editor | `lib/src/text_editor/` | Any text file (`TomTextFileEditor`): the header names the encoding and line endings the session writes back (`tomEncodingLabel`, `tomLineEndingsOf`); a file over the session's size limit is read-only with the reason. |
| `.env` editor | `lib/src/env_editor/` | A `.env` file as a table of entries (`TomEnvFileEditor`) over `tom_file_session`' codec: section headings, commented-out entries by their checkbox, every edit one line. **Show values** is off on every open; a hidden value is a link offering *Copy* through the host's protected clipboard, *Show* for that one value and *Edit…* in a masked field; the raw view is masked and read-only while the switch is off. No value reaches a label, a history entry, a notice or an error. |
| Markdown rendering | `lib/src/markdown_editor/` | One Markdown renderer for a file and a short text: `TomMarkdownRendered`, a file drawn for reading — the GitHub-flavoured AST with front matter and HTML comments kept visible; an image on the web is fetched and any other read through a callback; an anchor link scrolls and every other link is the caller's — and `TomMarkdownBody`, the body alone, in the document style or `compact` for a model's answer or a todo's notes. The outline of a file's headings (`tomMarkdownOutline`) and the Markdown highlighter (`tomMarkdownHighlight`). |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_file_editors/tom_file_editors.dart` | everything above | all (no `dart:io`) |

## Dependencies

Flutter, `highlight`, `json_schema`, `markdown`, `path`, `tom_basics`, `tom_file_session`, `tom_ui_support`.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:tom_file_system/io.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_editors/tom_file_editors.dart';

class NotesHost implements TomFileEditorHost {
  NotesHost(this.session, this.clipboard);
  @override
  final ForgeFileSession session;
  final Future<void> Function(String) clipboard;
  @override
  String get name => session.path.split('/').last;
  @override
  String get filePath =>
      session.fileSystem.root.resolve(session.path).toFilePath();
  @override
  Future<void> undo(BuildContext context) => session.undo();
  @override
  Future<void> redo(BuildContext context) => session.redo();
  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  @override
  Future<void> copyProtected(String value) => clipboard(value);
}

Future<Widget> openEnv(String folder) async {
  final session = ForgeFileSession(
      fileSystem: TomLocalFileSystem(folder), path: '.env');
  await session.load();
  return TomEnvFileEditor(host: NotesHost(session, (v) async {}));
}
```

## Tests

`flutter test` from this folder.
