import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_agentic_ui/tom_agentic_ui.dart';

ChangeEntry _entry(String id, String turn, {String section = 'PD00/x'}) =>
    ChangeEntry(
      id: id,
      sectionId: section,
      kind: ChangeKind.content,
      turnId: turn,
      afterThisEdit: id,
    );

void main() {
  group('ChangeEntry', () {
    test('valueForPane resolves base / thisEdit / current', () {
      final e = ChangeEntry(
        id: 'c1',
        sectionId: 'PD00/a',
        kind: ChangeKind.content,
        turnId: 't1',
        baseAtLastSave: 'BASE',
        afterThisEdit: 'EDIT',
      );
      expect(e.valueForPane(ReviewPane.base), 'BASE');
      expect(e.valueForPane(ReviewPane.thisEdit), 'EDIT');
      expect(e.valueForPane(ReviewPane.current, current: 'LIVE'), 'LIVE');
    });

    test('summary reflects kind and field', () {
      final f = ChangeEntry(
        id: 'c2',
        sectionId: 'PD00/b',
        kind: ChangeKind.formField,
        field: 'title',
        turnId: 't1',
      );
      expect(f.summary, 'Set field title');
    });
  });

  group('ChangeLog', () {
    test('groups by turn, newest turn first, oldest within turn', () {
      final log = ChangeLog();
      log.record(_entry('c1', 't1'));
      log.record(_entry('c2', 't1'));
      log.record(_entry('c3', 't2'));

      final groups = log.groups;
      expect(groups.map((g) => g.turnId), ['t2', 't1']);
      expect(groups[1].entries.map((e) => e.id), ['c1', 'c2']);
    });

    test('reset clears all entries and notifies', () {
      final log = ChangeLog();
      var notified = 0;
      log.addListener(() => notified++);
      log.record(_entry('c1', 't1'));
      expect(log.isEmpty, isFalse);

      log.reset();
      expect(log.isEmpty, isTrue);
      // one notify for record + one for reset.
      expect(notified, 2);
    });

    test('byId finds a recorded entry', () {
      final log = ChangeLog();
      log.record(_entry('c9', 't1'));
      expect(log.byId('c9')?.id, 'c9');
      expect(log.byId('missing'), isNull);
    });
  });

  group('widgets', () {
    testWidgets('ChangeLogPanel lists entries and raises onSelect',
        (tester) async {
      final log = ChangeLog()..record(_entry('c1', 't1', section: 'PD00/sec'));
      ChangeEntry? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeLogPanel(log: log, onSelect: (e) => picked = e),
        ),
      ));
      expect(find.text('PD00/sec'), findsOneWidget);
      await tester.tap(find.text('PD00/sec'));
      expect(picked?.id, 'c1');
    });

    testWidgets('ChangeReviewPanel raises onPick for the chosen pane',
        (tester) async {
      final entry = ChangeEntry(
        id: 'c1',
        sectionId: 'PD00/a',
        kind: ChangeKind.content,
        turnId: 't1',
        baseAtLastSave: 'BASE',
        afterThisEdit: 'EDIT',
      );
      ReviewPane? chosen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeReviewPanel(
            entry: entry,
            currentValue: 'LIVE',
            onPick: (p) => chosen = p,
          ),
        ),
      ));
      expect(find.text('BASE'), findsOneWidget);
      expect(find.text('EDIT'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      // Three "Use this pane" buttons; tap the middle (this edit).
      await tester.tap(find.text('Use this pane').at(1));
      expect(chosen, ReviewPane.thisEdit);
    });
  });
}
