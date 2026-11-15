/// wonetestb24 — D9 §4.1 in the editor: Calendar.app's yearly rule
/// (BYMONTH + BYMONTHDAY restating the start) is presented as a yearly rule
/// with controls rather than the read-only custom badge, is left as written
/// until the user changes it, and an edit writes the plain form.
library;

import 'package:tom_calendar_ui/tom_calendar_ui.dart';
import 'package:tom_calendar_model/tom_calendar_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _apple = 'FREQ=YEARLY;UNTIL=21000826;BYMONTH=8;BYMONTHDAY=26';
final _birthday = DateTime.utc(1990, 8, 26);

Future<List<String?>> _pump(WidgetTester tester, String rule) async {
  final emitted = <String?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TomRecurrenceField(
          value: rule,
          allDay: true,
          seriesStart: _birthday,
          frame: CalendarTimeFrame.utc,
          onChanged: emitted.add,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return emitted;
}

void main() {
  testWidgets('WONETESTB24-E1: the Apple rule is shown as Yearly with its '
      'controls, and nothing is written on opening [1019]', (tester) async {
    final emitted = await _pump(tester, _apple);
    expect(find.byKey(const ValueKey('recurrence-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('recurrence-custom')), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<CalendarRecurrenceFreq?>>(
              find.byKey(const ValueKey('recurrence-freq')))
          .initialValue,
      CalendarRecurrenceFreq.yearly,
    );
    expect(emitted, isEmpty, reason: 'kept verbatim unless edited');
  });

  testWidgets('WONETESTB24-E2: an edit writes the plain yearly form, keeping '
      'the end date [1019]', (tester) async {
    final emitted = await _pump(tester, _apple);
    await tester.enterText(
        find.byKey(const ValueKey('recurrence-interval')), '2');
    await tester.pumpAndSettle();
    expect(emitted.last, 'FREQ=YEARLY;INTERVAL=2;UNTIL=21000826');
  });

  testWidgets('WONETESTB24-E3: a BYMONTH rule that does not restate the start '
      'stays the read-only custom badge [1019]', (tester) async {
    await _pump(tester, 'FREQ=YEARLY;BYMONTH=9;BYMONTHDAY=26');
    expect(find.byKey(const ValueKey('recurrence-custom')), findsOneWidget);
    expect(find.byKey(const ValueKey('recurrence-editor')), findsNothing);
  });
}
