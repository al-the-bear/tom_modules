// Tests for the reusable live placeholder preview (§11.5, §12, OE-14). The
// widget expands a placeholder-bearing string via an injected `compose` and
// must render an unsupported-expression error inline rather than crash.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';
import 'package:tom_agentic_ui/tom_agentic_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('PlaceholderPreview (OE-14)', () {
    testWidgets('renders the composed expansion of a non-empty source',
        (tester) async {
      await _pump(
        tester,
        PlaceholderPreview(
          source: r'Hi ${name}!',
          compose: (s) async => s.replaceAll(r'${name}', 'Alex'),
        ),
      );
      await tester.pump();
      expect(find.text('Hi Alex!'), findsOneWidget);
    });

    testWidgets('renders the empty hint when the source is blank',
        (tester) async {
      await _pump(
        tester,
        PlaceholderPreview(
          source: '   ',
          compose: (s) async => s,
          emptyHint: 'no preview',
        ),
      );
      expect(find.text('no preview'), findsOneWidget);
      expect(find.byKey(const Key('placeholder-preview-body')), findsNothing);
    });

    testWidgets('renders a thrown unsupported-expression error inline, not a '
        'crash', (tester) async {
      await _pump(
        tester,
        PlaceholderPreview(
          source: r'compute ${{ 1 + 1 }}',
          compose: (_) => throw PlaceholderExpressionsUnsupportedError('1 + 1'),
        ),
      );
      await tester.pump();
      // The widget swallows the throw and surfaces its message in the preview.
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('PlaceholderExpressionsUnsupportedError'),
        findsOneWidget,
      );
    });

    testWidgets('shows the latest source\'s expansion: one overtaken by a '
        'newer source is dropped, even when it completes last', (tester) async {
      final slow = Completer<String>();
      Future<String> compose(String s) =>
          s == 'first' ? slow.future : Future.value('expanded $s');
      Widget preview(String source) =>
          PlaceholderPreview(source: source, compose: compose);

      await _pump(tester, preview('first'));
      await _pump(tester, preview('second'));
      await tester.pump();
      expect(find.text('expanded second'), findsOneWidget);

      slow.complete('expanded first');
      await tester.pump();
      expect(find.text('expanded second'), findsOneWidget);
      expect(find.text('expanded first'), findsNothing);
    });
  });
}
