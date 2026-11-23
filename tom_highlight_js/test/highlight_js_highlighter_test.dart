import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_highlight_js/tom_highlight_js.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

/// The text of every token of [type] in [source].
List<String> textsOf(String source, String language, String type) => [
  for (final t in HighlightJsHighlighter(language).tokenize(source))
    if (t.type == type) source.substring(t.start, t.end),
];

void main() {
  tearDown(unregisterHighlightJsLanguages);

  test('HJS-1: Python tokens carry the highlight.js classes', () {
    const src = 'def greet(name):\n    # say hello\n    return "hi " + name\n';
    expect(textsOf(src, 'python', 'keyword'), containsAll(['def', 'return']));
    expect(textsOf(src, 'python', 'comment'), ['# say hello']);
    expect(textsOf(src, 'python', 'string'), ['"hi "']);
  });

  test('HJS-2: JavaScript, SQL and CSS samples', () {
    expect(
      textsOf('const x = 42; // n', 'javascript', 'keyword'),
      contains('const'),
    );
    expect(textsOf('const x = 42; // n', 'javascript', 'number'), ['42']);
    expect(
      textsOf("SELECT name FROM users WHERE id = 'a';", 'sql', 'keyword'),
      containsAll(['SELECT', 'FROM', 'WHERE']),
    );
    expect(textsOf('a { color: red; }', 'css', 'selector-tag'), ['a']);
  });

  test('HJS-3: tokens lie inside the source and in order', () {
    const src = 'fn main() { println!("x"); }';
    var end = 0;
    for (final t in HighlightJsHighlighter('rust').tokenize(src)) {
      expect(t.start, greaterThanOrEqualTo(end));
      expect(t.end, lessThanOrEqualTo(src.length));
      end = t.end;
    }
  });

  test('HJS-4: names and aliases resolve, lower case', () {
    expect(highlightJsLanguages['py'], 'python');
    expect(highlightJsLanguages['js'], 'javascript');
    expect(highlightJsLanguages['ts'], 'typescript');
    expect(highlightJsLanguages['dockerfile'], 'dockerfile');
    expect(highlightJsLanguages.length, greaterThan(150));
  });

  test('HJS-5: registered, highlighterForLanguage answers highlight.js '
      'languages; our own highlighters stay first; unregistered, none', () {
    expect(highlighterForLanguage('python'), isNull);
    registerHighlightJsLanguages();
    registerHighlightJsLanguages(); // twice: no effect
    expect(highlighterForLanguage('Python'), isA<HighlightJsHighlighter>());
    expect(highlighterForLanguage('py'), isA<HighlightJsHighlighter>());
    expect(highlighterForLanguage('yaml'), isA<YamlHighlighter>());
    expect(highlighterForLanguage('no-such-language'), isNull);
    unregisterHighlightJsLanguages();
    expect(highlighterForLanguage('python'), isNull);
  });

  test('HJS-6: the theme styles the tokens by their class', () {
    const theme = HighlightTheme({
      'keyword': TextStyle(fontWeight: FontWeight.bold),
    });
    final spans = HighlightJsHighlighter(
      'python',
      theme: theme,
    ).highlight('def f(): pass');
    expect(spans, isNotEmpty);
    expect(spans.every((s) => s.type == 'keyword'), isTrue);
  });
}
