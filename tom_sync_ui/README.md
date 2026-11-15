# tom_sync_ui

Showing synchronisation to a person: the sync status as one line, a tooltip
and the action it asks for, the status-line indicator, and a three-way merge
view over any application's conflicts.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Sync status | `lib/src/sync_status/` | How a `tom_core_sync` status reads to a person (`TomSyncPresentation.of` over a `TomSyncSummary`: one line, a tooltip, a tone, the action it asks for — the key prompt or the merge view — and an upload ring), and the status-line widget that shows it (`TomSyncIndicator`). |
| Merge view | `lib/src/merge_view/` | A three-way merge view over any conflicts (`TomMergeView`): a conflict list (a dropdown on a narrow screen), the sides — base, ours, theirs, or two when there is no base — the decision bar and the result. The application supplies the rows (`TomMergeRow`, `TomMergeSide`), draws each row kind's versions through a `TomMergeRendererRegistry`, and writes a confirmed `TomMergeResolution`; a side whose content is unreachable is explained and cannot be taken; `TomMergeFieldTable` is the label/value table for scalar items and masked values. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_sync_ui/tom_sync_ui.dart` | everything above | all |

## Dependencies

Flutter, `tom_core_storage`, `tom_core_sync`.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:tom_sync_ui/tom_sync_ui.dart';

class NoteRow extends TomMergeRow {
  const NoteRow(this.id, this.ours, this.theirs);
  final String id;
  final String? ours;
  final String? theirs;
  @override
  String get kind => 'note';
  @override
  String get locator => 'notes.json';
  @override
  String get key => TomMergeRow.joinKey([locator, id]);
  @override
  String get headline => id;
  @override
  String get subtitle => 'note';
  @override
  List<TomMergeSide> get sides =>
      [TomMergeSide('ours', ours), TomMergeSide('theirs', theirs)];
  @override
  TomMergeResolution get seed => TomMergeResolution(value: ours, source: 'ours');
}

Widget review(List<NoteRow> rows) => TomMergeView(
      rows: rows,
      renderers: TomMergeRendererRegistry()
        ..register('note', (context, request) => Text('${request.value}')),
      onConfirm: (row, resolution) async {
        // Write resolution.value into the note, then retire the conflict.
      },
    );
```

## Tests

`flutter test` from this folder.
