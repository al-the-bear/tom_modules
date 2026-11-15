/// A golden case: where its failure images go, whether it runs, and what it
/// asserts before it compares a picture.
///
/// A failed comparison writes its images to `testlog/goldens/` (gitignored),
/// never beside the test, so a failure leaves nothing for a commit to sweep
/// up. A case that shows a known defect is skipped with the sentence naming
/// the work that fixes it, never baselined — a baseline of a defect would make
/// the defect the expected output. Every picture is compared only after the
/// content it should show is found, what it shows is found readable, and it
/// names no path of the machine taking it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'contrast_check.dart';
import 'golden_fonts.dart';
import 'path_check.dart';

/// Sends a failed comparison's images to [failureDir] instead of a
/// `failures/` folder beside the test.
class TomTestlogGoldenComparator extends LocalFileComparator {
  TomTestlogGoldenComparator(super.testFile, this.failureDir);

  /// Where failure images go.
  final Uri failureDir;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, failureDir);
    result.dispose();
    throw FlutterError(error);
  }
}

/// Installs [TomTestlogGoldenComparator] for the test file at [testFile],
/// relative to the package root, with its failures in `testlog/goldens/`.
void useTomTestlogComparator(String testFile) {
  final packageRoot = Directory.current.path;
  final failures = Directory(p.join(packageRoot, 'testlog', 'goldens'))
    ..createSync(recursive: true);
  goldenFileComparator = TomTestlogGoldenComparator(
    Uri.file(p.join(packageRoot, testFile)),
    Uri.directory(failures.path),
  );
}

/// Why [goldenName] does not run: the platform rule, then [knownRed] — the
/// cases whose shot shows a defect, keyed by golden name, each with the work
/// that makes it green and what the shot shows today.
String? tomGoldenSkipFor(
  String goldenName, {
  Map<String, String> knownRed = const {},
}) {
  final platform = tomGoldenSkipReason;
  if (platform != null) return platform;
  final red = knownRed[goldenName];
  return red == null ? null : 'KNOWN RED until $red';
}

/// A golden case named after its shot: skipped — with the reason in the
/// report, which `testWidgets`' boolean `skip` cannot carry — when
/// [tomGoldenSkipFor] says so.
void tomGoldenTestWidgets(
  String description,
  String goldenName,
  Future<void> Function(WidgetTester tester) body, {
  Map<String, String> knownRed = const {},
}) {
  testWidgets(description, (tester) async {
    final skip = tomGoldenSkipFor(goldenName, knownRed: knownRed);
    if (skip != null) {
      markTestSkipped(skip);
      return;
    }
    await body(tester);
  });
}

/// Compares [finder] with the golden at [path] — after the contrast check
/// ([expectTomReadable]) and the path check ([expectTomNoMachinePaths]), so
/// every case also asserts that what it shows can be read and names no path
/// of the machine taking it.
///
/// Under `--update-goldens` the picture is written first, so a case that
/// fails a check still leaves its evidence behind; that picture is not a
/// baseline to commit.
Future<void> expectTomGolden(
  WidgetTester tester,
  Finder finder,
  String path,
) async {
  // A file that forgot the comparator writes its failures beside the test,
  // where they get committed; say so instead of comparing.
  expect(goldenFileComparator, isA<TomTestlogGoldenComparator>(),
      reason: 'call useTomTestlogComparator in the file\'s setUpAll');
  if (autoUpdateGoldenFiles) {
    await expectLater(finder, matchesGoldenFile(path));
    expectTomReadable(tester, finder, shot: path);
    expectTomNoMachinePaths(tester, finder, shot: path);
    return;
  }
  expectTomReadable(tester, finder, shot: path);
  expectTomNoMachinePaths(tester, finder, shot: path);
  await expectLater(finder, matchesGoldenFile(path));
}

/// Asserts [marker] is drawn inside [content] and that [shot] matches the
/// golden at [path] ([expectTomGolden]).
///
/// The marker is checked first in an ordinary run, so an empty body fails
/// with [reason] rather than with a pixel difference. Under `--update-goldens`
/// the shot is written first, so a failing case still leaves its picture
/// behind for review — evidence, never a baseline to commit. Scope [content]
/// to the area that should hold the marker: a side panel naming the same
/// headline would otherwise let an empty body pass.
Future<void> expectTomShot(
  WidgetTester tester, {
  required Finder shot,
  required Finder content,
  required String marker,
  required String reason,
  required String path,
}) async {
  void found() => expect(
        find.descendant(
          of: content,
          matching: find.textContaining(marker, findRichText: true),
        ),
        findsWidgets,
        reason: reason,
      );
  if (autoUpdateGoldenFiles) {
    await expectTomGolden(tester, shot, path);
    found();
  } else {
    found();
    await expectTomGolden(tester, shot, path);
  }
}
