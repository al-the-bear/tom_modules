/// Test support for Flutter applications' widget tests: a golden harness and
/// a wait for a network-backed action.
///
/// Real fonts — Roboto and the Material icons from the Flutter SDK, the macOS
/// symbol face and a bundled emoji face — so a shot shows text rather than
/// boxes (`loadTomGoldenFonts`); failure images in `testlog/goldens/`
/// (`useTomTestlogComparator`); a case that runs on macOS only and is skipped
/// with its reason while it is known to show a defect
/// (`tomGoldenTestWidgets`); and every picture compared only after the
/// content it should show is found (`expectTomShot`), it is found readable
/// against WCAG AA (`expectTomReadable`) and it names no path of the machine
/// taking it (`expectTomNoMachinePaths`). `expectTomTextWhole` checks that a
/// label is drawn whole.
///
/// The wait for a network-backed action, `tester.pumpUntil(finder)`
/// ([TomPumpUntil]), lets real time pass between frames until a condition
/// holds, and its failure says what was on screen ([describeTomScreen]); the
/// deadline and step are `package:tom_test_support/pump_until.dart`'s, which
/// this library re-exports.
///
/// Test support: it depends on `flutter_test` and `dart:io`, so only a test
/// imports it; the default entry point does not.
library;

export 'src/golden/contrast_check.dart';
export 'src/golden/golden_cases.dart';
export 'src/golden/golden_fonts.dart';
export 'src/golden/path_check.dart';
export 'src/golden/text_fit_check.dart';
export 'src/testing/pump_until.dart';
export 'package:tom_test_support/pump_until.dart'
    show tomDefaultPumpUntilStep, tomDefaultPumpUntilTimeout;
