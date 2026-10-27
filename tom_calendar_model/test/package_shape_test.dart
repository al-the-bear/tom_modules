/// What the package is, read from its source: a leaf any Dart program can
/// link, with no I/O in its default entry point and no application in it.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final sources = {
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart'))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
  };

  Iterable<String> importsOf(String source) => RegExp(
    r"^(?:import|export) '([^']+)'",
    multiLine: true,
  ).allMatches(source).map((m) => m.group(1)!);

  /// Every library the default entry point reaches inside the package.
  Set<String> closure(String root) {
    final seen = <String>{};
    final pending = [root];
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!seen.add(path)) continue;
      for (final uri in importsOf(sources[path]!)) {
        if (uri.contains(':')) continue;
        final parts = [...path.split('/')..removeLast(), ...uri.split('/')];
        final normal = <String>[];
        for (final part in parts) {
          if (part == '..') {
            normal.removeLast();
          } else if (part != '.') {
            normal.add(part);
          }
        }
        pending.add(normal.join('/'));
      }
    }
    return seen;
  }

  test('the entry point reaches no dart:io, no isolate and no package but '
      'uuid, so a browser build links it', () {
    final reached = closure('lib/tom_calendar_model.dart');
    expect(reached, contains('lib/src/icalendar.dart'));
    expect(reached, hasLength(sources.length));
    for (final path in reached) {
      for (final uri in importsOf(sources[path]!)) {
        if (!uri.contains(':')) continue;
        expect(
          uri == 'dart:convert' || uri.startsWith('package:uuid/'),
          isTrue,
          reason: '$path imports $uri',
        );
      }
    }
  });

  test('the pubspec depends on uuid alone', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final dependencies = pubspec
        .split('\ndev_dependencies:')
        .first
        .split('\ndependencies:')
        .last;
    final names = RegExp(
      r'^  (\w+):',
      multiLine: true,
    ).allMatches(dependencies).map((m) => m.group(1)).toSet();
    expect(names, {'uuid'});
  });

  test('nothing in the library names an application', () {
    for (final entry in sources.entries) {
      expect(
        entry.value,
        isNot(contains(RegExp('webwork', caseSensitive: false))),
        reason: entry.key,
      );
    }
  });
}
