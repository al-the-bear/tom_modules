/// The validation model and its markers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_controls/tom_ui_controls.dart';

const _errors = [
  ValidationError(path: ['a', 'b'], message: 'missing value'),
  ValidationError(
    path: ['a', 'c'],
    message: 'deprecated key',
    severity: ValidationSeverity.warning,
  ),
  ValidationError(path: ['d'], message: 'wrong type'),
];

void main() {
  test('TUC-V1: errors are summed up to every ancestor path', () {
    final propagated = ErrorPropagator.propagate(_errors);
    expect(ErrorPropagator.countAt(propagated, []), (errors: 2, warnings: 1));
    expect(ErrorPropagator.countAt(propagated, ['a']), (
      errors: 1,
      warnings: 1,
    ));
    expect(ErrorPropagator.countAt(propagated, ['a', 'b']), (
      errors: 1,
      warnings: 0,
    ));
    expect(ErrorPropagator.countAt(propagated, ['x']), (
      errors: 0,
      warnings: 0,
    ));
    expect(
      ErrorPropagator.directErrorsAt(_errors, ['a']),
      isEmpty,
      reason: 'only descendants have errors',
    );
    expect(_errors.first.pathString, 'a > b');
  });

  testWidgets('TUC-V2: the badge shows the counts and nothing without any', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ValidationBadge(errorCount: 2, warningCount: 1),
              ValidationBadge(key: ValueKey('empty')),
            ],
          ),
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('empty'))), Size.zero);
  });

  testWidgets('TUC-V3: the tooltip lists the messages', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ValidationTooltip(errors: _errors)),
      ),
    );
    for (final e in _errors) {
      expect(find.text(e.message), findsOneWidget);
    }
  });
}
