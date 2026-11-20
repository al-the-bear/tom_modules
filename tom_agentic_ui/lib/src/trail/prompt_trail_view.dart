import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';

import 'prompt_trail_controller.dart';

/// The prompt trail column (§11.3, Col 3): the request/answer pairs of past
/// SDK exchanges, newest-first. Each row previews the request and answer;
/// tapping it opens the full request/answer body in a dialog.
///
/// Renders over a [PromptTrailController]; a pair whose answer is still
/// streaming shows a "waiting" placeholder until [PromptTrailController]
/// closes it.
class PromptTrailView extends StatelessWidget {
  const PromptTrailView({super.key, required this.controller});

  /// The trail controller this column renders.
  final PromptTrailController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Newest-first.
        final pairs = controller.pairs.reversed.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                'Trail (${pairs.length})',
                style: theme.textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pairs.isEmpty
                  ? _empty(theme)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: pairs.length,
                      itemBuilder: (context, i) =>
                          _item(context, theme, pairs[i]),
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(ThemeData theme) => Center(
    child: Text(
      'No exchanges yet.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _item(BuildContext context, ThemeData theme, TrailPair pair) {
    final answer = pair.answer;
    return ListTile(
      dense: true,
      title: Text(
        pair.request.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        answer?.text ?? 'Waiting for the answer…',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: answer == null ? theme.colorScheme.onSurfaceVariant : null,
          fontStyle: answer == null ? FontStyle.italic : null,
        ),
      ),
      onTap: () => _showBody(context, pair),
    );
  }

  void _showBody(BuildContext context, TrailPair pair) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Exchange'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Request', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    SelectableText(pair.request.text),
                    const SizedBox(height: 16),
                    Text('Answer', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    SelectableText(pair.answer?.text ?? '(still streaming)'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }
}
