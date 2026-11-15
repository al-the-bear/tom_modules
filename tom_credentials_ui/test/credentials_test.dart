import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_credentials_ui/tom_credentials_ui.dart';

class Picker implements TomKeyFilePicker {
  @override
  Future<TomKeyFile?> pickKeyFile(BuildContext context) async =>
      TomKeyFile(locator: '/keys/home.key', bytes: Uint8List.fromList([1]));
}

/// A host with a button that runs [onPressed] against a context below the
/// navigator.
Widget host(void Function(BuildContext context) onPressed) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        key: const Key('go'),
        onPressed: () => onPressed(context),
        child: const Text('go'),
      ),
    ),
  ),
);

void main() {
  group('CRED-KEY: the key fields, step and prompt', () {
    test('CRED-KEY-1: the controller is ready on the default key or on '
        'material that opens something, and checks a repeat', () {
      final withDefault = TomKeyStepController(hasDefaultKey: true);
      expect(withDefault.ready, isTrue);
      expect(withDefault.request, isNull, reason: 'the default key');
      withDefault.useDefault = false;
      expect(withDefault.ready, isFalse);
      withDefault.passphrase.text = 'secret';
      expect(withDefault.ready, isTrue);
      expect(withDefault.request!.material.passphrase, 'secret');
      expect(withDefault.request!.remember, isTrue);
      expect(withDefault.repeatMatches('secret'), isTrue);
      expect(withDefault.repeatMatches('other'), isFalse);

      final noDefault = TomKeyStepController();
      noDefault.useDefault = true;
      expect(
        noDefault.useDefault,
        isFalse,
        reason: 'there is no default key to choose',
      );
      withDefault.dispose();
      noDefault.dispose();
    });

    testWidgets('CRED-KEY-2: the key-file row needs a picker; choosing and '
        'clearing a file updates the controller', (tester) async {
      final controller = TomKeyStepController();
      addTearDown(controller.dispose);
      Future<void> pump(TomKeyFilePicker? picker, {bool remember = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TomKeyFields(
                  controller: controller,
                  keyPrefix: 'k',
                  keyFiles: picker,
                  offersRemember: remember,
                ),
              ),
            ),
          );
      await pump(null);
      expect(find.byKey(const Key('k-keyfile')), findsNothing);
      expect(find.byKey(const Key('k-remember')), findsOneWidget);
      await pump(Picker(), remember: false);
      expect(find.byKey(const Key('k-remember')), findsNothing);
      await tester.tap(find.byKey(const Key('k-keyfile')));
      await tester.pumpAndSettle();
      expect(controller.keyFile!.name, 'home.key');
      expect(find.text('home.key'), findsOneWidget);
      await tester.tap(find.byKey(const Key('k-keyfile-clear')));
      await tester.pump();
      expect(controller.keyFile, isNull);
    });

    testWidgets('CRED-KEY-3: the prompt names the file, refuses an empty key, '
        'and answers what was typed', (tester) async {
      TomKeyRequest? answer;
      var answered = false;
      await tester.pumpWidget(
        host((context) async {
          answer = await showTomKeyDialog(
            context,
            locator: 'github:acme/docs/plan.webwork.kdbx',
            reason: 'No configured key opens this file.',
          );
          answered = true;
        }),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.text('plan.webwork.kdbx'), findsOneWidget);
      expect(find.text('No configured key opens this file.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tom-key-confirm')));
      await tester.pump();
      expect(answered, isFalse, reason: 'nothing incomplete is submitted');
      await tester.enterText(find.byKey(const Key('tom-key-passphrase')), 'pw');
      await tester.tap(find.byKey(const Key('tom-key-confirm')));
      await tester.pumpAndSettle();
      expect(answered, isTrue);
      expect(answer!.material.passphrase, 'pw');
    });

    testWidgets('CRED-KEY-4: the key step offers the default only when there '
        'is one, and shows the fields for a key of its own', (tester) async {
      final controller = TomKeyStepController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TomKeyStep(
              controller: controller,
              keyPrefix: 's',
              noDefaultKeyLabel: 'No default document key is set.',
            ),
          ),
        ),
      );
      expect(find.text('No default document key is set.'), findsOneWidget);
      expect(find.byKey(const Key('s-passphrase')), findsOneWidget);
    });

    test('CRED-KEY-5: a locator names its file', () {
      expect(tomLocatorFileName('github:a/b/doc.webwork/'), 'doc.webwork');
      expect(tomLocatorFileName(r'C:\docs\x.kdbx'), 'x.kdbx');
      expect(tomLocatorFileName('plain'), 'plain');
    });
  });

  group('CRED-TOKEN: the token dialog, flow and keepers', () {
    testWidgets('CRED-TOKEN-1: the dialog asks for the host only when none is '
        'given, and answers host, secret and account', (tester) async {
      TomToken? answer;
      await tester.pumpWidget(
        host((context) async => answer = await showTomTokenDialog(context)),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.text('Add an access token'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('tom-token-host')), 'h.io');
      await tester.enterText(find.byKey(const Key('tom-token-secret')), 's');
      await tester.enterText(find.byKey(const Key('tom-token-account')), 'me');
      await tester.tap(find.byKey(const Key('tom-token-confirm')));
      await tester.pumpAndSettle();
      expect(
        (answer!.host, answer!.secret, answer!.account),
        ('h.io', 's', 'me'),
      );
    });

    testWidgets('CRED-TOKEN-2: the flow asks when the backend needs a token, '
        'keeps the answer and tries again', (tester) async {
      final source = TomInMemoryTokenSource();
      final keeper = TomSessionTokenKeeper(source);
      var attempts = 0;
      String? result;
      await tester.pumpWidget(
        host((context) async {
          result = await withTomTokenFlow<String>(
            context,
            keeper: keeper,
            action: () async {
              attempts++;
              if (source.listings.isEmpty) {
                throw const TomTokenRequiredException('github.com');
              }
              return 'opened';
            },
          );
        }),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.text('Access token for github.com'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('tom-token-secret')), 't');
      await tester.tap(find.byKey(const Key('tom-token-confirm')));
      await tester.pumpAndSettle();
      expect((attempts, result), (2, 'opened'));
      expect(source.listings.single.host, 'github.com');
    });

    test('CRED-TOKEN-3: without a keeper the refusal is passed on', () async {
      expect(
        () => withTomTokenFlow<void>(
          _NoContext(),
          keeper: null,
          action: () async => throw const TomTokenRequiredException('h'),
        ),
        throwsA(isA<TomTokenRequiredException>()),
      );
    });

    test('CRED-TOKEN-4: a session keeper lists by host and records nothing '
        'beyond the session', () async {
      final keeper = TomSessionTokenKeeper(TomInMemoryTokenSource());
      expect(keeper.keepsBeyondSession, isFalse);
      expect(
        await keeper.storeToken(const TomToken(host: 'b', secret: '1')),
        isFalse,
      );
      await keeper.storeToken(const TomToken(host: 'a', secret: '2'));
      expect([for (final l in await keeper.listTokens()) l.host], ['a', 'b']);
      expect(await keeper.revokeToken('a'), isFalse);
      expect((await keeper.listTokens()).single.host, 'b');
    });
  });

  group('CRED-SIGNIN: the sign-in item', () {
    testWidgets('CRED-SIGNIN-1: signed out it asks for a token for its host; '
        'signed in it names the account and signs out', (tester) async {
      final signIn = TomSignIn(
        host: 'github.com',
        keeper: TomSessionTokenKeeper(TomInMemoryTokenSource()),
        sessionNote: 'Kept for this tab only.',
      );
      addTearDown(signIn.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TomSignInIndicator(controller: signIn)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tom-sign-in-label')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tom-sign-in')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tom-token-secret')), 't');
      await tester.enterText(find.byKey(const Key('tom-token-account')), 'me');
      await tester.tap(find.byKey(const Key('tom-token-confirm')));
      await tester.pumpAndSettle();
      expect(signIn.signedIn!.account, 'me');
      expect(find.text('me@github.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tom-signed-in')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Kept for this tab only.', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tom-sign-out')));
      await tester.pumpAndSettle();
      expect(signIn.signedIn, isNull);
      expect(find.byKey(const Key('tom-sign-in-label')), findsOneWidget);
    });

    test('CRED-SIGNIN-2: the session note can change, and a change notifies '
        'once', () {
      final signIn = TomSignIn(
        host: 'github.com',
        keeper: TomSessionTokenKeeper(TomInMemoryTokenSource()),
        sessionNote: 'Kept for this tab only.',
      );
      addTearDown(signIn.dispose);
      var notified = 0;
      signIn.addListener(() => notified++);
      signIn.sessionNote = 'Kept for this tab only.';
      expect(notified, 0, reason: 'the same note is no change');
      signIn.sessionNote = null;
      expect(signIn.sessionNote, isNull);
      expect(notified, 1);
    });
  });
}

/// A context the flow never reads: with no keeper it rethrows before it would
/// need one.
class _NoContext extends Fake implements BuildContext {}
