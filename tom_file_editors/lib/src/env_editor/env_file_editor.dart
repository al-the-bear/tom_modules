/// A `.env` file as a table of its entries, values hidden behind
/// one switch.
///
/// **Show values** is off whenever the file is opened. While it is off a
/// value is a three-dot link — *Copy* through the protected clipboard, *Show*
/// for that one value, *Edit…* in a masked field — and the raw view is masked
/// and read-only, so there is no route to a value in clear that does not pass
/// the switch or a deliberate *Show*. No value reaches a label, a history
/// entry, a notice or an error.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tom_file_session/tom_file_session.dart';

import '../file_editor/file_editor_host.dart';
import '../file_editor/session_listenable.dart';
import '../file_editor/text_source.dart';

/// The mask a hidden value is shown as.
const String tomEnvMask = '•••';

/// A `.env` file's editor, inside its file tab.
class TomEnvFileEditor extends StatefulWidget {
  const TomEnvFileEditor({
    super.key,
    required this.host,
  });

  final TomFileEditorHost host;

  @override
  State<TomEnvFileEditor> createState() => _EnvEditorState();
}

class _EnvEditorState extends State<TomEnvFileEditor> {
  /// off on every open — this state is new per opened tab.
  bool _showValues = false;
  bool _raw = false;

  /// Values shown one at a time, by key, until the switch changes.
  final Set<String> _shown = {};

  String? _parsedText;
  ForgeEnvFile? _env;

  ForgeFileSession get _session => widget.host.session;

  ForgeEnvFile _parse(String text) {
    if (_parsedText != text) {
      _parsedText = text;
      _env = ForgeEnvFile.parse(text);
    }
    return _env!;
  }

  void _setShowValues(bool on) => setState(() {
    _showValues = on;
    _shown.clear();
  });

  void _edit(String text, String label) {
    try {
      _session.edit(text, label);
    } on StateError catch (e) {
      _say(e.message);
    }
  }

  void _say(String text) => widget.host.notice(context, text, kind: 'env-file');

  Future<void> _copy(ForgeEnvLine line) async {
    await widget.host.copyProtected(line.value);
    if (mounted) _say('Copied the value of ${line.key}.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: TomFileSessionListenable(_session),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final session = _session;
    final env = _parse(session.text);
    final readOnly = session.readOnlyReason != null;
    return Column(
      key: const Key('tom-env-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, readOnly),
        if (env.unreadableLines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              // Line numbers only: a line's text may be a value.
              'Not readable as an entry: line '
              '${env.unreadableLines.join(', ')}.',
              key: const Key('tom-env-unreadable'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _raw
              ? _rawView(env, readOnly)
              : _table(context, env, readOnly),
        ),
      ],
    );
  }

  // A Wrap, not a Row: in a narrow pane the switch and the button go to the
  // next line instead of off the edge.
  Widget _header(BuildContext context, bool readOnly) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        SegmentedButton<bool>(
          key: const Key('tom-env-view'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Table')),
            ButtonSegment(value: true, label: Text('Raw')),
          ],
          selected: {_raw},
          onSelectionChanged: (v) => setState(() => _raw = v.first),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Show values'),
            Switch(
              key: const Key('tom-env-show-values'),
              value: _showValues,
              onChanged: _setShowValues,
            ),
          ],
        ),
        if (!_raw)
          FilledButton.tonalIcon(
            key: const Key('tom-env-add'),
            onPressed: readOnly ? null : () => unawaited(_add(context)),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add entry'),
          ),
      ],
    ),
  );

  Widget _rawView(ForgeEnvFile env, bool readOnly) {
    if (!_showValues) {
      return TomTextSource(
        key: const ValueKey('masked'),
        text: env.masked(),
        readOnly: true,
        onChanged: (_) {},
      );
    }
    return TomTextSource(
      key: const ValueKey('raw'),
      text: env.text,
      readOnly: readOnly,
      onChanged: (text) =>
          _session.edit(text, 'Edit ${widget.host.name}', group: 'typing'),
      onUndo: () => unawaited(widget.host.undo(context)),
      onRedo: () => unawaited(widget.host.redo(context)),
      onSelectionMoved: _session.endGesture,
    );
  }

  Widget _table(BuildContext context, ForgeEnvFile env, bool readOnly) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final line in env.lines) {
      switch (line.kind) {
        case ForgeEnvLineKind.blank:
          rows.add(const SizedBox(height: 12));
        case ForgeEnvLineKind.section:
          rows.add(
            Padding(
              key: Key('tom-env-section-${line.index}'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                line.comment,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          );
        case ForgeEnvLineKind.unreadable:
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                'Line ${line.index + 1} is not an entry.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          );
        case ForgeEnvLineKind.entry || ForgeEnvLineKind.commented:
          rows.add(
            _EnvRow(
              key: ValueKey('tom-env-row-${line.index}'),
              line: line,
              reveal: _showValues || _shown.contains(line.key),
              readOnly: readOnly,
              onShow: () => setState(() => _shown.add(line.key)),
              onCopy: () => unawaited(_copy(line)),
              onEditValue: () => unawaited(_editValue(context, env, line)),
              onValue: (value) => _edit(
                env.withValue(line.index, value),
                'Edit the value of ${line.key}',
              ),
              onKey: (key) {
                try {
                  _edit(
                    env.withKey(line.index, key),
                    'Rename ${line.key} to $key',
                  );
                } on ArgumentError {
                  // Not echoed: what was typed may be a pasted value.
                  _say('A key is letters, digits, "_", "." and "-", and does '
                      'not start with a digit; ${line.key} was kept.');
                }
              },
              onToggle: () => _edit(
                env.withToggled(line.index),
                line.kind == ForgeEnvLineKind.entry
                    ? 'Comment out ${line.key}'
                    : 'Activate ${line.key}',
              ),
              onDelete: () =>
                  _edit(env.withoutLine(line.index), 'Delete ${line.key}'),
            ),
          );
      }
    }
    return ListView(
      key: const Key('tom-env-table'),
      padding: const EdgeInsets.only(bottom: 24),
      children: rows,
    );
  }

  Future<void> _editValue(
    BuildContext context,
    ForgeEnvFile env,
    ForgeEnvLine line,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _ValueDialog(
        title: 'Value of ${line.key}',
        initial: line.value,
        masked: !_showValues && !_shown.contains(line.key),
      ),
    );
    if (value == null || !mounted) return;
    final current = _parse(_session.text);
    final now = current.lines.where((l) => l.key == line.key && l.isEntry);
    if (now.isEmpty) return;
    _edit(
      current.withValue(now.first.index, value),
      'Edit the value of ${line.key}',
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _AddDialog(masked: !_showValues),
    );
    if (result == null || !mounted) return;
    final env = _parse(_session.text);
    if (env.entries.any((e) => e.key == result.$1)) {
      _say('${result.$1} is already in this file.');
      return;
    }
    _edit(env.withAdded(result.$1, result.$2), 'Add ${result.$1}');
  }
}

/// One entry: its key, its value (or the three-dot link), and its actions.
class _EnvRow extends StatelessWidget {
  const _EnvRow({
    super.key,
    required this.line,
    required this.reveal,
    required this.readOnly,
    required this.onShow,
    required this.onCopy,
    required this.onEditValue,
    required this.onValue,
    required this.onKey,
    required this.onToggle,
    required this.onDelete,
  });

  final ForgeEnvLine line;
  final bool reveal;
  final bool readOnly;
  final VoidCallback onShow;
  final VoidCallback onCopy;
  final VoidCallback onEditValue;
  final ValueChanged<String> onValue;
  final ValueChanged<String> onKey;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = line.kind == ForgeEnvLineKind.entry;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: active ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
      fontStyle: active ? null : FontStyle.italic,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Tooltip(
            message: active ? 'Comment out' : 'Activate',
            child: Checkbox(
              key: Key('tom-env-active-${line.key}'),
              value: active,
              onChanged: readOnly ? null : (_) => onToggle(),
            ),
          ),
          SizedBox(
            width: 220,
            child: _CommitText(
              key: Key('tom-env-key-${line.key}'),
              value: line.key,
              style: mono.copyWith(fontWeight: FontWeight.w600),
              enabled: !readOnly,
              onCommit: onKey,
            ),
          ),
          const Text(' = '),
          Expanded(
            child: reveal
                ? _CommitText(
                    key: Key('tom-env-value-${line.key}'),
                    value: line.value,
                    style: mono,
                    enabled: !readOnly,
                    onCommit: onValue,
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<int>(
                      key: Key('tom-env-hidden-${line.key}'),
                      tooltip: 'Value hidden',
                      onSelected: (choice) => switch (choice) {
                        0 => onCopy(),
                        1 => onShow(),
                        _ => onEditValue(),
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          key: Key('tom-env-copy-${line.key}'),
                          value: 0,
                          child: const Text('Copy'),
                        ),
                        PopupMenuItem(
                          key: Key('tom-env-show-${line.key}'),
                          value: 1,
                          child: const Text('Show'),
                        ),
                        if (!readOnly)
                          PopupMenuItem(
                            key: Key('tom-env-edit-${line.key}'),
                            value: 2,
                            child: const Text('Edit…'),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          line.value.isEmpty ? '(empty)' : tomEnvMask,
                          style: mono.copyWith(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          // The comment column: one width for every row, so the actions
          // line up whether or not a row has a comment.
          SizedBox(
            width: 240,
            child: line.comment.isEmpty
                ? null
                : Text(
                    '# ${line.comment}',
                    key: Key('tom-env-comment-${line.key}'),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
          if (reveal)
            IconButton(
              tooltip: 'Copy',
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 16),
            ),
          IconButton(
            key: Key('tom-env-delete-${line.key}'),
            tooltip: 'Delete',
            onPressed: readOnly ? null : onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

/// A text field that reports its value when committed (Enter or leaving it).
class _CommitText extends StatefulWidget {
  const _CommitText({
    super.key,
    required this.value,
    required this.style,
    required this.enabled,
    required this.onCommit,
  });

  final String value;
  final TextStyle style;
  final bool enabled;
  final ValueChanged<String> onCommit;

  @override
  State<_CommitText> createState() => _CommitTextState();
}

class _CommitTextState extends State<_CommitText> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_CommitText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _text.text != widget.value) {
      _text.text = widget.value;
    }
  }

  void _commit() {
    if (_text.text == widget.value) return;
    widget.onCommit(_text.text);
    // A refused commit leaves the file as it was: the field shows the file
    // again rather than keeping what was typed, which may be a pasted value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _text.text != widget.value) _text.text = widget.value;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    enabled: widget.enabled,
    style: widget.style,
    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
    onSubmitted: (_) => _commit(),
  );
}

/// A value edited in a field that is masked while values are hidden.
class _ValueDialog extends StatefulWidget {
  const _ValueDialog({
    required this.title,
    required this.initial,
    required this.masked,
  });

  final String title;
  final String initial;
  final bool masked;

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final TextEditingController _value = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('tom-env-value-dialog'),
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        key: const Key('tom-env-value-field'),
        controller: _value,
        obscureText: widget.masked,
        autofocus: true,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('tom-env-value-save'),
        onPressed: () => Navigator.pop(context, _value.text),
        child: const Text('Apply'),
      ),
    ],
  );
}

/// A new entry: its key, and its value in a masked field while values are
/// hidden.
class _AddDialog extends StatefulWidget {
  const _AddDialog({required this.masked});

  final bool masked;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _value = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = forgeIsEnvKey(_key.text.trim());
    return AlertDialog(
      key: const Key('tom-env-add-dialog'),
      title: const Text('Add entry'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('tom-env-add-key'),
              controller: _key,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Key'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('tom-env-add-value'),
              controller: _value,
              obscureText: widget.masked,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('tom-env-add-confirm'),
          onPressed: valid
              ? () => Navigator.pop(context, (_key.text.trim(), _value.text))
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
