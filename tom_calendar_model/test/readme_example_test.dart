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
  test('the example expands a series, cancels an occurrence, says the times '
      'and round-trips the file', () {
    expect(_printed(example.main), [
      '2026-07-06T07:00:00Z, 2026-07-08T07:00:00Z, 2026-07-13T07:00:00Z, '
          '2026-07-15T07:00:00Z',
      '3',
      '2026-07-06 07:00–07:15 UTC · 2026-07-06 09:00–09:15 where created '
          '(UTC+02:00)',
      'Repeats every week on Monday and Wednesday, 4 times',
      'true',
      'team',
      '1',
      'IN-PROCESS',
      '0',
    ]);
  });
}
