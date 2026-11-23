# tom_highlight_js

Every highlight.js language (about 190, through the `highlight` package) as
`tom_text_highlight` highlighters.

`tom_text_highlight` has light highlighters of its own (YAML, Markdown, JSON,
shell, `.env`), and the editors and renderers depend on it only. An
application that wants code blocks in other languages highlighted too —
Python, JavaScript/TypeScript, SQL, HTML, CSS and the rest — takes this
package and registers it once at start:

```dart
import 'package:tom_highlight_js/tom_highlight_js.dart';

void main() {
  registerHighlightJsLanguages();
  // runApp(...)
}
```

From then on `highlighterForLanguage` answers every highlight.js name and
alias it does not highlight itself, so the Markdown editor's preview and
code-block overlay and `tom_file_editors`' Markdown renderer highlight them.
The tokens carry the highlight.js class names (`keyword`, `string`,
`comment`, ...), which the existing themes style.

It is optional because the `highlight` package holds every grammar: an
application that only needs the languages of `tom_text_highlight` leaves it
out.

## Tests

`test/highlight_js_highlighter_test.dart`.
