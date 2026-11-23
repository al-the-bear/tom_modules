/// The one syntax-highlighting interface of the Tom editors and light
/// highlighters of our own.
///
/// - [SyntaxHighlighter] and [HighlightSpan]: the interface every source
///   view takes.
/// - [HighlightTheme], [TokenHighlighter], [HighlightToken]: token classes
///   styled by a theme; [highlightedInlineSpans] turns spans into
///   `InlineSpan`s.
/// - [YamlHighlighter], [MarkdownHighlighter], [JsonHighlighter],
///   [ShellHighlighter], [EnvHighlighter], and [highlighterForLanguage] for a
///   fenced code block's language name.
library;

export 'src/highlight_spans.dart';
export 'src/highlight_theme.dart';
export 'src/languages/env.dart';
export 'src/languages/json.dart';
export 'src/languages/languages.dart';
export 'src/languages/markdown.dart';
export 'src/languages/shell.dart';
export 'src/languages/yaml.dart';
export 'src/syntax_highlighter.dart';
export 'src/token_highlighter.dart';
