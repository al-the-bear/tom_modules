/// `TomDesktopClipboardPort` — the protected-value binding for desktop hosts:
/// concealed and cleared by change count on macOS through the host's runner,
/// and the portable text comparison everywhere else.
///
/// Test ids are those the guarantees were first written under (WONEQR36).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_host_ui/desktop.dart';

const _channel = MethodChannel('test/clipboard');

/// The system clipboard as `SystemChannels.platform` sees it.
class _PlatformClipboard {
  String? text;
  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'Clipboard.setData':
        text = (call.arguments as Map)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return text == null ? null : {'text': text};
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _PlatformClipboard platform;
  setUp(() {
    platform = _PlatformClipboard();
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      platform.handle,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(_channel, null);
  });

  group('WONEQR36 desktop clipboard', () {
    test('WONEQR36-B20: on macOS the runner places the value concealed and the '
        'clear is by change count — a later copy of the same text survives '
        '[1002]', () async {
      var changeCount = 41;
      final runner = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        runner.add(call);
        switch (call.method) {
          case 'placeConcealed':
            return ++changeCount;
          case 'clearIfUnchanged':
            final count = (call.arguments as Map)['changeCount'];
            if (count != changeCount) return false;
            changeCount++;
            return true;
        }
        return null;
      });
      const port = TomDesktopClipboardPort(
        channel: _channel,
        platform: 'macos',
      );

      final receipt = await port.placeConcealed('hunter2');
      expect(receipt?.generation, 42);
      expect(runner.single.arguments, {'text': 'hunter2'});
      expect(
        platform.calls,
        isEmpty,
        reason: 'the runner placed it; Flutter\'s clipboard was not used',
      );
      expect(await port.clearIfHolding(receipt!), isTrue);
      expect(runner.last.arguments, {'changeCount': 42});

      // The same text placed again by somebody else is a new change count.
      final second = await port.placeConcealed('hunter2');
      changeCount++; // the user copied over it
      expect(await port.clearIfHolding(second!), isFalse);
    });

    test('WONEQR36-B21: a macOS host whose runner does not answer, and a Linux '
        'or Windows host, get the portable text comparison', () async {
      for (final os in ['macos', 'linux', 'windows']) {
        platform.text = null;
        const port = TomDesktopClipboardPort(
          channel: _channel,
          platform: 'macos',
        );
        final chosen = os == 'macos'
            ? port
            : TomDesktopClipboardPort(channel: _channel, platform: os);
        final receipt = await chosen.placeConcealed('token-$os');
        expect(receipt?.generation, isNull, reason: os);
        expect(platform.text, 'token-$os');

        platform.text = 'mine';
        expect(await chosen.clearIfHolding(receipt!), isFalse, reason: os);
        expect(platform.text, 'mine');

        platform.text = 'token-$os';
        expect(await chosen.clearIfHolding(receipt), isTrue, reason: os);
        expect(platform.text, isEmpty);
      }
    });

    testWidgets(
      'WONEQR36-B22: the service over the desktop port clears after the '
      'configured delay, on the test binding\'s fake clock',
      (tester) async {
        // The binding's fake clock drives the real Timer the service arms by
        // default.
        final clip = TomProtectedClipboard(
          port: const TomDesktopClipboardPort(
            channel: _channel,
            platform: 'linux',
          ),
          clearAfter: () => const Duration(seconds: 12),
        );
        await clip.copy('secret');
        expect(platform.text, 'secret');
        await tester.pump(const Duration(seconds: 11));
        expect(platform.text, 'secret');
        await tester.pump(const Duration(seconds: 1));
        expect(platform.text, isEmpty);
      },
    );
  });
}
