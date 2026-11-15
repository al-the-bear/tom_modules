/// The AI trail view — the live trails of the AI sessions, as a panel docked
/// below an application's editing area on the desktop and a bottom sheet on
/// the phone.
///
/// Rendering follows the VS Code extension's trail: a run header with the
/// user's instruction; thinking, collapsed and dimmed; the answer as Markdown;
/// each tool call a card with its arguments as JSON, a status and its result
/// under it; retries, stalls and notices as lines; and per run its model,
/// duration, tokens and cost.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tom_llm/tom_llm.dart';

import 'docked_run.dart';
import 'package:tom_ui_support/tom_ui_support.dart';
import 'trail_controller.dart';
import 'package:tom_file_editors/tom_file_editors.dart';

/// How many characters of a tool result show before *Expand*.
const int tomTrailResultPreview = 600;

/// The words for each entry kind, in the filter menu.
String tomTrailKindLabel(LlmTrailEntryKind kind) => switch (kind) {
      LlmTrailEntryKind.run => 'Run headers',
      LlmTrailEntryKind.thinking => 'Thinking',
      LlmTrailEntryKind.text => 'Answer text',
      LlmTrailEntryKind.tool => 'Tool calls',
      LlmTrailEntryKind.notice => 'Notices',
      LlmTrailEntryKind.summary => 'Run summaries',
    };

/// The key of [entry] for its expansion state and its widget.
String tomTrailEntryKey(LlmTrailEntry entry) =>
    '${entry.sessionId}/${entry.runId}/${entry.at.microsecondsSinceEpoch}/'
    '${entry.kind.name}';

/// The trail view: tabs, header, filter and the entries.
class TomAiTrailView extends StatefulWidget {
  final TomAiTrailController controller;

  /// Closes the view — the panel's close button, or the sheet's. Null shows
  /// none.
  final VoidCallback? onClose;

  const TomAiTrailView({super.key, required this.controller, this.onClose});

  @override
  State<TomAiTrailView> createState() => _TrailViewState();
}

class _TrailViewState extends State<TomAiTrailView> {
  final ScrollController _scroll = ScrollController();

  /// Whether the view follows new entries: true until the reader scrolls up,
  /// and again once they scroll back to the bottom.
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _follow = position.pixels >= position.maxScrollExtent - 24;
  }

  void _followToEnd([int attempts = 3]) {
    if (!_follow || attempts == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_follow) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) return;
      _scroll.jumpTo(position.maxScrollExtent);
      // A lazily built list learns its true extent only as the entries near
      // the end are laid out, so the end moves once more after the jump.
      _followToEnd(attempts - 1);
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final entries = c.entries;
          final selected = c.selected;
          final docked = selected == null ? null : c.dockedRun(selected);
          final overview =
              selected == null ? c.dockedRuns : const <TomDockedAiRun>[];
          _followToEnd();
          return Column(
            key: const Key('tom-ai-trail'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Tabs(controller: c, onClose: widget.onClose),
              _Header(controller: c),
              const Divider(height: 1),
              // The run started from the application in this session: its preview
              // and decision, above the trail it writes. Loose,
              // so a short run leaves the trail its room and a long one
              // scrolls within three fifths of the view.
              if (docked != null) ...[
                Flexible(
                  flex: 3,
                  child: Column(
                    key: Key('tom-ai-trail-dock-${docked.sessionId}'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                          child: docked.buildView(context),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                        child: docked.buildActions(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ] else if (overview.isNotEmpty) ...[
                _RunsOverview(controller: c, runs: overview),
                const Divider(height: 1),
              ],
              Expanded(
                flex: 2,
                child: entries.isEmpty && docked != null
                    ? const SizedBox.shrink()
                    : entries.isEmpty
                    ? Center(
                        child: Text(
                          c.sessions.isEmpty
                              ? 'No AI run yet. Runs show here as they happen.'
                              : 'Nothing to show with this filter.',
                          key: const Key('tom-ai-trail-empty'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        key: const Key('tom-ai-trail-list'),
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _Entry(
                          key: ValueKey(tomTrailEntryKey(entries[i])),
                          entry: entries[i],
                          controller: c,
                          showSession: c.selected == null,
                        ),
                      ),
              ),
            ],
          );
        },
      );
}

/// The tab row: **All**, one tab per session (running ones marked, each
/// closable), then the filter, *Copy all* and close.
class _Tabs extends StatelessWidget {
  final TomAiTrailController controller;
  final VoidCallback? onClose;

  const _Tabs({required this.controller, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Tab(
                    key: const Key('tom-ai-trail-tab-all'),
                    label: 'All',
                    selected: c.selected == null,
                    onTap: () => c.select(null),
                  ),
                  for (final id in c.sessions)
                    _Tab(
                      key: Key('tom-ai-trail-tab-$id'),
                      id: id,
                      label: c.sessionName(id),
                      selected: c.selected == id,
                      running: c.isRunning(id),
                      deciding: c.needsDecision(id),
                      onTap: () => c.select(id),
                      onClose: () => c.closeSession(id),
                      onMenu: (context) => _sessionMenu(context, c, id),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('tom-ai-trail-new-session'),
            tooltip: 'New session',
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => _newSession(context, c),
          ),
          PopupMenuButton<LlmTrailEntryKind>(
            key: const Key('tom-ai-trail-filter'),
            tooltip: 'Filter by kind',
            icon: Icon(
              c.hidden.isEmpty ? Icons.filter_list : Icons.filter_list_alt,
              size: 18,
            ),
            onSelected: c.toggleKind,
            itemBuilder: (context) => [
              for (final kind in LlmTrailEntryKind.values)
                CheckedPopupMenuItem(
                  key: Key('tom-ai-trail-filter-${kind.name}'),
                  value: kind,
                  checked: !c.hidden.contains(kind),
                  child: Text(tomTrailKindLabel(kind)),
                ),
            ],
          ),
          IconButton(
            key: const Key('tom-ai-trail-copy-all'),
            tooltip: 'Copy the whole trail',
            icon: const Icon(Icons.copy_all, size: 18),
            onPressed: c.entries.isEmpty
                ? null
                : () => _copy(context, c, c.plainText, 'Trail copied.'),
          ),
          if (onClose != null)
            IconButton(
              key: const Key('tom-ai-trail-close'),
              tooltip: 'Close the trail',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String id;
  final String label;
  final bool selected;
  final bool running;

  /// Whether the session's docked run waits for the user's decision.
  final bool deciding;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final void Function(BuildContext context)? onMenu;

  const _Tab({
    super.key,
    this.id = '',
    required this.label,
    required this.selected,
    required this.onTap,
    this.running = false,
    this.deciding = false,
    this.onClose,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running) ...[
              SizedBox(
                key: Key('tom-ai-trail-running-${id.isEmpty ? label : id}'),
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
              ),
              const SizedBox(width: 6),
            ],
            if (deciding) ...[
              Tooltip(
                message: 'Waits for your decision',
                child: Icon(
                  Icons.pending_actions,
                  key: Key('tom-ai-trail-deciding-$id'),
                  size: 14,
                  color: theme.colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
            if (onMenu case final menu?)
              Builder(
                builder: (context) => InkWell(
                  key: Key('tom-ai-trail-tab-menu-$id'),
                  onTap: () => menu(context),
                  child: Tooltip(
                    message: 'Session',
                    child: Icon(Icons.arrow_drop_down, size: 16, color: color),
                  ),
                ),
              ),
            if (onClose != null)
              InkWell(
                key: Key('tom-ai-trail-tab-close-${id.isEmpty ? label : id}'),
                onTap: onClose,
                child: Tooltip(
                  message: 'Close this tab and clear its trail in memory',
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 14, color: color),
                  ),
                ),
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// The **All** tab's overview of the runs started from the application: one line
/// each, saying where it is; selecting one shows its session's tab.
class _RunsOverview extends StatelessWidget {
  final TomAiTrailController controller;
  final List<TomDockedAiRun> runs;

  const _RunsOverview({required this.controller, required this.runs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        key: const Key('tom-ai-trail-runs'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final run in runs)
            InkWell(
              key: Key('tom-ai-trail-run-${run.sessionId}'),
              onTap: () => controller.select(run.sessionId),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      run.needsDecision
                          ? Icons.pending_actions
                          : run.isWorking
                          ? Icons.hourglass_top
                          : Icons.check,
                      size: 14,
                      color: run.needsDecision
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(controller.sessionName(run.sessionId),
                        style: theme.textTheme.labelMedium),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        run.statusLine,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the selected session's trail is written, and why.
class _Header extends StatelessWidget {
  final TomAiTrailController controller;

  const _Header({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final selected = controller.selected;
    final status = controller.fileStatus;
    final Widget body;
    if (selected == null) {
      body = Text('Every session, interleaved by time.', style: style);
    } else if (status == null) {
      body = Text(
        'Kept in memory: no trail file is written for this session.',
        key: const Key('tom-ai-trail-memory'),
        style: style,
      );
    } else if (status.memoryOnly) {
      body = Row(
        children: [
          Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.tertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text('Kept in memory only: ${status.reason}',
                key: const Key('tom-ai-trail-memory'), style: style),
          ),
          if (status.keepOnDisk case final keep?)
            TextButton(
              key: const Key('tom-ai-trail-keep-on-disk'),
              onPressed: () => _confirmKeep(context, status.path, keep),
              child: const Text('Keep this session\'s trail on disk'),
            ),
        ],
      );
    } else {
      body = Text(
        'Written to ${status.path} (${status.reason}).',
        key: const Key('tom-ai-trail-file'),
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: body,
    );
  }

  Future<void> _confirmKeep(
    BuildContext context,
    String path,
    Future<void> Function() keep,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tom-ai-trail-keep-confirm'),
        title: const Text('Write this trail to disk?'),
        content: Text(
          "This session's runs drew on an encrypted document. Its trail — "
          'your instructions, the answers and tool results — will be written '
          'in plain text to $path: this run and the session\'s later runs, '
          'until the app exits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('tom-ai-trail-keep-confirm-ok'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Write to disk'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.keepOnDisk(keep);
  }
}

Future<void> _copy(
  BuildContext context,
  TomAiTrailController controller,
  String text,
  String done,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  _notice(context, controller, kind: 'trail-copied', message: done);
}

/// Shows a notice of the view through the host's surface
/// ([TomAiTrailController.showNotice]), or as a plain snack bar.
void _notice(
  BuildContext context,
  TomAiTrailController controller, {
  required String kind,
  required String message,
}) {
  final show = controller.showNotice;
  if (show != null) {
    show(context, kind: kind, message: message);
    return;
  }
  tomShowNotice(ScaffoldMessenger.maybeOf(context),
      kind: kind, message: message);
}

/// One entry, with its session badge on the **All** tab and its *Copy*.
class _Entry extends StatelessWidget {
  final LlmTrailEntry entry;
  final TomAiTrailController controller;
  final bool showSession;

  const _Entry({
    super.key,
    required this.entry,
    required this.controller,
    required this.showSession,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = tomTrailEntryKey(entry);
    final body = switch (entry) {
      final LlmTrailRunEntry e => _RunHeader(entry: e),
      final LlmTrailThinkingEntry e => _Thinking(
          entry: e,
          expanded: controller.isExpanded(key),
          onToggle: () => controller.toggleExpanded(key),
        ),
      final LlmTrailTextEntry e =>
        SelectionArea(child: TomMarkdownBody(markdown: e.text, compact: true)),
      final LlmTrailToolEntry e => _ToolCard(
          entry: e,
          expanded: controller.isExpanded(key),
          onToggle: () => controller.toggleExpanded(key),
        ),
      final LlmTrailNoticeEntry e => _Notice(entry: e),
      final LlmTrailSummaryEntry e => _Summary(entry: e),
    };
    return Padding(
      padding: EdgeInsets.only(
        top: entry is LlmTrailRunEntry ? 10 : 3,
        bottom: 3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSession)
            Container(
              margin: const EdgeInsets.only(right: 6, top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.sessionId,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          Expanded(child: body),
          IconButton(
            key: Key('tom-ai-trail-copy-$key'),
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            icon: Icon(Icons.copy, color: theme.colorScheme.onSurfaceVariant),
            onPressed: () => _copy(context, controller, entry.plainText, 'Copied.'),
          ),
        ],
      ),
    );
  }
}

String _time(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class _RunHeader extends StatelessWidget {
  final LlmTrailRunEntry entry;

  const _RunHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final context0 = entry.contextSectionIds.isEmpty && entry.contextLength == 0
        ? null
        : '${entry.contextSectionIds.length} section'
            '${entry.contextSectionIds.length == 1 ? '' : 's'} of context, '
            '${entry.contextLength} characters'
            '${entry.elidedCount > 0 ? ', ${entry.elidedCount} cut' : ''}'
            '${entry.excludedCount > 0 ? ', ${entry.excludedCount} with AI off' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.play_arrow, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                [
                  entry.purpose,
                  entry.providerId,
                  ?entry.model,
                  _time(entry.at),
                ].join(' · '),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.primary),
              ),
            ),
          ],
        ),
        if (entry.instruction case final instruction?)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(instruction, style: theme.textTheme.bodyMedium),
          ),
        if (context0 != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(context0, style: theme.textTheme.labelSmall),
          ),
      ],
    );
  }
}

class _Thinking extends StatelessWidget {
  final LlmTrailThinkingEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  const _Thinking({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    final firstLine = entry.text.trim().split('\n').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('tom-ai-trail-thinking-toggle'),
          onTap: onToggle,
          child: Row(
            children: [
              Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16, color: dim?.color),
              Text('Thinking', style: dim?.copyWith(fontWeight: FontWeight.w600)),
              if (!expanded) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(firstLine,
                      style: dim, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: SelectableText(entry.text,
                key: const Key('tom-ai-trail-thinking-text'), style: dim),
          ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  final LlmTrailToolEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  const _ToolCard({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final result = entry.result;
    final (statusIcon, statusLabel, statusColor) = switch (entry.status) {
      LlmToolStatus.running => (
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          'running',
          scheme.onSurfaceVariant,
        ),
      LlmToolStatus.done => (
          Icon(Icons.check_circle_outline, size: 14, color: scheme.primary),
          'done',
          scheme.primary,
        ),
      LlmToolStatus.failed => (
          Icon(Icons.error_outline, size: 14, color: scheme.error),
          'error',
          scheme.error,
        ),
    };
    final text = result?.text ?? '';
    final long = text.length > tomTrailResultPreview;
    final shown = long && !expanded
        ? '${text.substring(0, tomTrailResultPreview)}…'
        : text;
    return Card(
      key: Key('tom-ai-trail-tool-${entry.callId}'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: entry.status == LlmToolStatus.failed
              ? scheme.error
              : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.build_outlined, size: 14, color: scheme.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(entry.name,
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis),
                ),
                statusIcon,
                const SizedBox(width: 4),
                Text(statusLabel,
                    key: Key('tom-ai-trail-tool-status-${entry.callId}'),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: statusColor)),
              ],
            ),
            if (entry.arguments.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                color: scheme.surfaceContainerHighest,
                child: SelectableText(entry.argumentsJson, style: mono),
              ),
            if (result != null) ...[
              const SizedBox(height: 6),
              Text(
                result.isError ? 'Error' : 'Result',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: result.isError ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
              SelectableText(
                shown,
                key: Key('tom-ai-trail-tool-result-${entry.callId}'),
                style: mono?.copyWith(
                  color: result.isError ? scheme.error : null,
                ),
              ),
              if (result.fullLength > text.length)
                Text(
                  'The tool answered ${result.fullLength} characters; the '
                  'transport passed on ${text.length}.',
                  style: theme.textTheme.labelSmall,
                ),
              if (long)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: Key('tom-ai-trail-tool-expand-${entry.callId}'),
                    onPressed: onToggle,
                    child: Text(expanded
                        ? 'Collapse'
                        : 'Expand (${text.length} characters)'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final LlmTrailNoticeEntry entry;

  const _Notice({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.isError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final icon = switch (entry.noticeKind) {
      LlmTrailNoticeKind.session => Icons.circle_outlined,
      LlmTrailNoticeKind.retry => Icons.replay,
      LlmTrailNoticeKind.stall => Icons.hourglass_bottom,
      LlmTrailNoticeKind.notice => Icons.info_outline,
      LlmTrailNoticeKind.error => Icons.warning_amber_outlined,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(
            entry.message,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final LlmTrailSummaryEntry entry;

  const _Summary({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = entry.outcome == LlmRunOutcome.failed ||
        entry.outcome == LlmRunOutcome.timeout;
    final color = failed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(
          switch (entry.outcome) {
            LlmRunOutcome.completed => Icons.check,
            LlmRunOutcome.cancelled => Icons.stop_circle_outlined,
            LlmRunOutcome.failed => Icons.error_outline,
            LlmRunOutcome.timeout => Icons.timer_off_outlined,
          },
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            entry.line,
            key: const Key('tom-ai-trail-summary'),
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The splitter above the docked panel: dragging it sets the panel's height,
/// written once the drag ends.
class TomAiTrailSplitter extends StatelessWidget {
  final TomAiTrailController controller;

  /// The tallest the panel may be — the space the editing area can give up.
  final double maxHeight;

  const TomAiTrailSplitter({
    super.key,
    required this.controller,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const Key('tom-ai-trail-splitter'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            final next = controller.height - details.delta.dy;
            controller.dragHeight(next > maxHeight ? maxHeight : next);
          },
          onVerticalDragEnd: (_) => controller.commitHeight(),
          child: SizedBox(
            height: 6,
            child: Center(
              child: Container(height: 1, color: Theme.of(context).dividerColor),
            ),
          ),
        ),
      );
}

/// The panel docked below the editing area: the splitter and the
/// view, at the stored height — never more than [available] leaves the
/// editing area room for.
class TomAiTrailPanel extends StatelessWidget {
  final TomAiTrailController controller;

  /// The height the editing area and the panel share.
  final double available;

  const TomAiTrailPanel({
    super.key,
    required this.controller,
    required this.available,
  });

  /// The panel's drawn height: the stored one, but at most two thirds of
  /// [available], so a height dragged out on a tall screen does not bury the
  /// editor on a short one.
  static double _drawnHeight(double stored, double available) {
    final cap = available * 2 / 3;
    final floor = TomAiTrailController.minHeight;
    final max = cap < floor ? floor : cap;
    return stored > max ? max : stored;
  }

  @override
  Widget build(BuildContext context) {
    final max = _drawnHeight(double.infinity, available);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TomAiTrailSplitter(controller: controller, maxHeight: max),
        SizedBox(
          key: const Key('tom-ai-trail-panel'),
          height: _drawnHeight(controller.height, available),
          child: TomAiTrailView(
            controller: controller,
            onClose: () => controller.setOpen(false),
          ),
        ),
      ],
    );
  }
}

/// Opens the trail as a bottom sheet — the phone layout.
Future<void> showTomAiTrailSheet(
  BuildContext context,
  TomAiTrailController controller,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        key: const Key('tom-ai-trail-sheet'),
        height: MediaQuery.sizeOf(sheetContext).height * 0.75,
        child: TomAiTrailView(
          controller: controller,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );

/// The status-line chip: the AI trail and how many sessions are running.
/// On the desktop it opens and closes the docked panel; on the phone it opens
/// the bottom sheet. Absent on a root with no AI transport.
class TomAiTrailChip extends StatelessWidget {
  final TomAiTrailController controller;

  /// Whether this is the phone layout, where the trail is a bottom sheet.
  final bool phone;

  const TomAiTrailChip({
    super.key,
    required this.controller,
    this.phone = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.isAvailable) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final running = controller.runningCount;
        final color = running > 0
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;
        return Tooltip(
          message: phone
              ? 'Show the AI trail'
              : controller.isOpen
                  ? 'Hide the AI trail'
                  : 'Show the AI trail',
          child: InkWell(
            key: const Key('tom-ai-trail-chip'),
            onTap: phone
                ? () => showTomAiTrailSheet(context, controller)
                : controller.toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timeline, size: 14, color: color),
                  if (running > 0) ...[
                    const SizedBox(width: 3),
                    Text(
                      '$running',
                      key: const Key('tom-ai-trail-chip-count'),
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                  if (!phone) ...[
                    const SizedBox(width: 4),
                    Text('Trail',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: color)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


/// A session tab's menu: which gestures run in it, and for a
/// session the user created, rename and remove.
Future<void> _sessionMenu(
  BuildContext context,
  TomAiTrailController c,
  String id,
) async {
  final session = c.registry.byId(id);
  if (session == null) return;
  final box = context.findRenderObject()! as RenderBox;
  final at = box.localToGlobal(Offset(0, box.size.height));
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: [
      CheckedPopupMenuItem(
        key: const Key('tom-ai-trail-session-actions'),
        value: 'actions',
        checked: c.registry.actionSession == id,
        child: const Text('Run AI actions here'),
      ),
      CheckedPopupMenuItem(
        key: const Key('tom-ai-trail-session-agent'),
        value: 'agent',
        checked: c.registry.agentSession == id,
        child: const Text('Run the agent here'),
      ),
      if (!session.isBuiltIn) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: Key('tom-ai-trail-session-rename'),
          value: 'rename',
          child: Text('Rename…'),
        ),
        const PopupMenuItem(
          key: Key('tom-ai-trail-session-remove'),
          value: 'remove',
          child: Text('Remove session'),
        ),
      ],
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'actions':
      c.registry.useForActions(id);
    case 'agent':
      c.registry.useForAgent(id);
    case 'rename':
      final name = await showDialog<String>(
        context: context,
        builder: (context) => _NameDialog(
          title: 'Rename session',
          initial: session.name,
          action: 'Rename',
        ),
      );
      if (name != null) await c.renameSession(id, name);
    case 'remove':
      try {
        await c.removeSession(id);
      } on LlmSessionException catch (e) {
        if (context.mounted) {
          _notice(context, c, kind: 'ai-session', message: e.message);
        }
      }
  }
}

/// Creates a session: an internal one, or one bound to a quest
/// folder of a registered Workspace root.
Future<void> _newSession(
  BuildContext context,
  TomAiTrailController c,
) async {
  final folders = await c.questFolders?.call() ?? const <String>[];
  if (!context.mounted) return;
  final result = await showDialog<(String, String?)>(
    context: context,
    builder: (context) => _NewSessionDialog(
      questFolders: folders,
      questAvailable: c.questFolders != null,
    ),
  );
  if (result == null || !context.mounted) return;
  try {
    await c.createSession(result.$1, questFolder: result.$2);
  } on LlmSessionException catch (e) {
    if (context.mounted) {
      _notice(context, c, kind: 'ai-session', message: e.message);
    }
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    this.initial = '',
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('tom-ai-session-name'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('tom-ai-session-ok'),
            onPressed: () => Navigator.of(context).pop(_name.text),
            child: Text(widget.action),
          ),
        ],
      );
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({
    required this.questFolders,
    required this.questAvailable,
  });

  final List<String> questFolders;
  final bool questAvailable;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  final TextEditingController _name = TextEditingController();
  bool _quest = false;
  String? _folder;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final canCreate = _name.text.trim().isNotEmpty && (!_quest || _folder != null);
    return AlertDialog(
      key: const Key('tom-ai-new-session'),
      title: const Text('New AI session'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('tom-ai-session-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _quest,
              onChanged: (v) => setState(() => _quest = v ?? false),
              child: Column(
                children: [
                  const RadioListTile<bool>(
                    key: Key('tom-ai-session-kind-internal'),
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text('Internal'),
                    subtitle: Text('Its trail goes to the trail directory.'),
                  ),
                  RadioListTile<bool>(
                    key: const Key('tom-ai-session-kind-quest'),
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    enabled: widget.questAvailable,
                    title: const Text('Quest'),
                    subtitle: const Text(
                        'Its trail and its prompts and answers go into a '
                        'quest folder.'),
                  ),
                ],
              ),
            ),
            if (_quest)
              widget.questFolders.isEmpty
                  ? Text(
                      'No quest folder was found under the Workspace roots. A '
                      'quest folder holds overview.<folder>.md.',
                      key: const Key('tom-ai-session-no-quests'),
                      style: style,
                    )
                  : DropdownButton<String>(
                      key: const Key('tom-ai-session-quest-folder'),
                      isExpanded: true,
                      hint: const Text('Quest folder'),
                      value: _folder,
                      items: [
                        for (final folder in widget.questFolders)
                          DropdownMenuItem(
                            value: folder,
                            child: Text(folder,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _folder = v),
                    ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('tom-ai-session-create'),
          onPressed: canCreate
              ? () => Navigator.of(context)
                  .pop((_name.text, _quest ? _folder : null))
              : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
