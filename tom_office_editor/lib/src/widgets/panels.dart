// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The office editor's panels around the document: detection's states, the
/// password question, the read-only bar, the conflict banner, the stopped
/// and failed views.
library;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../detection/installation.dart';

/// What detection's state says in the tab
/// (`part-libreoffice-detection`, *The states*).
String libreOfficeStateMessage(LibreOfficeInstallation installation) =>
    switch (installation.state) {
      LibreOfficeState.found =>
        'LibreOffice ${installation.version ?? ''} is ready.',
      LibreOfficeState.missing => 'LibreOffice is not installed.',
      LibreOfficeState.tooOld =>
        'LibreOffice ${installation.version ?? '?'} is older than '
            '$kLibreOfficeMinimumVersion.',
      LibreOfficeState.damaged =>
        'LibreOffice at ${installation.bundlePath ?? '?'} cannot be used.',
      LibreOfficeState.quarantined =>
        'LibreOffice has not been opened yet. Open it once from Finder to '
            'confirm it.',
    };

/// The view of a tab whose detection did not answer `found`.
class TomOfficeDetectionView extends StatelessWidget {
  /// The view for [installation]. Each callback adds its button when given.
  const TomOfficeDetectionView({
    super.key,
    required this.installation,
    this.onCheckAgain,
    this.onChooseLibreOffice,
    this.onOpenDownloadPage,
    this.onOpenLibreOffice,
  });

  /// Detection's answer.
  final LibreOfficeInstallation installation;

  /// *Check again*.
  final VoidCallback? onCheckAgain;

  /// *Choose LibreOffice…* (sets the user's path).
  final VoidCallback? onChooseLibreOffice;

  /// The download page.
  final VoidCallback? onOpenDownloadPage;

  /// *Open LibreOffice* (a quarantined copy).
  final VoidCallback? onOpenLibreOffice;

  @override
  Widget build(BuildContext context) {
    final state = installation.state;
    final showDownload =
        state == LibreOfficeState.missing || state == LibreOfficeState.tooOld;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              libreOfficeStateMessage(installation),
              key: const ValueKey('office-detection-message'),
              textAlign: TextAlign.center,
            ),
            if (state == LibreOfficeState.damaged &&
                installation.reason != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                installation.reason!,
                key: const ValueKey('office-detection-reason'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (showDownload && onOpenDownloadPage != null)
                  TextButton(
                    onPressed: onOpenDownloadPage,
                    child: const Text('Download LibreOffice'),
                  ),
                if ((showDownload) && onChooseLibreOffice != null)
                  OutlinedButton(
                    onPressed: onChooseLibreOffice,
                    child: const Text('Choose LibreOffice…'),
                  ),
                if (state == LibreOfficeState.quarantined &&
                    onOpenLibreOffice != null)
                  OutlinedButton(
                    onPressed: onOpenLibreOffice,
                    child: const Text('Open LibreOffice'),
                  ),
                if (onCheckAgain != null)
                  FilledButton(
                    key: const ValueKey('office-check-again'),
                    onPressed: onCheckAgain,
                    child: const Text('Check again'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The masked password question (the password is never kept here beyond
/// the field).
class TomOfficePasswordPanel extends StatefulWidget {
  /// The panel for [request].
  const TomOfficePasswordPanel({
    super.key,
    required this.name,
    required this.request,
    required this.onAnswer,
  });

  /// The file's name.
  final String name;

  /// The question.
  final TomOfficePasswordRequest request;

  /// The answer; `null` cancels (or opens read-only, for a password to
  /// modify).
  final ValueChanged<String?> onAnswer;

  @override
  State<TomOfficePasswordPanel> createState() => _TomOfficePasswordPanelState();
}

class _TomOfficePasswordPanelState extends State<TomOfficePasswordPanel> {
  final _field = TextEditingController();

  @override
  void didUpdateWidget(TomOfficePasswordPanel old) {
    super.didUpdateWidget(old);
    if (old.request.attempt != widget.request.attempt) _field.clear();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _field.text;
    _field.clear();
    widget.onAnswer(text);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.toModify
                      ? '${widget.name} needs a password to be edited.'
                      : '${widget.name} is password-protected.',
                ),
                if (r.attempt > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Wrong password. Try again.',
                      key: const ValueKey('office-password-wrong'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('office-password-field'),
                  controller: _field,
                  obscureText: true,
                  autofocus: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('office-password-cancel'),
                      onPressed: () => widget.onAnswer(null),
                      child: Text(r.toModify ? 'Open read-only' : 'Cancel'),
                    ),
                    FilledButton(
                      key: const ValueKey('office-password-ok'),
                      onPressed: _submit,
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The words for a read-only reason.
String officeReadOnlyMessage(
  TomOfficeReadOnlyReason reason, {
  String? lockedBy,
}) => switch (reason) {
  TomOfficeReadOnlyReason.host => 'Opened read-only.',
  TomOfficeReadOnlyReason.notWritable =>
    'Read-only: the file cannot be written.',
  TomOfficeReadOnlyReason.locked =>
    'Read-only: ${lockedBy ?? 'another program'} has it '
        'open.',
  TomOfficeReadOnlyReason.passwordToModify =>
    'Read-only: opened without the password to edit it.',
  TomOfficeReadOnlyReason.passwordProtected =>
    'Read-only: password-protected files are not saved in place.',
};

/// A bar above the document.
class TomOfficeBar extends StatelessWidget {
  /// A bar with [message] and [actions].
  const TomOfficeBar({
    super.key,
    required this.message,
    this.actions = const [],
    this.warning = false,
  });

  /// The text.
  final String message;

  /// Its buttons.
  final List<Widget> actions;

  /// A warning's colours.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: warning ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(
              warning ? Icons.warning_amber_outlined : Icons.lock_outline,
              size: 16,
              color: warning
                  ? scheme.onErrorContainer
                  : scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: warning
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A centred message with one action (the stopped and failed views).
class TomOfficeMessageView extends StatelessWidget {
  /// The view.
  const TomOfficeMessageView({
    super.key,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  /// The message.
  final String message;

  /// Its detail.
  final String? detail;

  /// The button's label.
  final String? actionLabel;

  /// The button.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              detail!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel ?? 'OK')),
          ],
        ],
      ),
    ),
  );
}
