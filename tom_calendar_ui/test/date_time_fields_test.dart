/// The D9 §3.2 timezone boundary, in the two fields that are it.
///
/// UTC is the *canonical storage* form and local the *display* form: the field
/// converts to the device's local timezone for rendering and converts input
/// back to UTC. A field that worked entirely in UTC let a user in UTC+8 who
/// typed 17:00 store 17:00Z — eight hours from the meeting.
///
/// Every assertion is **relative to the running zone**; the suite is
/// additionally run in several zones by `tool/test_in_zones.sh`. Under UTC the
/// two frames coincide, so the tests that need a shift to mean anything skip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';
import 'package:tom_calendar_ui/tom_calendar_ui.dart';

/// Whether this process can tell the two frames apart at all.
final bool _shifted = DateTime.now().timeZoneOffset != Duration.zero;

/// `testWidgets` takes a `bool?` rather than the `test` package's reason
/// string, so the reason lives here: these two cases compare the local frame
/// against the UTC one, and under UTC there is nothing to compare.
final bool _skipInUtc = !_shifted;

DateTime? emitted;

Widget dateHost(DateTime value, {bool local = true}) => MaterialApp(
      home: Scaffold(
        body: TomDateField(
          label: 'Starts',
          value: value,
          frame: local ? CalendarTimeFrame.device : CalendarTimeFrame.utc,
          onChanged: (v) => emitted = v,
        ),
      ),
    );

Widget timeHost(DateTime value) => MaterialApp(
      home: Scaffold(
        body: TomTimeField(
          label: 'Time',
          value: value,
          frame: CalendarTimeFrame.device,
          onChanged: (v) => emitted = v,
        ),
      ),
    );

String textOf(WidgetTester tester) =>
    tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text;

void main() {
  setUp(() => emitted = null);

  group('WONEPRPC11 — the time field is the boundary', () {
    testWidgets('WONEPRPC11-9: a stored instant renders as its LOCAL time',
        (t) async {
      // 09:00 local, whatever that is in UTC here.
      final stored = DateTime(2026, 7, 22, 9).toUtc();
      await t.pumpWidget(timeHost(stored));

      expect(textOf(t), '09:00:00',
          reason: 'the user reads the hour they would have typed');
    });

    testWidgets('WONEPRPC11-10: and it is NOT the UTC wall clock', (t) async {
      final stored = DateTime(2026, 7, 22, 9).toUtc();
      await t.pumpWidget(timeHost(stored));

      final utcHour = stored.toUtc().hour.toString().padLeft(2, '0');
      expect(textOf(t), isNot('$utcHour:00:00'),
          reason: 'this is the whole defect: the field used to show the UTC '
              'wall clock, so a 17:00 meeting read as 09:00');
    }, skip: _skipInUtc);

    testWidgets('WONEPRPC11-11: typing a local time emits the matching UTC '
        'instant', (t) async {
      await t.pumpWidget(timeHost(DateTime(2026, 7, 22, 9).toUtc()));

      await t.enterText(find.byType(TextFormField), '17:30:00');
      await t.pump();

      expect(emitted, DateTime(2026, 7, 22, 17, 30).toUtc(),
          reason: 'the user types where they are; the document stores UTC');
      expect(emitted!.isUtc, isTrue,
          reason: 'the model is UTC-only and the field is what keeps it so');
    });

    testWidgets('WONEPRPC11-12: a typed time near midnight moves the stored '
        'DATE, not just the hour', (t) async {
      // The case a per-field conversion gets wrong: composing a typed local
      // time onto the *UTC* date keeps the instant on the wrong day.
      await t.pumpWidget(timeHost(DateTime(2026, 7, 22, 12).toUtc()));

      await t.enterText(find.byType(TextFormField), '23:30:00');
      await t.pump();

      expect(emitted, DateTime(2026, 7, 22, 23, 30).toUtc());
      expect(emitted!.toLocal().day, 22,
          reason: 'still the 22nd where the user is, whatever the UTC date is');
    });

    testWidgets('WONEPRPC11-13: the round trip is the identity', (t) async {
      await t.pumpWidget(timeHost(DateTime(2026, 7, 22, 9).toUtc()));
      await t.enterText(find.byType(TextFormField), '17:30:00');
      await t.pump();

      await t.pumpWidget(timeHost(emitted!));
      await t.pumpAndSettle();

      expect(textOf(t), '17:30:00',
          reason: 'reopening shows what was typed — the property the UTC-only '
              'field silently broke');
    });
  });

  group('WONEPRPC11 — the date field, and the §3.3 exemption', () {
    testWidgets('WONEPRPC11-14: a timed value renders its LOCAL date',
        (t) async {
      // 23:00 local on the 22nd: in an eastern zone the stored UTC date is the
      // 22nd, in a western one the 23rd — and the field shows the 22nd in both.
      await t.pumpWidget(dateHost(DateTime(2026, 7, 22, 23).toUtc()));

      expect(textOf(t), '2026-07-22');
    });

    testWidgets('WONEPRPC11-15: typing a date keeps the LOCAL time of day',
        (t) async {
      await t.pumpWidget(dateHost(DateTime(2026, 7, 22, 9).toUtc()));

      await t.enterText(find.byType(TextFormField), '2026-08-03');
      await t.pump();

      expect(emitted, DateTime(2026, 8, 3, 9).toUtc(),
          reason: '"change the date, keep the time" means the time the user '
              'can see — composing a local date onto a UTC hour would shift '
              'the event by the offset on every date edit');
    });

    testWidgets('WONEPRPC11-16: an ALL-DAY date does not move (§3.3)',
        (t) async {
      // Timezone-free. The stored value is a date-only UTC midnight, and
      // converting it through local time moves the day at either end of the
      // world — which is the one conversion §3.3 forbids.
      await t.pumpWidget(
          dateHost(DateTime.utc(2026, 7, 22), local: false));

      expect(textOf(t), '2026-07-22');
    });

    testWidgets('WONEPRPC11-17: and editing an all-day date emits a date-only '
        'UTC instant', (t) async {
      await t.pumpWidget(
          dateHost(DateTime.utc(2026, 7, 22), local: false));

      await t.enterText(find.byType(TextFormField), '2026-08-03');
      await t.pump();

      expect(emitted, DateTime.utc(2026, 8, 3),
          reason: 'no offset is applied in either direction');
      expect(emitted!.hour, 0);
    });

    testWidgets('WONEPRPC11-18: the two modes genuinely differ on the same '
        'instant', (t) async {
      // The guard that makes `local` load-bearing rather than decorative: one
      // stored value, two frames, two dates.
      //
      // The instant is chosen on the side the running zone shifts *toward*.
      // A single literal cannot do it: 23:00Z is already tomorrow east of UTC
      // and still today west of it, so a fixed choice tests nothing in half
      // the world — which is the same one-frame assumption this todo is about,
      // made in a test instead of in a widget.
      final eastward = DateTime.now().timeZoneOffset > Duration.zero;
      final instant = eastward
          ? DateTime.utc(2026, 7, 22, 23)
          : DateTime.utc(2026, 7, 22, 1);
      await t.pumpWidget(dateHost(instant, local: false));
      final asStored = textOf(t);

      await t.pumpWidget(dateHost(instant));
      await t.pumpAndSettle();
      final asLocal = textOf(t);

      expect(asStored, '2026-07-22');
      expect(asLocal, isNot(asStored),
          reason: 'an instant an hour from a UTC day boundary lands on the '
              'other calendar day wherever the clock is shifted');
    }, skip: _skipInUtc);
  });
}
