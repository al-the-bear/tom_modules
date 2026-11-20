import 'dart:async';

import 'package:flutter/material.dart';

import 'agent_reconnect_banner.dart';
import 'agent_send_controller.dart';

/// The minimal §7 send surface: a read-only streaming output area above a
/// one-line composer (text field + Send button).
///
/// Step 12's "minimal output view" — the full chat composer, queue and trail
/// arrive in step 16. The output area auto-scrolls to the tail as chunks stream
/// in; Send is disabled while a turn is in flight or no bridge is bound.
class AgentSendPanel extends StatefulWidget {
  const AgentSendPanel({super.key, required this.controller});

  /// The send controller streaming the answer.
  final AgentSendController controller;

  @override
  State<AgentSendPanel> createState() => _AgentSendPanelState();
}

class _AgentSendPanelState extends State<AgentSendPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll the output to the tail as new chunks arrive.
    widget.controller.addListener(_autoScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_autoScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || !widget.controller.canSend) return;
    _input.clear();
    // The controller records the answer and any failure itself.
    unawaited(widget.controller.send(prompt));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AgentReconnectBanner(controller: controller),
            Expanded(child: _output(theme, controller)),
            const Divider(height: 1),
            _composer(theme, controller),
          ],
        );
      },
    );
  }

  Widget _output(ThemeData theme, AgentSendController controller) {
    if (controller.error != null) {
      return _centered(
        theme,
        Icons.error_outline,
        '${controller.error}',
        theme.colorScheme.error,
      );
    }
    if (controller.output.isEmpty) {
      return _centered(
        theme,
        controller.sending ? Icons.hourglass_top : Icons.bolt_outlined,
        controller.sending
            ? 'Sending…'
            : 'Send a prompt to the bound VS Code agent.',
        theme.colorScheme.onSurfaceVariant,
      );
    }
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        controller.output,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _composer(ThemeData theme, AgentSendController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Ask the agent…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          controller.sending
              ? IconButton.filled(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.stop, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () => controller.cancel(),
                )
              : IconButton.filled(
                  tooltip: controller.canSend
                      ? 'Send'
                      : 'Bind a VS Code bridge first',
                  icon: const Icon(Icons.send, size: 18),
                  onPressed: controller.canSend ? _send : null,
                ),
        ],
      ),
    );
  }

  Widget _centered(ThemeData theme, IconData icon, String text, Color color) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
