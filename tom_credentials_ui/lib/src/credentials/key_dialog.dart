/// The key prompt shown when no configured key opens a container.
library;

import 'package:flutter/material.dart';

import 'key_fields.dart';

/// The key prompt: names the file and where it is, says why no configured key
/// opened it, and takes a passphrase and/or a key file with "remember for
/// this file".
///
/// [keyFiles] is the host's key-file picker; without one the key-file row is
/// not shown. Answers what was entered, or null when the user cancelled.
Future<TomKeyRequest?> showTomKeyDialog(
  BuildContext context, {
  required String locator,
  required String reason,
  TomKeyFilePicker? keyFiles,
}) => showDialog<TomKeyRequest>(
  context: context,
  builder: (_) => _KeyDialog(
    locator: locator,
    reason: reason,
    keyFiles: keyFiles,
    pickerContext: context,
  ),
);

/// The last path segment of [locator] — the file a key prompt names.
String tomLocatorFileName(String locator) {
  var path = locator;
  while (path.endsWith('/') || path.endsWith(r'\')) {
    path = path.substring(0, path.length - 1);
  }
  final cut = path.lastIndexOf(RegExp(r'[/\\:]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

class _KeyDialog extends StatefulWidget {
  final String locator;
  final String reason;
  final TomKeyFilePicker? keyFiles;
  final BuildContext pickerContext;

  const _KeyDialog({
    required this.locator,
    required this.reason,
    required this.keyFiles,
    required this.pickerContext,
  });

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  final _key = TomKeyStepController();

  @override
  void initState() {
    super.initState();
    _key.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return AlertDialog(
      key: const Key('tom-key-dialog'),
      scrollable: true,
      title: const Text('Key required'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tomLocatorFileName(widget.locator),
              key: const Key('tom-key-document'),
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.locator,
              key: const Key('tom-key-locator'),
              style: small,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.close, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.reason,
                    key: const Key('tom-key-reason'),
                    style: small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TomKeyFields(
              controller: _key,
              keyPrefix: 'tom-key',
              keyFiles: widget.keyFiles,
              pickerContext: widget.pickerContext,
              autofocus: true,
              onSubmitted: () => _submit(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('tom-key-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('tom-key-confirm'),
          // Always pressable, as Enter in the passphrase field is: nothing
          // incomplete is submitted, and a disabled button would say less.
          onPressed: () => _submit(context),
          child: const Text('Unlock'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final request = _key.request;
    if (request == null || !_key.ready) return;
    Navigator.pop(context, request);
  }
}
