/// The three-way merge view: a conflict list, the read-only sides, a decision
/// bar and the result.
library;

import 'package:flutter/material.dart';

import 'merge_model.dart';
import 'merge_renderers.dart';

/// Resolves a queue of conflicts, one row at a time.
///
/// Heterogeneous queues are the ordinary case — conflicts from different
/// kinds of container in one list — so the fork is at the renderer, not at
/// the door: the list, the selection, the decision bar and the confirm flow
/// are shared, and each row's versions are drawn by the [renderers] entry for
/// its kind.
///
/// The view holds the decisions taken but not yet confirmed, keyed by row, so
/// a hand-edited result survives a rebuild; each row starts on its
/// [TomMergeRow.seed]. Rows the application hands over again after a rebuild
/// keep their decisions. Conflicts that offer a comparison are listed before
/// those where a side cannot be shown.
class TomMergeView extends StatefulWidget {
  /// The queue. The application rebuilds the view as it changes.
  final List<TomMergeRow> rows;

  /// How each row kind's versions are drawn.
  final TomMergeRendererRegistry renderers;

  /// Writes a decision and retires the conflict. Rows the application does
  /// not remove from [rows] afterwards are remembered as settled when
  /// [rememberSettled] is set.
  final Future<void> Function(TomMergeRow row, TomMergeResolution resolution)
  onConfirm;

  /// Whether confirming [row] leaves the decision only in memory, so the bar
  /// says it is saved with the next save. Said before Confirm, because a
  /// consequence learnt after acting cannot be taken into account.
  final bool Function(TomMergeRow row)? needsSave;

  /// Remember confirmed rows and stop listing them, for rows that no queue
  /// retires.
  final bool rememberSettled;

  final String title;

  const TomMergeView({
    super.key,
    required this.rows,
    required this.renderers,
    required this.onConfirm,
    this.needsSave,
    this.rememberSettled = false,
    this.title = 'Resolve conflicts',
  });

  @override
  State<TomMergeView> createState() => _TomMergeViewState();
}

class _TomMergeViewState extends State<TomMergeView> {
  final Map<String, TomMergeResolution> _resolutions = {};
  final Set<String> _settled = {};
  String? _selectedKey;

  TomMergeResolution _resolutionFor(TomMergeRow row) =>
      _resolutions.putIfAbsent(row.key, () => row.seed);

  List<TomMergeRow> get _rows {
    final open = [
      for (final row in widget.rows)
        if (!_settled.contains(row.key)) row,
    ];
    return [
      for (final row in open)
        if (row.comparable) row,
      for (final row in open)
        if (!row.comparable) row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) {
      return _Frame(
        title: widget.title,
        child: const Center(
          key: Key('tom-merge-empty'),
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('No conflicts to resolve.'),
          ),
        ),
      );
    }

    final selected = rows.firstWhere(
      (row) => row.key == _selectedKey,
      orElse: () => rows.first,
    );

    return _Frame(
      title: '${widget.title} (${rows.length})',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final detail = _MergeDetail(
            key: ValueKey(selected.key),
            row: selected,
            narrow: narrow,
            renderers: widget.renderers,
            resolution: _resolutionFor(selected),
            onResolutionChanged: (resolution) =>
                setState(() => _resolutions[selected.key] = resolution),
            onConfirm: () => _confirm(selected),
            needsSave: widget.needsSave?.call(selected) ?? false,
          );

          if (narrow) {
            return Column(
              children: [
                _ConflictDropdown(
                  rows: rows,
                  selected: selected,
                  onSelected: (row) => setState(() => _selectedKey = row.key),
                ),
                const Divider(height: 1),
                Expanded(child: detail),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: _ConflictList(
                  rows: rows,
                  selected: selected,
                  onSelected: (row) => setState(() => _selectedKey = row.key),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm(TomMergeRow row) async {
    // Through the seeding accessor: a row confirmed without being touched
    // resolves to its seed, not to a missing decision that reads as deletion.
    await widget.onConfirm(row, _resolutionFor(row));
    if (!mounted) return;
    setState(() {
      if (widget.rememberSettled) _settled.add(row.key);
      _resolutions.remove(row.key);
      _selectedKey = null;
    });
  }
}

class _Frame extends StatelessWidget {
  final String title;
  final Widget child;

  const _Frame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 1000,
    height: 640,
    child: Column(
      children: [
        AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              key: const Key('tom-merge-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _ConflictList extends StatelessWidget {
  final List<TomMergeRow> rows;
  final TomMergeRow selected;
  final ValueChanged<TomMergeRow> onSelected;

  const _ConflictList({
    required this.rows,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const Key('tom-merge-conflict-list'),
    itemCount: rows.length,
    itemBuilder: (context, index) {
      final row = rows[index];
      return ListTile(
        dense: true,
        selected: row.key == selected.key,
        title: Text(row.headline, overflow: TextOverflow.ellipsis),
        subtitle: Text(row.subtitle, overflow: TextOverflow.ellipsis),
        onTap: () => onSelected(row),
      );
    },
  );
}

class _ConflictDropdown extends StatelessWidget {
  final List<TomMergeRow> rows;
  final TomMergeRow selected;
  final ValueChanged<TomMergeRow> onSelected;

  const _ConflictDropdown({
    required this.rows,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: DropdownButton<String>(
      key: const Key('tom-merge-conflict-picker'),
      isExpanded: true,
      value: selected.key,
      items: [
        for (final row in rows)
          DropdownMenuItem(
            value: row.key,
            child: Text(row.headline, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (key) => onSelected(rows.firstWhere((row) => row.key == key)),
    ),
  );
}

/// One conflict: the read-only sides, the result, and the decision buttons.
class _MergeDetail extends StatelessWidget {
  final TomMergeRow row;
  final bool narrow;
  final TomMergeRendererRegistry renderers;
  final TomMergeResolution resolution;
  final ValueChanged<TomMergeResolution> onResolutionChanged;
  final VoidCallback onConfirm;
  final bool needsSave;

  const _MergeDetail({
    super.key,
    required this.row,
    required this.narrow,
    required this.renderers,
    required this.resolution,
    required this.onResolutionChanged,
    required this.onConfirm,
    required this.needsSave,
  });

  /// The shortest the detail column is laid out at; below this it scrolls.
  /// A short viewport would otherwise not make the panes small but
  /// degenerate — a 31 px side is no comparison at all.
  static const double _minDetailHeight = 420;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final column = _column(context);
      if (constraints.maxHeight >= _minDetailHeight) return column;
      return SingleChildScrollView(
        child: SizedBox(height: _minDetailHeight, child: column),
      );
    },
  );

  Widget _column(BuildContext context) {
    final sides = row.sides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${row.headline}  ·  ${row.locator}',
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: narrow
              ? _SideTabs(sides: sides, row: row, renderers: renderers)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final side in sides)
                      Expanded(
                        child: _PaneFrame(
                          label: side.label,
                          child: _MergeBody(
                            row: row,
                            renderers: renderers,
                            value: side.value,
                            label: side.label,
                            readOnly: true,
                            absentBecause: side.absentBecause,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        _DecisionBar(
          row: row,
          // A side that cannot be shown cannot be taken: its null is not a
          // deletion, and offering it as one would delete what nobody decided
          // to remove.
          sides: [
            for (final side in sides)
              if (!side.unreachable) side,
          ],
          keepsWhatIsThere: !row.comparable,
          current: resolution,
          onResolutionChanged: onResolutionChanged,
          onConfirm: onConfirm,
          needsSave: needsSave,
        ),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: _PaneFrame(
            label: 'result',
            child: resolution.deletes
                ? const Center(
                    key: Key('tom-merge-result-delete'),
                    child: Text('This will be deleted.'),
                  )
                : _MergeBody(
                    key: ValueKey(resolution.value),
                    row: row,
                    renderers: renderers,
                    value: resolution.value,
                    label: 'result',
                    readOnly: !row.resultEditable,
                    onChanged: () => onResolutionChanged(
                      TomMergeResolution(value: resolution.value),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SideTabs extends StatelessWidget {
  final List<TomMergeSide> sides;
  final TomMergeRow row;
  final TomMergeRendererRegistry renderers;

  const _SideTabs({
    required this.sides,
    required this.row,
    required this.renderers,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: sides.length,
    child: _headerThenRest(
      header: TabBar(tabs: [for (final side in sides) Tab(text: side.label)]),
      body: TabBarView(
        children: [
          for (final side in sides)
            _PaneFrame(
              label: side.label,
              child: _MergeBody(
                row: row,
                renderers: renderers,
                value: side.value,
                label: side.label,
                readOnly: true,
                absentBecause: side.absentBecause,
              ),
            ),
        ],
      ),
    ),
  );
}

/// A fixed header above a body that takes the rest, the header clipped to
/// the height there is — a pane shorter than its own label shows nothing
/// readable either way, and must not paint over the decision bar.
Widget _headerThenRest({required Widget header, required Widget body}) =>
    LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: ClipRect(child: header),
          ),
          Expanded(child: body),
        ],
      ),
    );

/// One version: a deletion, an unreachable side, or the row's renderer.
class _MergeBody extends StatelessWidget {
  final TomMergeRow row;
  final TomMergeRendererRegistry renderers;
  final Object? value;
  final String label;
  final bool readOnly;
  final VoidCallback? onChanged;
  final String? absentBecause;

  const _MergeBody({
    super.key,
    required this.row,
    required this.renderers,
    required this.value,
    required this.label,
    required this.readOnly,
    this.onChanged,
    this.absentBecause,
  });

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null) {
      final absent = absentBecause;
      if (absent != null) {
        return _AbsentSide(key: const Key('tom-merge-absent'), reason: absent);
      }
      return const Center(child: Text('(deleted on this side)'));
    }
    return renderers.build(
      context,
      TomMergeBodyRequest(
        row: row,
        value: value,
        label: label,
        readOnly: readOnly,
        onChanged: onChanged,
      ),
    );
  }
}

class _PaneFrame extends StatelessWidget {
  final String label;
  final Widget child;

  const _PaneFrame({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: _headerThenRest(
        header: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Text(label, style: theme.textTheme.labelSmall),
        ),
        body: child,
      ),
    );
  }
}

class _DecisionBar extends StatelessWidget {
  final TomMergeRow row;
  final List<TomMergeSide> sides;
  final TomMergeResolution current;
  final ValueChanged<TomMergeResolution> onResolutionChanged;
  final VoidCallback onConfirm;
  final bool needsSave;

  /// A side cannot be shown, so the decision on offer is to keep the version
  /// there is; the bar says that rather than looking like a choice.
  final bool keepsWhatIsThere;

  const _DecisionBar({
    required this.row,
    required this.keepsWhatIsThere,
    required this.sides,
    required this.current,
    required this.onResolutionChanged,
    required this.onConfirm,
    required this.needsSave,
  });

  /// A [Wrap], not a [Row]: the number of sides and the labels vary and the
  /// view must work on a phone, where a row of buttons overflows.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // One side and nothing edited: nothing to take that is not already
        // the result.
        for (final side in sides)
          if (!(keepsWhatIsThere &&
              sides.length == 1 &&
              current.source == side.label))
            OutlinedButton(
              key: Key('tom-merge-take-${side.label}'),
              onPressed: () => onResolutionChanged(
                TomMergeResolution(value: row.take(side), source: side.label),
              ),
              child: Text(
                side.value == null
                    ? 'Delete (${side.label})'
                    : 'Use ${side.label}',
              ),
            ),
        Text(
          current.deletes
              ? 'Result: delete'
              : 'Result: ${current.source ?? 'edited'}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        FilledButton(
          key: const Key('tom-merge-confirm'),
          onPressed: onConfirm,
          child: Text(
            keepsWhatIsThere &&
                    current.source == row.seed.source &&
                    !current.deletes
                ? 'Keep this version'
                : 'Confirm',
          ),
        ),
        // Only when it is true: a line that is always there is a line nobody
        // reads.
        if (needsSave)
          Text(
            key: const Key('tom-merge-needs-save'),
            'Saved with your next save',
            style: Theme.of(context).textTheme.labelSmall,
          ),
      ],
    ),
  );
}

/// A side that is empty for a stated reason other than deletion — a loss to
/// work around, not a deletion to accept or reject, so it is not drawn like
/// one. Scrolls rather than centres, because a side pane can be 30 px tall.
class _AbsentSide extends StatelessWidget {
  const _AbsentSide({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
