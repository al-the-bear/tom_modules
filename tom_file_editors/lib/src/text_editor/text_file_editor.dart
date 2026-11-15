/// Any text file in a tab — the source editor and nothing more.
///
/// The text editor's job is to change bytes faithfully: the encoding and the
/// line endings the file had are written back, so the header says
/// what they are, and a file over the session's size limit opens read-only with the
/// reason. No highlighting is invented for an extension the editor does not
/// know.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_file_session/tom_file_session.dart';

import '../file_editor/file_editor_host.dart';
import '../file_editor/session_listenable.dart';
import '../file_editor/text_source.dart';

/// The line endings [text] uses, as the header names them.
String tomLineEndingsOf(String text) {
  final crlf = '\r\n'.allMatches(text).length;
  final lf = '\n'.allMatches(text).length - crlf;
  if (crlf == 0 && lf == 0) return 'No line breaks';
  if (crlf == 0) return 'LF';
  if (lf == 0) return 'CRLF';
  return 'Mixed LF and CRLF';
}

/// The encoding as the header names it.
String tomEncodingLabel(TomTextEncoding encoding) => switch (encoding) {
  TomTextEncoding.utf8 => 'UTF-8',
  TomTextEncoding.utf8Bom => 'UTF-8 with BOM',
  TomTextEncoding.utf16le => 'UTF-16 LE',
  TomTextEncoding.utf16be => 'UTF-16 BE',
  TomTextEncoding.latin1 => 'Latin-1 (read-only)',
};

/// A text file's editor, inside its file tab.
class TomTextFileEditor extends StatefulWidget {
  const TomTextFileEditor({
    super.key,
    required this.host,
  });

  final TomFileEditorHost host;

  @override
  State<TomTextFileEditor> createState() => _TextFileEditorState();
}

class _TextFileEditorState extends State<TomTextFileEditor> {
  final GlobalKey<TomTextSourceState> _source = GlobalKey();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: TomFileSessionListenable(widget.host.session),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final ForgeFileSession session = widget.host.session;
    final theme = Theme.of(context);
    final readOnly = session.readOnlyReason;
    return Column(
      key: const Key('tom-text-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Row(
            children: [
              Text(
                '${tomEncodingLabel(session.encoding)} · '
                '${tomLineEndingsOf(session.text)}',
                key: const Key('tom-text-format'),
                style: theme.textTheme.labelSmall,
              ),
              if (readOnly != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    readOnly,
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                key: const Key('tom-text-find'),
                tooltip: 'Find in file',
                onPressed: () => _source.currentState?.openSearch(),
                icon: const Icon(Icons.search, size: 18),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TomTextSource(
            key: _source,
            text: session.text,
            readOnly: readOnly != null,
            onChanged: (text) =>
                session.edit(text, 'Edit ${widget.host.name}', group: 'typing'),
            onUndo: () => unawaited(widget.host.undo(context)),
            onRedo: () => unawaited(widget.host.redo(context)),
            onSelectionMoved: session.endGesture,
          ),
        ),
      ],
    );
  }
}
