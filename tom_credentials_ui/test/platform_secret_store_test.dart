/// The platform secret store against flutter_secure_storage's method channel,
/// answered by the test, so no real keychain is touched.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_credentials_ui/desktop.dart';

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(_secureChannel, null));

  group('SECRET-STORE platform secret store', () {
    test(
        'SECRET-STORE-1: TomPlatformSecretStore writes, reads and deletes '
        'one prefixed entry through flutter_secure_storage\'s channel',
        () async {
      final keychain = <String, String>{};
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_secureChannel, (call) async {
        calls.add(call);
        final args = (call.arguments as Map).cast<String, Object?>();
        switch (call.method) {
          case 'write':
            keychain[args['key']! as String] = args['value']! as String;
            return null;
          case 'read':
            return keychain[args['key']! as String];
          case 'delete':
            keychain.remove(args['key']);
            return null;
        }
        return null;
      });
      // The options the plugin sends are chosen by the target platform.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const store = TomPlatformSecretStore(keyPrefix: 'app.settingsKey.');

      expect(await store.read('h1'), isNull,
          reason: 'a miss is an answer, not an error');
      await store.write('h1', 'master-key');
      expect(keychain, {'app.settingsKey.h1': 'master-key'});
      expect(await store.read('h1'), 'master-key');
      await store.delete('h1');
      expect(keychain, isEmpty);

      expect(calls.map((c) => c.method), ['read', 'write', 'read', 'delete']);
      for (final call in calls) {
        final options = (call.arguments as Map)['options'] as Map;
        expect(options['usesDataProtectionKeychain'], 'false',
            reason: 'the ad-hoc signed sandboxed build has no keychain '
                'access group, so the data-protection keychain refuses '
                'every call (-34018)');
      }
    });

    test(
        'SECRET-STORE-2: a keychain failure surfaces as the platform error, so '
        'the bootstrap can tell it from a miss', () async {
      messenger.setMockMethodCallHandler(_secureChannel, (call) async {
        throw PlatformException(
            code: 'Unexpected security result code',
            message: 'Code: -34018, Message: A required entitlement '
                "isn't present.");
      });
      const store = TomPlatformSecretStore(
        keyPrefix: 'app.settingsKey.',
        storage: FlutterSecureStorage(),
      );
      await expectLater(store.read('h1'), throwsA(isA<PlatformException>()));
    });
  });
}
