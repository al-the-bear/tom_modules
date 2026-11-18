@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('OFFICE-PROTO-PURE-1: no library imports dart:io, dart:ffi or '
      'Flutter', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(4), reason: 'found nothing');
    for (final file in files) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains("'dart:io'")), reason: file.path);
      expect(text, isNot(contains("'dart:ffi'")), reason: file.path);
      expect(text, isNot(contains('package:flutter/')), reason: file.path);
    }
  });
}
