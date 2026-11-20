/// What can be checked of the Mermaid view without a webview: the bundled
/// mermaid.js and its licence, the themes, and the widget's first frame.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_mermaid_view/tom_mermaid_view.dart';

void main() {
  test(
      'MV-1: the asset is mermaid.js 11.13.0 with its MIT licence beside '
      'it, declared in the pubspec and named in THIRD_PARTY.md', () {
    final script = File('assets/js/mermaid.min.js');
    expect(script.existsSync(), isTrue);
    expect(script.lengthSync(), greaterThan(2 * 1024 * 1024));
    expect(script.readAsStringSync(), contains('11.13.0'));
    final licence = File('assets/js/LICENSE').readAsStringSync();
    expect(licence, startsWith('The MIT License'));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/js/mermaid.min.js'),
    );
    expect(File('THIRD_PARTY.md').readAsStringSync(), contains('11.13.0'));
  });

  testWidgets('MV-2: the asset loads under the package key the view reads', (
    tester,
  ) async {
    final script = await tester.runAsync(
      () => rootBundle.loadString(
        'packages/tom_mermaid_view/assets/js/mermaid.min.js',
      ),
    );
    expect(script, contains('mermaid'));
  });

  test('MV-3: each theme carries the name mermaid.js initialises it by', () {
    expect({
      for (final t in MermaidTheme.values) t: t.jsName
    }, {
      MermaidTheme.light: 'default',
      MermaidTheme.dark: 'dark',
      MermaidTheme.neutral: 'neutral',
      MermaidTheme.forest: 'forest',
    });
  });

  testWidgets(
      'MV-4: the first frame is a loading indicator of the minimum '
      'height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MermaidWebView(source: 'graph TD; A-->B;', minHeight: 80),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byType(MermaidWebView)).height,
      80,
    );
  });
}
