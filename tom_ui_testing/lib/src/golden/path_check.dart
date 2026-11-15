/// Whether a shot names the machine that took it.
///
/// A golden is committed, and a picture that shows `/Users/<account>/…` both
/// records a user's path in the repository and fails for every other account
/// and checkout location — the comparison then reports a pixel difference
/// that is really a difference of machines. A suite gives what it boots its
/// data, trail and log directories relative to the package, so what a shot
/// shows reads the same everywhere; this check holds that, over every
/// paragraph and every text field the shot draws.
library;

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The absolute paths no shot may show: the home directory of the account
/// running the test, and the package root the test runs in (which also covers
/// a checkout outside any home directory). [tomMachinePathIn] also refuses a
/// path written from `~`.
List<String> tomMachinePaths() => [
      if ((Platform.environment['HOME'] ?? '').length > 1)
        Platform.environment['HOME']!,
      Directory.current.absolute.path,
    ];

/// The home directory a suite gives anything that shortens a path against
/// the home (`~/…`): the package root. With the user's home a shot would read
/// `~/<this checkout>/…`; with this one every machine reads `~/testlog/…`,
/// the package's own gitignored folder.
String get tomGoldenHome => Directory.current.absolute.path;

/// The machine path [text] contains, or null: an entry of [tomMachinePaths], or
/// a path written relative to a home directory (`~/…`), which names this
/// account's tree just as surely — except `~/testlog/…`, the [tomGoldenHome]
/// stand-in.
String? tomMachinePathIn(String text, {List<String>? paths}) {
  for (final path in paths ?? tomMachinePaths()) {
    if (text.contains(path)) return path;
  }
  final home = RegExp(r'''(^|[\s(\["'])~[/\\](?!testlog[/\\])''')
      .firstMatch(text);
  if (home != null) return '~/';
  return null;
}

/// No text drawn under [finder] — a paragraph or a text field's value —
/// contains a [tomMachinePaths] entry.
void expectTomNoMachinePaths(WidgetTester tester, Finder finder, {String? shot}) {
  final paths = tomMachinePaths();
  final texts = <String>[
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    ))
      paragraph.text.toPlainText(),
    for (final field in tester.widgetList<EditableText>(
      find.descendant(of: finder, matching: find.byType(EditableText)),
    ))
      field.controller.text,
  ];
  for (final text in texts) {
    final found = tomMachinePathIn(text, paths: paths);
    expect(found, isNull,
        reason: '${shot ?? 'the shot'} shows "$text", which names this '
            'machine\'s path $found; give the harness a path relative to the '
            'package instead');
  }
}
