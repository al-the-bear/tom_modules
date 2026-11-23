// Fenced code in the Markdown renderer is highlighted by tom_text_highlight
// for the languages it knows, in the renderer's palette; other languages are
// plain. The source editor takes a SyntaxHighlighter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_editors/tom_file_editors.dart';

/// The leaf spans of the code block [n] with their colours.
List<(String, Color?)> codeSpans(WidgetTester tester, int n) {
  final block = find.byKey(Key('tom-markdown-code-$n'));
  final rich = tester.widget<RichText>(
    find.descendant(of: block, matching: find.byType(RichText)).first,
  );
  final out = <(String, Color?)>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null && span.text!.isNotEmpty) {
      out.add((span.text!, span.style?.color));
    }
    return true;
  });
  return out;
}

void main() {
  testWidgets('FILE-ED-H1: a JSON, YAML and shell block is highlighted, a '
      'Python block is plain', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TomMarkdownRendered(
            markdown:
                '```json\n{"a": 1}\n```\n\n'
                '```yaml\nkey: "v"\n```\n\n'
                '```sh\necho \$HOME\n```\n\n'
                '```python\nprint(1)\n```\n',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final json = codeSpans(tester, 0);
    final key = json.firstWhere((s) => s.$1 == '"a"');
    final number = json.firstWhere((s) => s.$1 == '1');
    expect(key.$2, isNotNull);
    expect(number.$2, isNotNull);
    expect(key.$2, isNot(number.$2));
    final yaml = codeSpans(tester, 1);
    expect(
      yaml.firstWhere((s) => s.$1 == 'key').$2,
      key.$2,
      reason: 'a YAML key is an attr like a JSON key',
    );
    expect(yaml.firstWhere((s) => s.$1 == '"v"').$2, isNotNull);
    final shell = codeSpans(tester, 2);
    expect(shell.firstWhere((s) => s.$1 == 'echo').$2, isNotNull);
    final python = codeSpans(tester, 3);
    expect([for (final s in python) s.$2].whereType<Color>(), isEmpty);
  });

  testWidgets('FILE-ED-H2: the source editor draws its SyntaxHighlighter\'s '
      'spans', (tester) async {
    late ColorScheme colors;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              colors = Theme.of(context).colorScheme;
              return TomTextSource(
                text: 'key: "v" # c',
                readOnly: false,
                onChanged: (_) {},
                highlighter: tomYamlSourceHighlighter(colors),
              );
            },
          ),
        ),
      ),
    );
    final field = tester.widget<EditableText>(find.byType(EditableText));
    final span = field.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    );
    final colours = <String, Color?>{};
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) colours[s.text!] = s.style?.color;
      return true;
    });
    expect(colours['key'], colors.primary);
    expect(colours['"v"'], colors.tertiary);
    expect(colours['# c'], colors.onSurfaceVariant);
  });
}
