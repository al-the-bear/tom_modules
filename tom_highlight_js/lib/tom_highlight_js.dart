/// Every highlight.js language as a `tom_text_highlight` highlighter, for an
/// application that wants code blocks highlighted beyond the languages
/// `tom_text_highlight` has of its own.
///
/// Optional on purpose: the editors and renderers depend on
/// `tom_text_highlight` only, and an application that takes this package
/// calls [registerHighlightJsLanguages] once at start.
library;

export 'src/highlight_js_highlighter.dart';
