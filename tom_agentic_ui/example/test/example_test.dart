import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_agentic_ui_example/main.dart';

void main() {
  testWidgets('the picker lists the fake server, the composer queues a '
      'prompt', (tester) async {
    await tester.pumpWidget(const AgenticExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('example_workspace'), findsOneWidget);
    expect(find.text('127.0.0.1:19900 · available'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Summarise the diff');
    await tester.pump();
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    expect(find.text('queued: Summarise the diff'), findsOneWidget);
  });
}
