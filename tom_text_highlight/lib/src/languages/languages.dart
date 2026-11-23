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

/// A highlighter for [language] (a name or alias, any case) styled by
/// [theme]; null for a language this package does not highlight.
TokenHighlighter? highlighterForLanguage(
  String? language, {
  HighlightTheme theme = HighlightTheme.none,
}) => switch (highlightLanguageOf(language)) {
  'yaml' => YamlHighlighter(theme: theme),
  'markdown' => MarkdownHighlighter(theme: theme),
  'json' => JsonHighlighter(theme: theme),
  'bash' => ShellHighlighter(theme: theme),
  'env' => EnvHighlighter(theme: theme),
  _ => null,
};
