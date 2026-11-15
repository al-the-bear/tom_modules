/// How the merge view draws one version: renderers by row kind, and the field
/// table several of them share.
library;

import 'package:flutter/material.dart';

import 'merge_model.dart';

/// What a renderer is asked to draw.
class TomMergeBodyRequest {
  /// The row the version belongs to.
  final TomMergeRow row;

  /// The version, never null: a deleted side is drawn by the view.
  final Object value;

  /// Which pane this is — a side's label, or `result`.
  final String label;

  /// Whether the pane is read-only.
  final bool readOnly;

  /// Called after the user edits the result pane.
  final VoidCallback? onChanged;

  const TomMergeBodyRequest({
    required this.row,
    required this.value,
    required this.label,
    required this.readOnly,
    this.onChanged,
  });
}

/// Draws one version of a conflicted item.
typedef TomMergeBodyRenderer =
    Widget Function(BuildContext context, TomMergeBodyRequest request);

/// The renderers a merge view draws versions with, one per row kind.
///
/// An application registers the same renderers its editors use, read-only,
/// so a conflict is compared in the shape the user edits it in — a renderer
/// that ran only during conflicts would be wrong exactly where being wrong
/// costs the most.
class TomMergeRendererRegistry {
  final Map<String, TomMergeBodyRenderer> _renderers = {};

  /// Registers [renderer] for rows whose kind is [kind], replacing any.
  void register(String kind, TomMergeBodyRenderer renderer) =>
      _renderers[kind] = renderer;

  /// Whether a renderer is registered for [kind].
  bool handles(String kind) => _renderers.containsKey(kind);

  /// Draws [request], or says plainly that nothing can.
  Widget build(BuildContext context, TomMergeBodyRequest request) {
    final renderer = _renderers[request.row.kind];
    if (renderer == null) {
      return Center(child: Text('No view for ${request.row.kind}.'));
    }
    return renderer(context, request);
  }
}

/// A label/value table: one line per field, labels in a fixed column, values
/// selectable.
///
/// For items that are a handful of scalar fields, where what the user needs
/// is to see *which* field differs: the same field lands on the same line in
/// every pane, so a difference is a difference in the text and not in the
/// layout.
class TomMergeFieldTable extends StatelessWidget {
  /// The fields, in display order.
  final List<(String, String)> fields;

  const TomMergeFieldTable({super.key, required this.fields});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      for (final (label, value) in fields)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Expanded(child: SelectableText(value)),
            ],
          ),
        ),
    ],
  );
}
