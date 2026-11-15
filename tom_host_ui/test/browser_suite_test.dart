/// Runs the browser-only tests, so that they run at all.
///
/// `test/browser/` carries `@TestOn('browser')` files, which an ordinary
/// `flutter test` skips silently. They are the only place `web.dart`'s two
/// browser halves are executed rather than compiled: the print frame and the
/// two-flavour `ClipboardItem`. So the package's own suite drives them on
/// Chrome (`tom_test_support`'s `TomBrowserSuite`) and fails if they do not
/// pass.
@Timeout(Duration(minutes: 10))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_test_support/tom_test_support.dart';

void main() {
  final suite = TomBrowserSuite();

  test('RUI-B0: test/browser passes on Chrome', () async {
    final failure = TomBrowserSuite.failureOf(await suite.run());
    expect(failure, isNull, reason: failure);
  }, skip: suite.skipReason);
}
