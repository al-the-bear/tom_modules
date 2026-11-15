/// The access-token half of a storage command: ask for a token when the
/// backend has none, or when it refused the one it had.
///
/// The key prompt's twin. A command that reaches a remote meets
/// [TomTokenRequiredException] when no token is held for the host and
/// [TomTokenRejectedException] when the service refused the one held. Both
/// have the same answer — ask, keep the answer, try again — because a failure
/// report would only tell the user that something they cannot fix from the
/// report went wrong. The same dialog sets or replaces a token from a
/// settings section ([showTomTokenDialog]).
library;

import 'package:flutter/material.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'token_keeper.dart';

/// Runs [action], asking for a token and retrying while the backend needs one.
///
/// Null when the user declined the prompt.
/// [keeper] is where an answer is kept; without one there is nowhere to keep
/// a token, so the backend's refusal is passed on rather than asked about.
Future<T?> withTomTokenFlow<T>(
  BuildContext context, {
  required TomTokenKeeper? keeper,
  required Future<T> Function() action,
}) async {
  while (true) {
    final String host;
    final bool rejected;
    try {
      return await action();
    } on TomTokenRequiredException catch (e) {
      if (keeper == null) rethrow;
      host = e.host;
      rejected = false;
    } on TomTokenRejectedException catch (e) {
      if (keeper == null) rethrow;
      host = e.host;
      rejected = true;
    }
    if (!context.mounted) return null;
    final token = await showTomTokenDialog(
      context,
      host: host,
      rejected: rejected,
    );
    if (token == null) return null;
    await keeper.storeToken(token);
  }
}

/// Asks for an access token, answering it or null when the user cancelled.
///
/// [host] names the service the token is for; null asks for the host too —
/// a settings section's "Add a token". The field is empty whatever is held
/// already: a replacement never shows the token it replaces.
Future<TomToken?> showTomTokenDialog(
  BuildContext context, {
  String? host,
  bool rejected = false,
}) => showDialog<TomToken>(
  context: context,
  builder: (context) => _TokenPrompt(host: host, rejected: rejected),
);

class _TokenPrompt extends StatefulWidget {
  const _TokenPrompt({required this.host, required this.rejected});

  final String? host;
  final bool rejected;

  @override
  State<_TokenPrompt> createState() => _TokenPromptState();
}

class _TokenPromptState extends State<_TokenPrompt> {
  final _secret = TextEditingController();
  final _account = TextEditingController();
  final _host = TextEditingController();

  @override
  void dispose() {
    _secret.dispose();
    _account.dispose();
    _host.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _secret.text.trim();
    final host = widget.host ?? _host.text.trim();
    if (secret.isEmpty || host.isEmpty) return;
    final account = _account.text.trim();
    Navigator.pop(
      context,
      TomToken(
        host: host,
        secret: secret,
        account: account.isEmpty ? null : account,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    return AlertDialog(
      key: const Key('tom-token-prompt'),
      // The explanation, the field and the buttons are taller than a phone
      // in landscape; the dialog scrolls rather than overflows.
      scrollable: true,
      title: Text(
        host == null
            ? 'Add an access token'
            : widget.rejected
            ? '$host refused the access token'
            : 'Access token for $host',
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              host == null
                  ? 'Documents on a remote host are read and written with a '
                        'personal access token that can read and write the '
                        'repository\'s contents.'
                  : widget.rejected
                  ? 'The token held for $host was refused — it may '
                        'have expired or been revoked. Enter a new one to '
                        'try again.'
                  : 'Documents on $host are read and written with a '
                        'personal access token that can read and write the '
                        'repository\'s contents.',
            ),
            const SizedBox(height: 12),
            if (host == null)
              TextField(
                key: const Key('tom-token-host'),
                controller: _host,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'github.com',
                ),
                onSubmitted: (_) => _submit(),
              ),
            TextField(
              key: const Key('tom-token-secret'),
              controller: _secret,
              autofocus: host != null,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Token'),
              onSubmitted: (_) => _submit(),
            ),
            TextField(
              key: const Key('tom-token-account'),
              controller: _account,
              decoration: const InputDecoration(
                labelText: 'Account (optional)',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('tom-token-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('tom-token-confirm'),
          onPressed: _submit,
          child: const Text('Use this token'),
        ),
      ],
    );
  }
}
