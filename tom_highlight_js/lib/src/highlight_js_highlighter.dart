import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:tom_text_highlight/tom_text_highlight.dart';

/// The highlight.js language names and aliases, lower case, to the name the
/// parser is registered under.
final Map<String, String> highlightJsLanguages = () {
  final names = <String, String>{};
  for (final MapEntry(key: name, value: mode) in allLanguages.entries) {
    names[name.toLowerCase()] = name;
    for (final alias in mode.aliases ?? const <String>[]) {
      names.putIfAbsent(alias.toLowerCase(), () => name);
    }
  }
  return names;
}();

/// A highlighter for one highlight.js [language] (a name of
/// [highlightJsLanguages]' values), styled by [theme] through the
/// highlight.js class names (`keyword`, `string`, `comment`, ...), the same
/// names `tom_text_highlight`'s own highlighters and its themes use.
///
/// Each token is a run of text under its innermost class; text under no
/// class is left out (it keeps the base style).
class HighlightJsHighlighter extends TokenHighlighter {
  HighlightJsHighlighter(this.language, {super.theme});

  /// The registered highlight.js language name.
  final String language;

  @override
  List<HighlightToken> tokenize(String source) {
    final result = highlight.parse(source, language: language);
    final tokens = <HighlightToken>[];
    var offset = 0;
    void walk(Node node, String? type) {
      final own = node.className ?? type;
      final value = node.value;
      if (value != null) {
        if (own != null && value.isNotEmpty) {
          tokens.add(HighlightToken(offset, offset + value.length, own));
        }
        offset += value.length;
      }
      for (final child in node.children ?? const <Node>[]) {
        walk(child, own);
      }
    }

    for (final node in result.nodes ?? const <Node>[]) {
      walk(node, null);
    }
    return tokens;
  }
}

/// The fallback [registerHighlightJsLanguages] adds: a
/// [HighlightJsHighlighter] for a name or alias highlight.js knows.
TokenHighlighter? highlightJsFallback(String language, HighlightTheme theme) {
  final name = highlightJsLanguages[language];
  return name == null ? null : HighlightJsHighlighter(name, theme: theme);
}

/// Makes `tom_text_highlight`'s `highlighterForLanguage` answer every
/// highlight.js language it does not highlight itself (its own YAML,
/// Markdown, JSON, shell and `.env` highlighters stay first). Call it once,
/// at start; calling it again has no effect.
void registerHighlightJsLanguages() =>
    registerHighlighterFallback(highlightJsFallback);

/// Undoes [registerHighlightJsLanguages].
void unregisterHighlightJsLanguages() =>
    unregisterHighlighterFallback(highlightJsFallback);
