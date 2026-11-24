# tom_pdf_pdfjs

The pdf.js view of the PDF editor: **`TomPdfJsView`**, Mozilla's pdf.js in
the workspace's webview fork, in three modes the host chooses, with its
controller and the bridge's channel. pdf.js 6.5.438 is vendored as assets.
The host is `tom_pdf_editor`'s `TomPdfViewHost` (the host every PDF view
shares); the notice bar and toolbar row are `tom_pdf_editor`'s too. No FFI,
no native library.

License: BSD-3-Clause (see [LICENSE](LICENSE)); pdf.js is Apache-2.0, with
the third-party parts listed in [THIRD_PARTY.md](THIRD_PARTY.md). Not
published (`publish_to: none`).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| pdf.js view | `lib/src/`, `assets/pdfjs_forge/`, `third_party/pdfjs/6.5.438/` | `TomPdfJsView` and `TomPdfJsController`: pdf.js 6.5.438's **legacy** build (the modern one does not start in macOS 15's WKWebView), vendored unmodified as assets (its GPL Liberation Sans fonts replaced by the OFL 2.1.5 release, THIRD_PARTY.md), served with Forge's own files by `TomLocalContentServer` (`/<token>/pdfjs/…`, the document at `/<token>/doc/<n>/<name>` with `Range`, the save receiver at `/<token>/save`). **Modes** (`TomPdfJsMode`): `integrated` — the generic viewer with Forge's stylesheet hiding open, print, download, present, bookmark and pdf.js's find bar; `full` — the generic viewer unchanged; `components` — Forge's `components.html` with `pdf_viewer.mjs`'s `PDFViewer`, `PDFLinkService`, `PDFFindController` and annotation editor, and a toolbar drawn in Flutter (tools, undo, redo, zoom, find). The two generic pages are made from pdf.js's `web/viewer.html` and served beside it (its CSP forbids a `<base>`): an options script before the viewer starts (`defaultUrl` empty, `disablePreferences`, `disableHistory`, `enableScripting: false`, `isEvalSupported: false`, `enableXfa: false`, the signature editor off), the bridge after it. **Bridge** (`TomPdfJsChannel`): Dart → page `open`, `close`, `save`, `resetModified`, `undo`, `redo`, `find`, `setTool`, `zoom`, `scrollTo`, `checkModified` (started, never awaited in the page); page → Dart through the `forge` handler: `ready`, `loaded`, `textLayer`, `modified`, `history`, `findCount`, `view` (page and scale), `saved`, `error`, `openLink`, `passwordRequested`, `shortcut` (Cmd+S, Cmd+F), `trail`. **Saving:** `saveDocument()`'s bytes are POSTed to the site and written through `TomBinaryFiles` (temporary target, replace over an unchanged file, else the conflict banner), then pdf.js's storage is reset and the document reopened. Forms are filled by pdf.js itself. Opening another document closes the previous one first. The history and the dirty state are pdf.js's own. |
| Debug | `lib/src/pdfjs_trail.dart` | the `[PE:js]` trail on the editor's flag (`kPdfEditorDebug`); errors reported as `tom_pdf_pdfjs`'s. |
| Test support | `lib/src/testing/` | `FakePdfJsChannel` stands in for the view's webview. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_pdf_pdfjs/tom_pdf_pdfjs.dart` | `TomPdfJsView`, `TomPdfJsController`, `TomPdfJsChannel`, `TomPdfJsMode`, `TomPdfJsTool`, `TomPdfJsState`, `TomPdfJsConflict`, `PdfJsViewPosition`, `kPdfJsVersion`, `kPdfJsAssets`, `kPdfJsForgeAssets` | desktop (`dart:io`, the webview plugin) |
| `package:tom_pdf_pdfjs/testing.dart` | `FakePdfJsChannel` | all |

## Dependencies

Flutter; `tom_pdf_editor`, `tom_file_session` (`TomBinaryFiles`,
`TomLocalContentServer`) and the webview fork `flutter_inappwebview`
(`tom_ai/xternal/tom_flutter_inappwebview`) by path.

## Usage

```dart
import 'package:tom_pdf_pdfjs/tom_pdf_pdfjs.dart';

final controller = TomPdfJsController(myViewHost, // a TomPdfViewHost
    mode: TomPdfJsMode.components);
// TomPdfJsView(controller: controller)
```

The example app (`example/`) shows the view in each mode
(`TOM_PDF_VIEW=components|integrated|full`) and holds the macOS
integration tests. Taking in a pdf.js release and the tests:
`_agent_guidelines/build.md` in this package.
