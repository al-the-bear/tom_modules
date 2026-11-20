# Tom Mermaid View

`MermaidWebView` renders a [Mermaid](https://mermaid.js.org/) diagram
(flowchart, sequence, class, state, ER, gantt, pie, timeline, mindmap, …) with
the official mermaid.js in a small webview that sizes itself to the diagram.

```yaml
dependencies:
  tom_mermaid_view:
    path: ../../tom_ai/modules/tom_mermaid_view
```

```dart
import 'package:tom_mermaid_view/tom_mermaid_view.dart';

MermaidWebView(
  source: 'graph TD; A-->B;',
  theme: MermaidTheme.dark,
)
```

The package bundles `mermaid.min.js` (mermaid.js 11.13.0, MIT, 2.9 MB) as an
asset and depends on the webview plugin (`flutter_inappwebview`, the Tom fork),
so it is a package of its own: an application that never shows a diagram does
not depend on it and ships neither. It is one of the Tom UI modules
(`tom_ai/modules`, repository `tom_modules`); Tom Forge's `tom_md_editor`
takes it for its Mermaid plugin, which renders ```` ```mermaid ```` blocks.
It is not published: its webview is the Tom fork, taken by path.

Third-party software: [THIRD_PARTY.md](THIRD_PARTY.md).

## License

BSD-3-Clause ([LICENSE](LICENSE)); mermaid.js is MIT
([assets/js/LICENSE](assets/js/LICENSE)).
