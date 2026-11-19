import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_controls/tom_ui_controls.dart';
import 'package:tom_ui_controls_example/main.dart';

void main() {
  testWidgets('the search box filters the tree, a tap shows the file with '
      'its marker', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ControlsExampleApp());
    expect(find.byType(SplitPanel), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('tree.dart'), findsNothing, reason: 'folders collapsed');

    await tester.enterText(find.byType(TextField), 'tree');
    await tester.pump();
    await tester.pump();
    expect(find.text('tree_view.md'), findsOneWidget);
    expect(find.text('tree.dart'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.text('tree.dart'));
    await tester.pump();
    await tester.pump();
    expect(find.text('lib/tree.dart'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'one error on the badge');
  });
}
