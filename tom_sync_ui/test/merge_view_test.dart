import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_sync_ui/tom_sync_ui.dart';

/// A row over plain strings: base, ours and theirs, any of which may be
/// absent, and a side that may be unreachable.
class TextRow extends TomMergeRow {
  final String id;
  final String? base;
  final String? ours;
  final String? theirs;
  final bool lostTheirs;
  final bool editable;

  const TextRow(
    this.id, {
    this.base,
    this.ours,
    this.theirs,
    this.lostTheirs = false,
    this.editable = false,
  });

  @override
  String get kind => 'text';

  @override
  String get locator => 'mem:/doc';

  @override
  String get key => TomMergeRow.joinKey([locator, id]);

  @override
  String get headline => 'Item $id';

  @override
  String get subtitle => 'text';

  @override
  List<TomMergeSide> get sides => [
    if (base != null) TomMergeSide('base', base),
    TomMergeSide('ours', ours),
    TomMergeSide(
      'theirs',
      theirs,
      absentBecause: lostTheirs ? 'Gone from the container.' : null,
    ),
  ];

  @override
  TomMergeResolution get seed =>
      TomMergeResolution(value: ours, source: 'ours');

  @override
  bool get resultEditable => editable;
}

TomMergeRendererRegistry renderers() => TomMergeRendererRegistry()
  ..register(
    'text',
    (context, request) => Text(
      '${request.label}:${request.value}${request.readOnly ? '' : ' (edit)'}',
    ),
  );

Future<List<(String, Object?)>> pumpView(
  WidgetTester tester,
  List<TomMergeRow> rows, {
  bool rememberSettled = true,
  bool Function(TomMergeRow)? needsSave,
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final confirmed = <(String, Object?)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TomMergeView(
          rows: rows,
          renderers: renderers(),
          rememberSettled: rememberSettled,
          needsSave: needsSave,
          onConfirm: (row, resolution) async =>
              confirmed.add((row.key, resolution.value)),
        ),
      ),
    ),
  );
  return confirmed;
}

void main() {
  group('MERGE-VIEW: one view over any rows', () {
    testWidgets('MERGE-VIEW-1: three panes with a base, two without, drawn by '
        'the row kind\'s renderer, and a read-only result by default', (
      tester,
    ) async {
      await pumpView(tester, [
        const TextRow('a', base: 'b0', ours: 'o', theirs: 't'),
      ]);
      expect(find.text('base:b0'), findsOneWidget);
      expect(find.text('ours:o'), findsOneWidget);
      expect(find.text('theirs:t'), findsOneWidget);
      expect(find.text('result:o'), findsOneWidget);
      expect(find.text('Resolve conflicts (1)'), findsOneWidget);
    });

    testWidgets('MERGE-VIEW-2: confirm without touching takes the seed; '
        'taking a side then confirming takes that side; a settled row leaves', (
      tester,
    ) async {
      final confirmed = await pumpView(tester, [
        const TextRow('a', ours: 'o', theirs: 't'),
        const TextRow('b', ours: 'p', theirs: 'q'),
      ]);
      await tester.tap(find.byKey(const Key('tom-merge-confirm')));
      await tester.pumpAndSettle();
      expect(confirmed.single.$2, 'o');
      expect(find.text('Resolve conflicts (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tom-merge-take-theirs')));
      await tester.pump();
      expect(find.text('Result: theirs'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tom-merge-confirm')));
      await tester.pumpAndSettle();
      expect(confirmed.last.$2, 'q');
      expect(find.byKey(const Key('tom-merge-empty')), findsOneWidget);
    });

    testWidgets('MERGE-VIEW-3: a deleted side offers deletion; the result says '
        'it will be deleted', (tester) async {
      final confirmed = await pumpView(tester, [
        const TextRow('a', ours: 'o', theirs: null),
      ]);
      expect(find.text('Delete (theirs)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tom-merge-take-theirs')));
      await tester.pump();
      expect(find.byKey(const Key('tom-merge-result-delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tom-merge-confirm')));
      await tester.pumpAndSettle();
      expect(confirmed.single.$2, isNull);
    });

    testWidgets('MERGE-VIEW-4: an unreachable side is explained, offers no '
        'button, is listed after comparable rows, and the bar keeps what is '
        'there', (tester) async {
      await pumpView(tester, [
        const TextRow('lost', ours: 'o', lostTheirs: true),
        const TextRow('fine', ours: 'x', theirs: 'y'),
      ]);
      final list = tester.widget<ListView>(
        find.byKey(const Key('tom-merge-conflict-list')),
      );
      expect(list, isNotNull);
      expect(
        find.text('Item fine'),
        findsWidgets,
        reason: 'the comparable row is selected first',
      );
      await tester.tap(find.text('Item lost'));
      await tester.pump();
      expect(find.byKey(const Key('tom-merge-absent')), findsOneWidget);
      expect(find.byKey(const Key('tom-merge-take-theirs')), findsNothing);
      expect(find.text('Keep this version'), findsOneWidget);
    });

    testWidgets('MERGE-VIEW-5: an editable result is passed to the renderer as '
        'editable, and the save notice shows only when asked', (tester) async {
      await pumpView(tester, [
        const TextRow('a', ours: 'o', theirs: 't', editable: true),
      ], needsSave: (_) => true);
      expect(find.text('result:o (edit)'), findsOneWidget);
      expect(find.byKey(const Key('tom-merge-needs-save')), findsOneWidget);
    });

    testWidgets('MERGE-VIEW-6: a row the application keeps handing over stays '
        'listed when settling is not remembered', (tester) async {
      final confirmed = await pumpView(tester, [
        const TextRow('a', ours: 'o', theirs: 't'),
      ], rememberSettled: false);
      await tester.tap(find.byKey(const Key('tom-merge-confirm')));
      await tester.pumpAndSettle();
      expect(confirmed, hasLength(1));
      expect(find.text('Resolve conflicts (1)'), findsOneWidget);
    });

    testWidgets('MERGE-VIEW-7: a narrow view picks the row from a dropdown and '
        'shows the sides as tabs', (tester) async {
      await pumpView(tester, [
        const TextRow('a', base: 'b0', ours: 'o', theirs: 't'),
      ], size: const Size(600, 800));
      expect(
        find.byKey(const Key('tom-merge-conflict-picker')),
        findsOneWidget,
      );
      expect(find.byType(TabBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MERGE-VIEW-8: a kind with no renderer says so', (
      tester,
    ) async {
      final registry = TomMergeRendererRegistry();
      expect(registry.handles('text'), isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => registry.build(
                context,
                const TomMergeBodyRequest(
                  row: TextRow('a', ours: 'o'),
                  value: 'o',
                  label: 'ours',
                  readOnly: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('No view for text.'), findsOneWidget);
    });

    testWidgets('MERGE-VIEW-9: the field table lays labels and values out '
        'line by line', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TomMergeFieldTable(fields: [('Title', 'A'), ('URL', 'b')]),
          ),
        ),
      );
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    test('MERGE-VIEW-10: a resolution distinguishes a deletion from a value, '
        'and a side an unreachable state from a deletion', () {
      expect(const TomMergeResolution(value: null).deletes, isTrue);
      expect(const TomMergeResolution(value: 'x').deletes, isFalse);
      expect(const TomMergeSide('a', null).unreachable, isFalse);
      expect(
        const TomMergeSide('a', null, absentBecause: 'gone').unreachable,
        isTrue,
      );
      expect(TomMergeRow.joinKey(['a', 'b']), 'a\u0000b');
    });
  });
}
