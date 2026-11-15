/// The portable binding over Flutter's clipboard, and the browser entry point
/// as a VM test sees it: "this process could not", never a crash.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_host_ui/web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? held;

  setUp(() {
    held = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          held = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return held == null ? null : {'text': held};
      }
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  test('RUI-1: the Flutter port places plain text and clears it only while '
      'the clipboard still holds it', () async {
    const port = TomFlutterClipboardPort();
    final receipt = await port.placeConcealed('token');
    expect(receipt?.text, 'token');
    expect(receipt?.generation, isNull);
    held = 'mine';
    expect(await port.clearIfHolding(receipt!), isFalse);
    expect(held, 'mine');
    held = 'token';
    expect(await port.clearIfHolding(receipt), isTrue);
    expect(held, isEmpty);
  });

  test('RUI-2: off the web, the browser clipboard reports failed and the '
      'browser print reports nothing printed', () async {
    expect(
      await tomPlaceOnBrowserClipboard(html: '<p>x</p>', text: 'x'),
      TomClipboardPlacement.failed,
    );
    expect(await tomPrintHtmlInBrowser('T', '<p>x</p>'), isNull);
    expect(held, isNull, reason: 'nothing reached the platform clipboard');
  });
}
