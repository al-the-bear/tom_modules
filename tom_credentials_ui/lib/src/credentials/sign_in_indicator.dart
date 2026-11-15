/// A status line's sign-in item.
///
/// An affordance rather than a report, so it does not vanish when nothing is
/// wrong. Signed out it reads **Sign in** and raises the token dialog
/// ([showTomTokenDialog], the same one a storage command raises when a backend
/// has no token); signed in it shows the host and account, and its popover
/// says how long the credential lasts and offers to replace it or sign out.
library;

import 'package:flutter/material.dart';

import 'sign_in.dart';
import 'token_dialog.dart';

class TomSignInIndicator extends StatelessWidget {
  final TomSignIn controller;

  /// Drops the label and keeps the icon — the phone's compact strip, where
  /// the tooltip (long-press) and the tap still work.
  final bool iconOnly;

  const TomSignInIndicator({
    super.key,
    required this.controller,
    this.iconOnly = false,
  });

  /// Raises the token dialog for the controller's host and keeps the answer;
  /// null when the user cancelled.
  static Future<TomSignIn?> signIn(
    BuildContext context,
    TomSignIn controller,
  ) async {
    final token = await showTomTokenDialog(context, host: controller.host);
    if (token == null) return null;
    await controller.storeToken(token);
    return controller;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final signedIn = controller.signedIn;
      final style = Theme.of(context).textTheme.labelSmall;
      final note = controller.sessionNote;
      if (signedIn == null) {
        return Tooltip(
          message: note == null
              ? 'Sign in to ${controller.host}'
              : 'Sign in to ${controller.host}. $note',
          child: InkWell(
            key: const Key('tom-sign-in'),
            onTap: () => signIn(context, controller),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.login, size: 14),
                  if (!iconOnly) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Sign in',
                        key: const Key('tom-sign-in-label'),
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      final account = signedIn.account;
      final who = account == null ? signedIn.host : '$account@${signedIn.host}';
      return MenuAnchor(
        menuChildren: [
          Padding(
            key: const Key('tom-signed-in-popover'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row(context, 'Signed in to', signedIn.host),
                  if (account != null) _row(context, 'Account', account),
                  _row(
                    context,
                    'Kept',
                    note ?? 'In your settings, until you revoke it.',
                  ),
                ],
              ),
            ),
          ),
          MenuItemButton(
            key: const Key('tom-sign-in-replace'),
            leadingIcon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: () => signIn(context, controller),
            child: const Text('Replace the token…'),
          ),
          MenuItemButton(
            key: const Key('tom-sign-out'),
            leadingIcon: const Icon(Icons.logout, size: 16),
            onPressed: controller.signOut,
            child: const Text('Sign out'),
          ),
        ],
        builder: (context, menu, _) => InkWell(
          key: const Key('tom-signed-in'),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Tooltip(
            message: note == null ? 'Signed in as $who' : '$who. $note',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle_outlined, size: 14),
                  if (!iconOnly) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        who,
                        key: const Key('tom-signed-in-label'),
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  static Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label: ', style: theme.labelMedium),
            TextSpan(text: value, style: theme.bodySmall),
          ],
        ),
      ),
    );
  }
}
