/// `tester.pumpUntil(finder)` — the wait for a network-backed action, bound
/// to a `WidgetTester`.
///
/// The policy — ask, let real time pass, pump a frame, repeat until the
/// deadline — is `package:tom_test_support/pump_until.dart`, which says why
/// `pumpAndSettle` cannot do this. This file supplies the three primitives
/// the policy abstracts: real time passes inside `runAsync`, the frame is
/// pumped **outside** it (the binding asserts its zone otherwise, and the
/// assertion says nothing about the test), and the screen is rendered as the
/// texts and string keys the tree holds.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_test_support/pump_until.dart';

/// Three forms, one loop: [pumpUntil] waits for a finder to match,
/// [pumpUntilGone] for it to stop matching, and [pumpUntilTrue] for any
/// condition — a store's state, say, when the widget shows nothing a finder
/// could name.
extension TomPumpUntil on WidgetTester {
  /// Pumps real frames until [finder] matches, or fails after [timeout]
  /// naming [what] (the finder's own description by default) and what was on
  /// screen. [hint] is appended to the failure when the caller knows where to
  /// look first.
  Future<void> pumpUntil(
    Finder finder, {
    String? what,
    Duration timeout = tomDefaultPumpUntilTimeout,
    String? hint,
  }) => pumpUntilTrue(
    () => finder.evaluate().isNotEmpty,
    what: what ?? finder.toString(),
    timeout: timeout,
    hint: hint,
  );

  /// Pumps real frames until [finder] matches nothing — a loading state
  /// ending, a dialog closing.
  Future<void> pumpUntilGone(
    Finder finder, {
    String? what,
    Duration timeout = tomDefaultPumpUntilTimeout,
    String? hint,
  }) => pumpUntilTrue(
    () => finder.evaluate().isEmpty,
    what: what ?? '$finder to be gone',
    timeout: timeout,
    hint: hint,
  );

  /// Pumps real frames until [condition] holds. It must state a *result*,
  /// never the absence of one — see the policy's own documentation.
  Future<void> pumpUntilTrue(
    bool Function() condition, {
    required String what,
    Duration timeout = tomDefaultPumpUntilTimeout,
    String? hint,
  }) async {
    try {
      await tomPumpUntil(
        what: what,
        matches: condition,
        pumpFrame: () => pump(),
        passTime: (step) => runAsync(() => Future<void>.delayed(step)),
        onScreen: () => describeTomScreen(this),
        timeout: timeout,
        hint: hint,
      );
    } on TomPumpUntilTimeout catch (error) {
      fail(error.message);
    }
  }
}

/// The screen as a reader of a failure can use it: every `Text`'s content and
/// every string `ValueKey` in the tree, each list capped so a long page does
/// not bury the report.
String describeTomScreen(WidgetTester tester, {int cap = 40}) {
  final texts = <String>[];
  final keys = <String>[];
  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      final text = widget.data ?? widget.textSpan?.toPlainText();
      if (text != null && text.trim().isNotEmpty) texts.add(text.trim());
    }
    final key = widget.key;
    if (key is ValueKey<String>) keys.add(key.value);
  }
  String list(List<String> items) {
    final shown = items.take(cap).map((s) => "'$s'").join(', ');
    final more = items.length - cap;
    return '[$shown${more > 0 ? ', … +$more' : ''}]';
  }

  return 'texts: ${list(texts)}; keys: ${list(keys)}';
}
