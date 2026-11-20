import 'dart:async';

import 'package:flutter/material.dart';

/// Expands the placeholders of a prompt (§11.5): the host's composer — in the
/// TomSpecs editor `SpecPromptComposer.compose`, which reads the files a
/// prompt injects through the workspace's file system, hence a future.
typedef PromptCompose = Future<String> Function(String source);

/// A live, read-only preview of a placeholder-bearing [source] string with its
/// supported placeholders expanded (§11.5, OE-14).
///
/// Expansion is delegated to [compose] — typically `SpecPromptComposer.compose`
/// in the editor — so this widget stays decoupled from the placeholder engine
/// (`tom_core_agentic`) and is reusable across the composer (§11.1) and the
/// config editors (§12 — "live placeholder preview").
///
/// The expansion runs again whenever [source] changes; the preview shows the
/// latest expansion that has completed, and an expansion overtaken by a newer
/// [source] is dropped. `compose` may fail — notably with
/// `PlaceholderExpressionsUnsupportedError` for the deliberately disabled
/// `${{ … }}` form (§11.5). The preview catches *any* error and renders its
/// message inline in the error colour rather than letting it escape and break
/// the surrounding editor: a half-typed `${{` must never crash the panel the
/// user is typing into. An empty [source] renders [emptyHint] instead.
class PlaceholderPreview extends StatefulWidget {
  const PlaceholderPreview({
    super.key,
    required this.source,
    required this.compose,
    this.emptyHint = 'Nothing to preview yet.',
  });

  /// The raw, placeholder-bearing text to expand.
  final String source;

  /// Expands the supported placeholders in [source]; may fail for unsupported
  /// forms (the preview renders the error rather than propagating it).
  final PromptCompose compose;

  /// Shown when [source] is empty/whitespace, so the preview slot is never a
  /// bare empty box.
  final String emptyHint;

  @override
  State<PlaceholderPreview> createState() => _PlaceholderPreviewState();
}

class _PlaceholderPreviewState extends State<PlaceholderPreview> {
  /// The latest completed expansion: its text, or the error's message.
  String _body = '';
  bool _isError = false;

  /// Counts the expansions started, so only the latest one is shown.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_expand());
  }

  @override
  void didUpdateWidget(PlaceholderPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.compose != widget.compose) {
      unawaited(_expand());
    }
  }

  Future<void> _expand() async {
    final generation = ++_generation;
    final source = widget.source;
    if (source.trim().isEmpty) return;
    String body;
    var isError = false;
    try {
      body = await widget.compose(source);
    } on Object catch (error) {
      body = '$error';
      isError = true;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _body = body;
      _isError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.source.trim().isEmpty) {
      return Text(
        widget.emptyHint,
        key: const Key('placeholder-preview-empty'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return SelectableText(
      _body,
      key: const Key('placeholder-preview-body'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: _isError ? theme.colorScheme.error : null,
      ),
    );
  }
}
