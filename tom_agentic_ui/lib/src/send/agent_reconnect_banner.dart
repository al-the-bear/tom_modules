import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_send_controller.dart';

/// The §6.1 reconnect surface, shared by the minimal send panel and the full
/// chat composer.
///
/// Two presentations, matching the spec's two interaction classes:
///   * the **informational** probing phase ([ReconnectPhase.probing]) is a
///     non-blocking inline info strip — work continues, the panel just shows it
///     is retrying;
///   * the **paused** phases (§6.1 steps 4–5,
///     [ReconnectPhase.awaitingDifferentWorkspace] /
///     [ReconnectPhase.awaitingStillGone]) demand a decision, so they are
///     presented as true modal dialogs (`showDialog`) that block until the user
///     picks an action.
///
/// The widget stays the single integration point: hosts embed one
/// `AgentReconnectBanner` and it renders the inline strip *and* drives the
/// modals. The modal is opened/closed by a phase listener (not from `build`,
/// where `showDialog` is illegal), keeping [AgentSendController.reconnectPhase]
/// the single source of truth — the dialog actions only call the controller,
/// and the resulting phase change is what dismisses the dialog.
///
/// Renders nothing inline while the phase is [ReconnectPhase.idle] or while a
/// paused phase is being shown as a modal.
class AgentReconnectBanner extends StatefulWidget {
  const AgentReconnectBanner({super.key, required this.controller});

  /// The send controller whose reconnect phase drives the banner.
  final AgentSendController controller;

  @override
  State<AgentReconnectBanner> createState() => _AgentReconnectBannerState();
}

class _AgentReconnectBannerState extends State<AgentReconnectBanner> {
  /// True from the moment [showDialog] is requested until the route is gone.
  /// Tracked synchronously (the dialog's builder, which sets [_dialogContext],
  /// does not run until the next pump, so several controller notifications can
  /// fire first — without this flag they would each open a fresh dialog).
  bool _modalOpen = false;

  /// The dialog route's own context once it has built, used to pop exactly that
  /// route (not whatever happens to be topmost). `null` until the build.
  BuildContext? _dialogContext;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPhaseChanged);
  }

  @override
  void didUpdateWidget(AgentReconnectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPhaseChanged);
      widget.controller.addListener(_onPhaseChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPhaseChanged);
    super.dispose();
  }

  /// True for the paused phases that are presented as a blocking modal.
  static bool _isModalPhase(ReconnectPhase phase) =>
      phase == ReconnectPhase.awaitingDifferentWorkspace ||
      phase == ReconnectPhase.awaitingStillGone;

  /// Opens the modal when the protocol enters a paused phase and closes it when
  /// it leaves one. Runs from a controller notification (never during build), so
  /// `showDialog` is safe here.
  void _onPhaseChanged() {
    if (!mounted) return;
    final wantsModal = _isModalPhase(widget.controller.reconnectPhase);
    if (wantsModal && !_modalOpen) {
      _openModal();
    } else if (!wantsModal && _modalOpen) {
      _closeModal();
    }
  }

  void _openModal() {
    _modalOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _dialogContext = dialogContext;
          // Rebuild the dialog body if the phase shifts between the two paused
          // states (e.g. a declined different-workspace re-send goes still-gone)
          // before the listener swaps the route.
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (_, _) => _modalFor(widget.controller),
          );
        },
      ).then((_) {
        _modalOpen = false;
        _dialogContext = null;
      }),
    );
  }

  void _closeModal() {
    _modalOpen = false;
    final dialogContext = _dialogContext;
    _dialogContext = null;
    if (dialogContext != null) Navigator.of(dialogContext).pop();
  }

  Widget _modalFor(AgentSendController controller) {
    switch (controller.reconnectPhase) {
      case ReconnectPhase.awaitingDifferentWorkspace:
        final ws =
            controller.differentWorkspaceServer?.workspace ??
            'another workspace';
        return AlertDialog(
          icon: const Icon(Icons.swap_horiz),
          title: const Text('Reconnect to a different workspace?'),
          content: Text(
            'The VS Code server on this port now serves "$ws". Reconnect to it '
            'and re-send the interrupted prompt?',
          ),
          actions: [
            // "Dismiss" keeps this workspace's binding and just re-sends the
            // original prompt (§6.1 step 5 declined).
            TextButton(
              onPressed: controller.resendPending,
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: controller.confirmDifferentWorkspace,
              child: const Text('Reconnect'),
            ),
          ],
        );
      case ReconnectPhase.awaitingStillGone:
        return AlertDialog(
          icon: const Icon(Icons.cloud_off),
          title: const Text('VS Code server still unavailable'),
          content: const Text(
            'No VS Code server is responding on this port. Your prompt is '
            'preserved — retry when the window is back, or abort the send.',
          ),
          actions: [
            TextButton(
              onPressed: controller.abortReconnect,
              child: const Text('Abort'),
            ),
            FilledButton(
              onPressed: controller.resendPending,
              child: const Text('Retry'),
            ),
          ],
        );
      case ReconnectPhase.idle:
      case ReconnectPhase.probing:
        // The phase moved out from under the route; an empty frame while the
        // listener pops it.
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Only the non-blocking probing strip is inline; the paused phases live in
    // the modal driven by [_onPhaseChanged].
    if (widget.controller.reconnectPhase == ReconnectPhase.probing) {
      return _banner(
        theme,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        'Lost connection to the VS Code server — retrying…',
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner(
    ThemeData theme,
    Color background,
    Color foreground,
    String text,
    Widget trailing,
  ) {
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
