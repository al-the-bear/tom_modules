/// The split panel and its separator, the search box and the small controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_controls/tom_ui_controls.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('TUC-L1: the split panel shares the width by its ratio, and a '
      'drag on the separator moves it within the bounds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const first = ValueKey('first');
    const second = ValueKey('second');
    await _pump(
      tester,
      const SplitPanel(
        initialRatio: 0.3,
        minRatio: 0.2,
        maxRatio: 0.8,
        first: SizedBox.expand(key: first),
        second: SizedBox.expand(key: second),
      ),
    );
    final w1 = tester.getSize(find.byKey(first)).width;
    final w2 = tester.getSize(find.byKey(second)).width;
    expect(w1 / (w1 + w2), closeTo(0.3, 0.01));

    await tester.drag(find.byType(DraggableSeparator), const Offset(200, 0));
    await tester.pump();
    final d1 = tester.getSize(find.byKey(first)).width;
    expect(d1, greaterThan(w1));

    await tester.drag(find.byType(DraggableSeparator), const Offset(-900, 0));
    await tester.pump();
    final m1 = tester.getSize(find.byKey(first)).width;
    final m2 = tester.getSize(find.byKey(second)).width;
    expect(m1 / (m1 + m2), closeTo(0.2, 0.01), reason: 'held at minRatio');
  });

  testWidgets('TUC-S1: the search box reports the text, the match position '
      'and the navigation', (tester) async {
    final searched = <String>[];
    var next = 0;
    var previous = 0;
    await _pump(
      tester,
      SearchBox(
        onSearch: searched.add,
        onNext: () => next++,
        onPrevious: () => previous++,
        matchCount: 5,
        currentMatch: 2,
      ),
    );
    await tester.enterText(find.byType(TextField), 'tree');
    expect(searched.last, 'tree');
    expect(find.text('2/5'), findsOneWidget);
    await tester.tap(find.byTooltip('Next (F3)'));
    await tester.tap(find.byTooltip('Previous (Shift+F3)'));
    expect((next, previous), (1, 1));
  });

  testWidgets('TUC-S2: with replace, the replace button answers both texts', (
    tester,
  ) async {
    String? replaced;
    await _pump(
      tester,
      SearchBox(
        onSearch: (_) {},
        showReplace: true,
        onReplace: (s, r) => replaced = '$s->$r',
      ),
    );
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'old');
    await tester.enterText(fields.at(1), 'new');
    await tester.tap(find.byTooltip('Replace'));
    expect(replaced, 'old->new');
  });

  testWidgets('TUC-C1: the action button, the collapse toggle and the node '
      'action row', (tester) async {
    var pressed = 0;
    var toggled = 0;
    var rowVisible = false;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            ActionButton(
              icon: Icons.add,
              tooltip: 'Add',
              onPressed: () => pressed++,
            ),
            CollapseToggle(isExpanded: false, onToggle: () => toggled++),
            NodeActionRow(
              visible: rowVisible,
              actions: [
                NodeAction(icon: Icons.delete, onPressed: () => pressed += 10),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => rowVisible = true),
              child: const Text('show'),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    expect(pressed, 1);
    expect(find.byTooltip('Add'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(toggled, 1);

    await tester.tap(find.byIcon(Icons.delete), warnIfMissed: false);
    expect(pressed, 1, reason: 'a hidden row ignores taps');
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete));
    expect(pressed, 11);
  });
}
