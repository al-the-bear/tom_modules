/// The golden harness's checks, each with a case that must fail: the path
/// check refuses a drawn machine path and a path held in a text field and
/// passes one relative to the package; the contrast check refuses light grey
/// on white and exempts a disabled control; the text-fit check refuses a cut
/// label; a known-red case is skipped with its reason; the bundled emoji face
/// resolves and draws emoji rather than boxes.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_testing/tom_ui_testing.dart';
import 'package:tom_ui_support/tom_ui_support.dart' show tomContrastRatio;

Future<Finder> _pump(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: KeyedSubtree(key: key, child: child)),
  ));
  return find.byKey(key);
}

/// The trail's heading emoji, the kind of glyph a test font has no face for.
const List<String> _emoji = [
  '🚀', '🧠', '💬', '🔧', '📤', '🔁', '✅', '⚠️', '⏹️', '📊', //
];

/// A private-use code point no loaded face holds: always the box.
const String _missing = '\u{10FFFD}';

final GlobalKey _boundary = GlobalKey();

Future<List<int>> _draw(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Apple Symbols', 'Apple Color Emoji'],
      ),
      home: Material(
        child: Center(
          child: RepaintBoundary(
            key: _boundary,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Center(
                child: Text(text, style: const TextStyle(fontSize: 32)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List().toList();
  });
  return bytes!;
}

void main() {
  final package = Directory.current.absolute.path;

  group('GOLDEN-P the path check', () {
    test('GOLDEN-P1: the machine paths are the home directory and the '
        'package root, and a home-relative path counts', () {
      final paths = tomMachinePaths();
      expect(paths, contains(package));
      final home = Platform.environment['HOME'];
      if (home != null && home.length > 1) expect(paths, contains(home));
      expect(tomMachinePathIn('$package/testlog/x.log'), isNotNull);
      expect(tomMachinePathIn('testlog/data/device.yaml'), isNull);
      expect(tomMachinePathIn('~/Desktop/…/root/ws'), '~/');
      expect(tomMachinePathIn('Watching (~/x)'), '~/');
      expect(tomMachinePathIn('~1 escapes / in a JSON pointer'), isNull);
      expect(tomMachinePathIn('a~/b'), isNull);
      expect(tomMachinePathIn('~/testlog/root/ws'), isNull);
      expect(tomGoldenHome, package);
    });

    testWidgets('GOLDEN-P2: a drawn absolute path fails', (tester) async {
      final finder =
          await _pump(tester, Text('Kept in $package/testlog/data'));
      expect(() => expectTomNoMachinePaths(tester, finder, shot: 'p2.png'),
          throwsA(isA<TestFailure>()));
    });

    testWidgets('GOLDEN-P3: a path in a text field fails', (tester) async {
      final finder = await _pump(
        tester,
        TextField(controller: TextEditingController(text: '$package/trails')),
      );
      expect(() => expectTomNoMachinePaths(tester, finder),
          throwsA(isA<TestFailure>()));
    });

    testWidgets('GOLDEN-P4: a path relative to the package passes',
        (tester) async {
      final finder = await _pump(
        tester,
        const Column(children: [
          Text('testlog/goldens_data/logs/app.log'),
          TextField(),
        ]),
      );
      expectTomNoMachinePaths(tester, finder);
    });
  });

  group('GOLDEN-C the contrast check', () {
    testWidgets('GOLDEN-C1: light grey on white fails and names where; dark '
        'text passes', (tester) async {
      final finder = await _pump(
        tester,
        const ColoredBox(
          color: Colors.white,
          child: Column(children: [
            Text('readable', style: TextStyle(color: Colors.black)),
            Text('faint',
                key: ValueKey('faint-label'),
                style: TextStyle(color: Color(0xFFDDDDDD))),
          ]),
        ),
      );
      final findings = findTomLowContrast(tester, finder);
      expect(findings, hasLength(1));
      expect(findings.single.text, 'faint');
      expect(findings.single.ratio, lessThan(4.5));
      expect('${findings.single}', contains('faint-label'));
      expect(() => expectTomReadable(tester, finder, shot: 'c1.png'),
          throwsA(isA<TestFailure>()));
    });

    testWidgets('GOLDEN-C2: a disabled control is exempt, as WCAG exempts it',
        (tester) async {
      final finder = await _pump(
        tester,
        const ColoredBox(
          color: Colors.white,
          child: TextButton(
            onPressed: null,
            child: Text('off', style: TextStyle(color: Color(0xFFEEEEEE))),
          ),
        ),
      );
      expectTomReadable(tester, finder);
    });

    testWidgets('GOLDEN-C4: an ink response nothing can press is a disabled '
        'control — exempt, and reported with that reason', (tester) async {
      final finder = await _pump(
        tester,
        const ColoredBox(
          color: Colors.white,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('toolbar-undo'),
              child: Icon(Icons.undo, color: Color(0xFFEEEEEE)),
            ),
          ),
        ),
      );
      final scan = tomContrastScan(tester, finder);
      expect(scan.findings, isEmpty);
      expect(scan.exempted, hasLength(1));
      expect(scan.exempted.single.reason, tomContrastDisabled);
      expect('${scan.exempted.single}', contains('toolbar-undo'));
      expectTomReadable(tester, finder);
    });

    testWidgets('GOLDEN-C5: the same ink response with a handler is held to '
        'the rule', (tester) async {
      final finder = await _pump(
        tester,
        ColoredBox(
          color: Colors.white,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {},
              child: const Icon(Icons.undo, color: Color(0xFFEEEEEE)),
            ),
          ),
        ),
      );
      final scan = tomContrastScan(tester, finder);
      expect(scan.exempted, isEmpty);
      expect(scan.findings, hasLength(1));
    });

    test('GOLDEN-C3: the ratio is the readable-colour helper\'s', () {
      expect(tomContrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    });
  });

  group('GOLDEN-T the text-fit check', () {
    testWidgets('GOLDEN-T1: a label cut by its box fails; one that fits '
        'passes', (tester) async {
      final fits = await _pump(tester, const Text('short'));
      expectTomTextWhole(tester, fits);
      final cut = await _pump(
        tester,
        const SizedBox(
          width: 40,
          child: Text('a label much too long for its box',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
      expect(() => expectTomTextWhole(tester, cut),
          throwsA(isA<TestFailure>()));
    });
  });

  group('GOLDEN-K skipping and comparing', () {
    test('GOLDEN-K1: a known-red case is skipped with its sentence on macOS; '
        'elsewhere every case is skipped for the platform', () {
      final skip = tomGoldenSkipFor('a', knownRed: {'a': 'x1 fixes it'});
      if (Platform.isMacOS) {
        expect(skip, 'KNOWN RED until x1 fixes it');
        expect(tomGoldenSkipFor('b', knownRed: {'a': 'x1'}), isNull);
      } else {
        expect(skip, tomGoldenSkipReason);
      }
    });

    testWidgets('GOLDEN-K2: a golden is refused without the testlog '
        'comparator, so failures never land beside the test', (tester) async {
      final finder = await _pump(tester, const Text('x'));
      final before = goldenFileComparator;
      addTearDown(() => goldenFileComparator = before);
      await expectLater(
        () => expectTomGolden(tester, finder, 'never.png'),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('GOLDEN-K3: the comparator puts failures in testlog/goldens',
        (tester) async {
      final before = goldenFileComparator;
      addTearDown(() => goldenFileComparator = before);
      useTomTestlogComparator('test/golden_harness_test.dart');
      final comparator = goldenFileComparator as TomTestlogGoldenComparator;
      expect(comparator.failureDir.pathSegments.where((s) => s.isNotEmpty),
          containsAllInOrder(['testlog', 'goldens']));
      expect(Directory.fromUri(comparator.failureDir).existsSync(), isTrue);
    });
  });

  group('GOLDEN-F the fonts', () {
    test('GOLDEN-F1: the emoji font resolves, is a TrueType font, and its OFL '
        'licence sits beside it', () {
      final font = tomGoldenEmojiFontFile();
      final bytes = font.readAsBytesSync();
      expect(bytes.length, greaterThan(100000));
      expect(bytes.sublist(0, 4), [0, 1, 0, 0]);
      final names =
          font.parent.listSync().map((e) => e.uri.pathSegments.last);
      expect(names, contains('OFL.txt'));
    });

    testWidgets('GOLDEN-F2: every emoji is drawn from a face, not as the '
        'missing-glyph box; and two missing glyphs draw alike, so the '
        'comparison can fail', (tester) async {
      final skip = tomGoldenSkipReason;
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      await tester.runAsync(loadTomGoldenFonts);
      final box = await _draw(tester, _missing);
      expect(await _draw(tester, '\u{10FFFC}'), box);
      for (final emoji in _emoji) {
        expect(await _draw(tester, emoji), isNot(equals(box)),
            reason: '$emoji is drawn as a box');
      }
    });
  });
}
