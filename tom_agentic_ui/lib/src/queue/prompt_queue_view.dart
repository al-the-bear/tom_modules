import 'package:flutter/material.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';

import 'prompt_queue_controller.dart';

/// The prompt queue column (§11.2, Col 2): the staged/pending prompts with
/// per-item status, reorder (up/down), remove and retry, plus a "Send next"
/// action that dispatches the first pending item.
///
/// Renders over a [PromptQueueController]; every control routes back through
/// the controller (which persists + notifies), so the column repaints as
/// dispatch transitions each item's status.
class PromptQueueView extends StatelessWidget {
  const PromptQueueView({super.key, required this.controller});

  /// The queue controller this column renders and drives.
  final PromptQueueController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final items = controller.items;
        final hasPending =
            items.any((p) => p.status == QueuedPromptStatus.pending);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme, items.length, hasPending),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? _empty(theme)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _item(theme, items[i], i),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(ThemeData theme, int count, bool hasPending) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Queue ($count)',
              style: theme.textTheme.titleSmall,
            ),
          ),
          TextButton.icon(
            onPressed: hasPending && !controller.isDispatching
                ? controller.sendNext
                : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Send next'),
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Text(
          'No queued prompts.\nAdd one from the composer.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  Widget _item(ThemeData theme, QueuedPrompt item, int index) {
    final isLast = index == controller.items.length - 1;
    return ListTile(
      dense: true,
      leading: _statusChip(theme, item.status),
      title: Text(
        item.originalText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: item.error == null
          ? null
          : Text(
              item.error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status == QueuedPromptStatus.error)
            IconButton(
              tooltip: 'Retry',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed:
                  controller.isDispatching ? null : () => controller.retry(item.id),
            ),
          IconButton(
            tooltip: 'Move up',
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: index == 0 ? null : () => controller.moveUp(index),
          ),
          IconButton(
            tooltip: 'Move down',
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: isLast ? null : () => controller.moveDown(index),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => controller.removeById(item.id),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(ThemeData theme, QueuedPromptStatus status) {
    final scheme = theme.colorScheme;
    final (color, icon) = switch (status) {
      QueuedPromptStatus.staged => (scheme.outline, Icons.drafts_outlined),
      QueuedPromptStatus.pending => (scheme.primary, Icons.schedule),
      QueuedPromptStatus.sending => (scheme.tertiary, Icons.send),
      QueuedPromptStatus.sent => (scheme.secondary, Icons.check_circle_outline),
      QueuedPromptStatus.error => (scheme.error, Icons.error_outline),
    };
    return Tooltip(message: status.value, child: Icon(icon, size: 18, color: color));
  }
}
