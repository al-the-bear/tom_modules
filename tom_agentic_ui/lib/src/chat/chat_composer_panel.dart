import 'package:flutter/material.dart';

import '../send/agent_reconnect_banner.dart';
import '../send/agent_send_controller.dart';
import 'placeholder_preview.dart';

/// One selectable agent profile in the composer's profile picker (§11.1).
///
/// A deliberately minimal value type — just an [id] and a display [name] — so
/// the composer stays decoupled from `tom_core_agentic`'s richer `AgentProfile`
/// model: the host maps its profiles down to this and routes a selection back
/// via [ChatComposerPanel.onProfileSelected].
class ChatComposerProfile {
  const ChatComposerProfile({required this.id, required this.name});

  final String id;
  final String name;
}

/// The bottom chat composer (§11.1): a profile picker and the streamed answer
/// above a multiline input with two actions — **Send now** (stream
/// immediately) and **Add to queue** (defer for §11.2 dispatch) — plus an
/// optional live placeholder preview (§11.5, OE-14).
///
/// The streaming output + reconnect surface come from the shared
/// [AgentSendController]; the two actions are delegated to the host via
/// [onSendNow] / [onAddToQueue] so the composer stays transport-agnostic — the
/// host wires "Send now" through the trail-recording coordinator and "Add to
/// queue" through the queue controller.
///
/// The **profile picker** ([profiles] / [selectedProfileId] /
/// [onProfileSelected]) renders only when the host supplies profiles; the
/// **live preview** ([composePreview]) renders only when the host supplies a
/// compose function, expanding the current input's placeholders as the user
/// types and surfacing an unsupported-expression error inline.
class ChatComposerPanel extends StatefulWidget {
  const ChatComposerPanel({
    super.key,
    required this.controller,
    required this.onSendNow,
    required this.onAddToQueue,
    this.composePreview,
    this.profiles = const <ChatComposerProfile>[],
    this.selectedProfileId,
    this.onProfileSelected,
  });

  /// The send controller supplying the streamed answer and busy/reconnect state.
  final AgentSendController controller;

  /// Streams the composed prompt immediately (records the trail pair).
  final ValueChanged<String> onSendNow;

  /// Defers the composed prompt onto the queue.
  final ValueChanged<String> onAddToQueue;

  /// Expands the current input's placeholders for the live preview (§11.5,
  /// OE-14). When null, no preview is shown. May throw for unsupported forms —
  /// [PlaceholderPreview] renders the error rather than crashing the composer.
  final PromptCompose? composePreview;

  /// The profiles offered in the picker (§11.1). Empty hides the picker.
  final List<ChatComposerProfile> profiles;

  /// The currently selected profile id, or null for "no profile".
  final String? selectedProfileId;

  /// Called when the user picks a different profile (null = cleared).
  final ValueChanged<String?>? onProfileSelected;

  @override
  State<ChatComposerPanel> createState() => _ChatComposerPanelState();
}

class _ChatComposerPanelState extends State<ChatComposerPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// The picker's live selection. Seeded from the host and updated on change so
  /// the dropdown reflects the choice immediately (the view above is built once
  /// and does not rebuild on selection).
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _selectedProfileId = widget.selectedProfileId;
    widget.controller.addListener(_autoScroll);
    _input.addListener(_onInputChanged);
  }

  @override
  void didUpdateWidget(ChatComposerPanel old) {
    super.didUpdateWidget(old);
    // Re-seed when the host pushes a different selection (but not on our own
    // in-flight edits, which already updated `_selectedProfileId`).
    if (widget.selectedProfileId != old.selectedProfileId &&
        widget.selectedProfileId != _selectedProfileId) {
      _selectedProfileId = widget.selectedProfileId;
    }
  }

  void _onProfileChanged(String? id) {
    setState(() => _selectedProfileId = id);
    widget.onProfileSelected?.call(id);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_autoScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  void _autoScroll() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String get _text => _input.text.trim();

  void _sendNow() {
    final prompt = _text;
    if (prompt.isEmpty || !widget.controller.canSend) return;
    _input.clear();
    widget.onSendNow(prompt);
  }

  void _addToQueue() {
    final prompt = _text;
    if (prompt.isEmpty) return;
    _input.clear();
    widget.onAddToQueue(prompt);
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
      return _centered(theme, Icons.error_outline, '${controller.error}',
          theme.colorScheme.error);
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
      child: SelectableText(controller.output, style: theme.textTheme.bodyMedium),
    );
  }

  Widget _composer(ThemeData theme, AgentSendController controller) {
    final hasText = _text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.profiles.isNotEmpty) _profilePicker(theme),
          TextField(
            controller: _input,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Ask the agent…',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.composePreview != null) _preview(theme),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: hasText ? _addToQueue : null,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Add to queue'),
              ),
              const SizedBox(width: 8),
              controller.sending
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed:
                          hasText && controller.canSend ? _sendNow : null,
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Send now'),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  /// The profile picker dropdown (§11.1). A leading "No profile" entry lets the
  /// user clear the selection; selecting it routes `null` back to the host.
  Widget _profilePicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Profile',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            key: const Key('chat-composer-profile'),
            isDense: true,
            isExpanded: true,
            value: _selectedProfileId,
            onChanged: _onProfileChanged,
            items: [
              const DropdownMenuItem<String?>(
                child: Text('No profile'),
              ),
              for (final profile in widget.profiles)
                DropdownMenuItem<String?>(
                  value: profile.id,
                  child: Text(profile.name, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The collapsible live placeholder preview (§11.5, OE-14): the current input
  /// with its supported placeholders expanded, refreshed on every keystroke
  /// (the input listener already rebuilds the composer).
  Widget _preview(ThemeData theme) {
    return Theme(
      // Drop the default ExpansionTile divider lines so the preview tucks
      // quietly under the input.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('chat-composer-preview'),
        tilePadding: EdgeInsets.zero,
        dense: true,
        title: Text('Preview', style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceholderPreview(
            source: _input.text,
            compose: widget.composePreview!,
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
