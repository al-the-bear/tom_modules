/// Any text file in a tab — the source editor and nothing more.
///
/// The text editor's job is to change bytes faithfully: the encoding and the
/// line endings the file had are written back, so the header says
/// what they are, and a file over the session's size limit opens read-only with the
/// reason. No highlighting is invented for an extension the editor does not
/// know: a host that knows one passes its highlighter.
///
/// An application that hosts the editor in a shell of its own reaches what
/// it needs through the editor's arguments: the selection the user leaves
/// ([TomTextFileEditor.onSelectionChanged]), selections it asks for
/// ([TomTextFileEditor.selectionRequest]), and the history keys routed
/// through its own key map ([TomTextFileEditor.handleHistoryKeys]), the find
/// key left to its own find ([TomTextFileEditor.handleFindKey]), and a typing
/// burst that also ends after a pause ([TomTextFileEditor.typingPause]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

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
    this.highlighter,
    this.onSelectionChanged,
    this.selectionRequest,
    this.handleHistoryKeys = true,
    this.handleFindKey = true,
    this.showReadOnlyReason = true,
    this.typingPause,
  });

  final TomFileEditorHost host;

  /// The file kind's highlighting; none for plain text.
  final SyntaxHighlighter? highlighter;

  /// The selection the user left, after every change of it or of the text
  /// ([TomTextSource.onSelectionChanged]).
  final ValueChanged<TextSelection>? onSelectionChanged;

  /// Selections the application asks the source to show
  /// ([TomTextSource.selectionRequest]).
  final ValueListenable<TextSelection?>? selectionRequest;

  /// Whether the source answers the undo and redo keys itself through the
  /// host (the default); false for an application that routes them through
  /// its own key map ([TomTextSource.handleHistoryKeys]).
  final bool handleHistoryKeys;

  /// Whether the find key opens the source's own find bar (the default);
  /// false for an application with a find of its own on that key
  /// ([TomTextSource.handleFindKey]). The header's find button opens the
  /// source's either way.
  final bool handleFindKey;

  /// How long typing may pause before the burst in progress ends; null (the
  /// default): only a caret move or leaving the source ends it. An
  /// application whose other editors end a burst after a pause passes theirs,
  /// so typing, pausing and typing again is two history entries everywhere.
  final Duration? typingPause;

  /// Whether the header names why the file is read-only (the default);
  /// false for an application whose frame says it already.
  final bool showReadOnlyReason;

  @override
  State<TomTextFileEditor> createState() => _TextFileEditorState();
}

class _TextFileEditorState extends State<TomTextFileEditor> {
  final GlobalKey<TomTextSourceState> _source = GlobalKey();

  /// Ends the typing burst once [TomTextFileEditor.typingPause] has passed
  /// without typing.
  Timer? _pause;

  @override
  void dispose() {
    _pause?.cancel();
    super.dispose();
  }

  void _typed(ForgeFileSession session, String text) {
    session.edit(text, 'Edit ${widget.host.name}', group: 'typing');
    final pause = widget.typingPause;
    if (pause == null) return;
    _pause?.cancel();
    _pause = Timer(pause, session.endGesture);
  }

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
              if (readOnly != null && widget.showReadOnlyReason) ...[
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
            onChanged: (text) => _typed(session, text),
            onUndo: () => unawaited(widget.host.undo(context)),
            onRedo: () => unawaited(widget.host.redo(context)),
            onSelectionMoved: session.endGesture,
            onFocusLost: session.endGesture,
            onSelectionChanged: widget.onSelectionChanged,
            selectionRequest: widget.selectionRequest,
            handleHistoryKeys: widget.handleHistoryKeys,
            handleFindKey: widget.handleFindKey,
            highlighter: widget.highlighter,
          ),
        ),
      ],
    );
  }
}
