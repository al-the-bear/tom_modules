// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/material.dart';

/// Asks for a note's text; `null` when cancelled. [initial] is the text of a
/// note being edited.
Future<String?> showPdfNoteDialog(
  BuildContext context, {
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _NoteDialog(initial: initial),
);

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial.isEmpty ? 'New note' : 'Edit note'),
    content: SizedBox(
      width: 360,
      child: TextField(
        key: const ValueKey('pdf-note-text'),
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('pdf-note-ok'),
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('OK'),
      ),
    ],
  );
}
