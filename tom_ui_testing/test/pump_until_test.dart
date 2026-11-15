/// `tester.pumpUntil` against a load that finishes in **real** time, which is
/// the one shape `pumpAndSettle` cannot wait for.
///
/// The widget below is a panel's loading state in miniature: an indeterminate
/// progress indicator while a future is pending, the content once it
/// resolves. The future is started inside `runAsync`, so it completes
/// on the real clock the way a request to a real server does — and the suite
/// first reproduces the premise offline (a settle over it times out), then
/// shows the wait that ends when the load does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tom_ui_testing/tom_ui_testing.dart';

const loading = Key('load-in-flight');
const loaded = Key('load-arrived');

/// Shows [loading] until [load] completes, then [loaded] with its value.
class _Loader extends StatefulWidget {
  final Future<String> load;
  const _Loader(this.load);

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  String? _value;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.load.then((value) {
        if (mounted) setState(() => _value = value);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value == null) {
      return const Row(
        key: loading,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          Text('Loading comments…'),
        ],
      );
    }
    return Text(value, key: loaded);
  }
}

Widget host(Future<String> load) =>
    MaterialApp(home: Scaffold(body: _Loader(load)));

/// A load that resolves after [after] of real time, started where real time
/// runs — created inside `runAsync` and handed back by reference, since an
/// `async` closure returning it would hand back its value instead.
Future<Future<String>> realLoad(WidgetTester tester, Duration after) async {
  late Future<String> load;
  await tester.runAsync(() async {
    load = Future<String>.delayed(after, () => 'The thread');
  });
  return load;
}

void main() {
  testWidgets(
    'PUMP-UNTIL-1: a settle over a real-time load times out on the spinner — '
    'the premise, reproduced offline — and pumpUntil ends when the load '
    'does',
    (tester) async {
      // Started before the load, so what is measured is the load itself: the
      // settle below spends an unpredictable share of the load's real time
      // (0.8 s of it under a full suite's load, measured), so a stopwatch
      // started after it measured the machine rather than the property.
      final clock = Stopwatch()..start();
      const loadTime = Duration(milliseconds: 1500);
      final load = await realLoad(tester, loadTime);
      await tester.runAsync(() => tester.pumpWidget(host(load)));
      expect(find.byKey(loading), findsOneWidget);

      // The fake clock runs through a second in no real time at all, the
      // indicator schedules a frame on every pump, and the load is nowhere
      // near done.
      // Caught rather than `expectLater`-ed: a settle is a guarded tester
      // call, and a second guarded call while it is in flight is refused as
      // a guard conflict before the timeout can be observed.
      FlutterError? settle;
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 1),
        );
      } on FlutterError catch (error) {
        settle = error;
      }
      expect(
        settle,
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('pumpAndSettle timed out'),
        ),
      );
      expect(
        find.byKey(loading),
        findsOneWidget,
        reason: 'the settle gave up; the load is still in flight',
      );

      await tester.pumpUntil(find.byKey(loaded), what: 'the thread');
      expect(
        clock.elapsed,
        greaterThanOrEqualTo(loadTime),
        reason: 'the wait lasted as long as the load, in real time',
      );
      expect(find.byKey(loading), findsNothing);
      expect(find.text('The thread'), findsOneWidget);
    },
  );

  testWidgets(
    'PUMP-UNTIL-2: pumpUntilGone ends when the loading state ends, and a '
    'settle after it is safe',
    (tester) async {
      final load = await realLoad(tester, const Duration(milliseconds: 600));
      await tester.runAsync(() => tester.pumpWidget(host(load)));

      await tester.pumpUntilGone(find.byKey(loading), what: 'the spinner');
      expect(find.byKey(loaded), findsOneWidget);
      // Nothing is in flight now, so a settle has something to settle to.
      await tester.pumpAndSettle();
      expect(find.byKey(loaded), findsOneWidget);
    },
  );

  testWidgets(
    'PUMP-UNTIL-3: a load that never arrives fails on the deadline, naming '
    'what was waited for and what the screen held',
    (tester) async {
      final load = await realLoad(tester, const Duration(minutes: 1));
      await tester.runAsync(() => tester.pumpWidget(host(load)));

      await expectLater(
        tester.pumpUntil(
          find.byKey(loaded),
          what: "the section's thread",
          timeout: const Duration(milliseconds: 700),
          hint: 'The store is the subject here, not the panel.',
        ),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(
              contains("for the section's thread and it never arrived"),
              contains("'Loading comments…'"),
              contains("'load-in-flight'"),
              contains('The store is the subject here, not the panel.'),
            ),
          ),
        ),
      );
    },
  );

  testWidgets(
    'PUMP-UNTIL-4: pumpUntilTrue waits on a condition the screen does not '
    'show — a value arriving outside the tree',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('idle')));
      String? arrived;
      await tester.runAsync(() async {
        // Started here, completed in real time; nothing in the tree changes.
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 400),
          ).then((_) => arrived = 'written'),
        );
      });
      expect(arrived, isNull);
      await tester.pumpUntilTrue(() => arrived != null, what: 'the write');
      expect(arrived, 'written');
    },
  );

  testWidgets(
    'PUMP-UNTIL-5: describeTomScreen lists texts and string keys, and says how '
    'many the cap hid',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (var i = 0; i < 5; i++) Text('row $i', key: Key('row-$i')),
              const Text('   '),
              const SizedBox(key: ValueKey<int>(7)),
            ],
          ),
        ),
      );
      final screen = describeTomScreen(tester, cap: 3);
      expect(
        screen,
        "texts: ['row 0', 'row 1', 'row 2', … +2]; "
        "keys: ['row-0', 'row-1', 'row-2', … +2]",
        reason: 'blank text and a non-string key are not worth a line',
      );
      expect(
        describeTomScreen(tester),
        contains("'row 4']"),
        reason: 'under the default cap nothing is hidden',
      );
    },
  );
}
