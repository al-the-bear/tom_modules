/// What the README example prints, asserted — the expectations are written
/// here, so the test states a claim of its own rather than agreeing with the
/// example's comments by construction.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../example/readme_example.dart' as example;

List<String> _printed(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  test('the example computes, recalculates the dependents of an edit, '
      'reads another sheet, and lowers a formula', () {
    expect(_printed(example.main), [
      '200',
      '40',
      'low',
      '150',
      'low',
      '#DIV/0!',
      "formula.add(formula.rangeSum(currentSheet.range(0, 0, 1, 0)), "
          "formula.sheet('rates').cell(0, 0))",
    ]);
  });
}
