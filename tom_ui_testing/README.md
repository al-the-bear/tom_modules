# tom_ui_testing

Test support for Flutter applications' widget tests: a golden harness that
loads real fonts and checks content, contrast and machine paths before
comparing pixels, and a wait for a network-backed action (tester.pumpUntil).

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Golden harness | `lib/src/golden/` | Test support behind `testing.dart`, described below. |
| Network wait | `lib/src/testing/` | Test support behind `testing.dart`: `tester.pumpUntil(finder)`, `pumpUntilGone` and `pumpUntilTrue` (`TomPumpUntil`) let real time pass between frames until a load that finishes in real time has arrived — which `pumpAndSettle` cannot wait for while a progress indicator keeps scheduling frames — and fail naming what was waited for and what the screen held (`describeTomScreen`). The policy is `tom_test_support`'s `tomPumpUntil`. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_ui_testing/tom_ui_testing.dart` | `loadTomGoldenFonts`, `tomGoldenEmojiFontFile`, `useTomTestlogComparator`, `tomGoldenTestWidgets`, `tomGoldenSkipFor`, `expectTomGolden`, `expectTomShot`, `expectTomReadable`, `findTomLowContrast`, `tomContrastScan`, `expectTomNoMachinePaths`, `tomMachinePathIn`, `tomGoldenHome`, `expectTomTextWhole`; `TomPumpUntil`, `describeTomScreen`, `tomDefaultPumpUntilTimeout`, `tomDefaultPumpUntilStep` | a test (imports `flutter_test` and `dart:io`) |

## Dependencies

Flutter, `flutter_test`, `path`, `tom_test_support`, `tom_ui_support`.

## The golden harness

`package:tom_ui_testing/tom_ui_testing.dart` is for an application's golden suite.
A golden is only worth having if a person can look at it and say whether it
is right, so the harness makes a shot readable and every case assert more
than "the same as last time":

- **Real fonts.** `loadTomGoldenFonts` loads Roboto and the Material icons
  from the Flutter SDK the test runs on and registers Roboto under the system
  and monospace family names (the test engine otherwise draws every glyph as a
  box); it registers the macOS `Apple Symbols` face and a bundled monochrome
  Noto Emoji (`fonts/`, SIL OFL 1.1, outside `lib/` and declared as no asset)
  under the names `Apple Symbols` and `Apple Color Emoji`, so a theme that
  falls back to those draws symbols and emoji from a face. Goldens are compared
  on macOS only (`tomGoldenSkipReason`): rasterisation differs per platform.
- **Failures in `testlog/goldens/`.** `useTomTestlogComparator` installs a
  comparator that writes failure images there (gitignored), never beside the
  test; `expectTomGolden` refuses to compare without it.
- **A defect is never a baseline.** `tomGoldenTestWidgets` skips a case listed
  as known red with the sentence naming the work that fixes it, in the report.
- **Content before pixels.** `expectTomShot` checks that a marker is drawn in
  the area that should hold it before comparing, so an empty body fails with
  its reason.
- **Readable.** `expectTomGolden` runs the contrast check first: every visible
  text run and icon reaches WCAG 2.2 AA against the surface painted behind it
  (4.5:1, or 3:1 for large text and icons), disabled and invisible text
  exempt; a finding names the colours and the nearest keyed widgets. A
  disabled control is a Material control switched off, an `InkWell` /
  `InkResponse` nothing can press, or anything whose semantics say it is not
  enabled. `tomContrastScan` returns the findings and the runs an exemption
  skipped, each with its reason (`tomContrastDisabled`, `tomContrastHidden`),
  so a case can assert why a faint control was not held to the rule.
- **No machine paths.** It also refuses a shot that draws the home directory
  of the account running it or the package's absolute root, in a paragraph or
  a text field (`expectTomNoMachinePaths`); give anything that shortens a path
  against the home `tomGoldenHome` so it reads `~/testlog/…` everywhere.
- **Labels drawn whole.** `expectTomTextWhole` asserts a label is neither cut
  nor on more lines than it may take — measured here because the real fonts
  are loaded.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_ui_testing/tom_ui_testing.dart';

void main() {
  setUpAll(() async {
    await loadTomGoldenFonts();
    useTomTestlogComparator('test/goldens/home_test.dart');
  });

  tomGoldenTestWidgets('the home page', 'home', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Hello')));
    await expectTomShot(
      tester,
      shot: find.byType(MaterialApp),
      content: find.byType(MaterialApp),
      marker: 'Hello',
      reason: 'the greeting is drawn',
      path: 'macos/home.png',
    );
  }, knownRed: const {});
}
```

## Tests

`flutter test` from this folder.
