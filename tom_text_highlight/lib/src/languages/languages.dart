/// The highlighter for a language name, as a fenced code block writes it.
library;

import '../highlight_theme.dart';
import '../token_highlighter.dart';
import 'env.dart';
import 'json.dart';
import 'markdown.dart';
import 'shell.dart';
import 'yaml.dart';

/// Language names and aliases, lower case, to the canonical name.
const Map<String, String> highlightLanguageAliases = {
  'yaml': 'yaml',
  'yml': 'yaml',
  'markdown': 'markdown',
  'md': 'markdown',
  'json': 'json',
  'jsonc': 'json',
  'bash': 'bash',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'env': 'env',
  'dotenv': 'env',
  '.env': 'env',
};

/// The canonical name of [language] when this package highlights it, else
/// null.
String? highlightLanguageOf(String? language) {
  if (language == null) return null;
  return highlightLanguageAliases[language.trim().toLowerCase()];
}

/// Supplies a highlighter for a language this package has none of: the
/// language name as the code block writes it (trimmed, lower case) and the
/// theme to style it with; null when it does not know the language either.
typedef HighlighterFallback =
    TokenHighlighter? Function(String language, HighlightTheme theme);

final List<HighlighterFallback> _fallbacks = [];

/// Adds [fallback], asked by [highlighterForLanguage] for every language this
/// package does not highlight, in the order they were added. An application
/// that wants more languages registers one (e.g. `tom_highlight_js`'s
/// `registerHighlightJsLanguages()`); nothing is registered by default.
/// Adding the same function twice has no effect.
void registerHighlighterFallback(HighlighterFallback fallback) {
  if (!_fallbacks.contains(fallback)) _fallbacks.add(fallback);
}

/// Removes [fallback] (registered with [registerHighlighterFallback]).
void unregisterHighlighterFallback(HighlighterFallback fallback) =>
    _fallbacks.remove(fallback);

/// A highlighter for [language] (a name or alias, any case) styled by
/// [theme]: this package's own for the languages it highlights, else the
/// first registered fallback's; null when none knows the language.
TokenHighlighter? highlighterForLanguage(
  String? language, {
  HighlightTheme theme = HighlightTheme.none,
}) {
  final own = switch (highlightLanguageOf(language)) {
    'yaml' => YamlHighlighter(theme: theme),
    'markdown' => MarkdownHighlighter(theme: theme),
    'json' => JsonHighlighter(theme: theme),
    'bash' => ShellHighlighter(theme: theme),
    'env' => EnvHighlighter(theme: theme),
    _ => null,
  };
  if (own != null || language == null) return own;
  final name = language.trim().toLowerCase();
  if (name.isEmpty) return null;
  for (final fallback in _fallbacks) {
    final highlighter = fallback(name, theme);
    if (highlighter != null) return highlighter;
  }
  return null;
}
