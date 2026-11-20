/// Mermaid diagrams in a webview: [MermaidWebView] renders a diagram's
/// source with the official mermaid.js, in one of the [MermaidTheme]s.
///
/// The package bundles `mermaid.min.js` (mermaid.js 11.13.0, MIT, 2.9 MB) as
/// an asset and brings the webview plugin, so it is a package of its own:
/// only an application that renders diagrams depends on it.
library;

export 'src/mermaid_webview.dart';
