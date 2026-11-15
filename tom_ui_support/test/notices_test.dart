/// Notices go away on their own and do not queue behind one of their kind
/// (`tomShowNotice`); this package shows a snack bar nowhere else.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_support/tom_ui_support.dart';

Widget _host() => const MaterialApp(home: Scaffold(body: SizedBox.expand()));

ScaffoldMessengerState _messenger(WidgetTester tester) =>
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));

void main() {
  testWidgets('NOTICE-1: a second notice of a kind replaces the first at once, '
      'and nothing is left after its duration', (tester) async {
    await tester.pumpWidget(_host());
    final messenger = _messenger(tester);
    tomShowNotice(messenger, kind: 'created', message: 'Created "Plan".');
    await tester.pumpAndSettle();
    tomShowNotice(messenger, kind: 'created', message: 'Created "Budget".');
    await tester.pumpAndSettle();
    expect(find.text('Created "Budget".'), findsOneWidget);
    expect(find.text('Created "Plan".'), findsNothing);
    await tester.pump(tomNoticeDuration('Created "Budget".'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('NOTICE-2: a notice with an action still times out',
      (tester) async {
    await tester.pumpWidget(_host());
    tomShowNotice(
      _messenger(tester),
      kind: 'k',
      message: 'With an action',
      action: SnackBarAction(label: 'Open', onPressed: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('NOTICE-3: notices of other kinds still queue; a waiting one '
      'of the same kind is replaced in its place', (tester) async {
    await tester.pumpWidget(_host());
    final messenger = _messenger(tester);
    tomShowNotice(messenger, kind: 'export', message: 'Printed.');
    tomShowNotice(messenger, kind: 'created', message: 'Created one.');
    tomShowNotice(messenger, kind: 'created', message: 'Created two.');
    await tester.pumpAndSettle();
    expect(find.text('Printed.'), findsOneWidget);
    await tester.pump(tomNoticeDuration('Printed.'));
    await tester.pumpAndSettle();
    expect(find.text('Created two.'), findsOneWidget);
    expect(find.text('Created one.'), findsNothing);
    await tester.pump(tomNoticeDuration('Created two.'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  test('NOTICE-4: a sentence stays four seconds, a long one longer, never '
      'more than ten', () {
    expect(tomNoticeDuration('Created "Plan".'), const Duration(seconds: 4));
    expect(tomNoticeDuration(List.filled(32, 'word').join(' ')),
        const Duration(seconds: 6));
    expect(tomNoticeDuration(List.filled(400, 'word').join(' ')),
        const Duration(seconds: 10));
  });

  testWidgets('NOTICE-5: without a messenger nothing happens', (tester) async {
    tomShowNotice(null, kind: 'k', message: 'nowhere');
  });

  test('NOTICE-6: nothing in the Tom UI modules shows a snack bar except '
      'the notice queue', () {
    // The rule holds for every package the notice queue was written for;
    // they sit beside this one in tom_modules.
    const modules = [
      'tom_ui_support', 'tom_ui_testing', 'tom_host_ui', 'tom_credentials_ui',
      'tom_sync_ui', 'tom_calendar_ui', 'tom_file_editors', 'tom_todo_ui',
      'tom_ai_trail_ui',
    ];
    final files = [
      for (final module in modules)
        ...Directory('../$module/lib')
            .listSync(recursive: true)
            .whereType<File>(),
    ];
    expect(files.length, greaterThan(60), reason: 'the walk found nothing');
    final offenders = [
      for (final file in files)
        if (file.path.endsWith('.dart') &&
            !file.path.endsWith('notices/notices.dart') &&
            file.readAsStringSync().contains('.showSnackBar('))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
