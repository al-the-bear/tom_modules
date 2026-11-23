import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

class _Whole extends TokenHighlighter {
  _Whole(this.type, {super.theme});

  final String type;

  @override
  List<HighlightToken> tokenize(String source) => [
    HighlightToken(0, source.length, type),
  ];
}

void main() {
  TokenHighlighter? python(String language, HighlightTheme theme) =>
      language == 'python' ? _Whole('keyword', theme: theme) : null;

  tearDown(() => unregisterHighlighterFallback(python));

  test('TH-FB-1: a language of ours is ours; another is null without a '
      'fallback', () {
    expect(highlighterForLanguage('yaml'), isA<YamlHighlighter>());
    expect(highlighterForLanguage('python'), isNull);
  });

  test('TH-FB-2: a registered fallback answers the languages it knows, by '
      'trimmed lower-case name, with the given theme', () {
    registerHighlighterFallback(python);
    registerHighlighterFallback(python); // twice: no effect
    const theme = HighlightTheme({
      'keyword': TextStyle(color: Color(0xFF0000FF)),
    });
    final h = highlighterForLanguage(' Python ', theme: theme);
    expect(h, isA<_Whole>());
    expect(h!.highlight('def').single.style.color, const Color(0xFF0000FF));
    expect(highlighterForLanguage('cobol'), isNull);
    expect(
      highlighterForLanguage('json'),
      isA<JsonHighlighter>(),
      reason: 'our own highlighters come first',
    );
  });

  test('TH-FB-3: an unregistered fallback is no longer asked', () {
    registerHighlighterFallback(python);
    unregisterHighlighterFallback(python);
    expect(highlighterForLanguage('python'), isNull);
  });
}
