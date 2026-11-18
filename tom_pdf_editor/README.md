# tom_pdf_editor

A Flutter widget that shows one PDF, rendered natively by PDFium over FFI:
scroll and zoom, a page list with thumbnails and the outline, search with the
hits highlighted, text selection and copy, links, annotations (highlights on
text, notes and ink, changed and removed) and form filling (text fields,
checkboxes, radio buttons), with undo and redo, saved incrementally. A controller beside it is
what a host drives (open, save, undo, redo, find, the dirty state), in the
same shape as the office editor's, so a host treats both alike.

Beside it, a second view for comparison: **`TomPdfJsView`**, Mozilla's
pdf.js in the workspace's webview fork, in three modes the host chooses.

License: BSD-3-Clause (see [LICENSE](LICENSE)); PDFium is BSD-3-Clause, pdf.js
Apache-2.0, with the third-party parts listed in
[THIRD_PARTY.md](THIRD_PARTY.md). Not published (`publish_to: none`).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| Editor | `lib/src/editor.dart` | `TomPdfEditor`: the zoom bar, the page list (thumbnails 120 px wide, the outline), the find bar (match case, whole word, previous / next, the count), the bars for read-only files, conflicts (*Keep mine*, *Take theirs*, *Save as copy*) and deleted files, the password dialog, *could not open*. |
| View | `lib/src/view/` | `PdfPageView`: the page column laid out from the page sizes alone (`PdfLayout`), zoom 50–400 % plus fit width and fit page (Cmd + / − / 0, Ctrl + wheel, pinch); renders by priority (visible, then thumbnails, then prefetch), cancelling what scrolled away; one bitmap per page up to 2048 px wide, 512-px tiles above (`planTiles`); the LRU cache of 256 MiB (`PdfRenderCache`), the old zoom shown until the new one has arrived; search hits and the selection drawn over the pages; drag, double- and triple-click selection, Cmd+C, links with a hand cursor. |
| Annotations | `lib/src/controller.dart`, `lib/src/engine/annotation.dart` | The tools (Select V, Highlight H, Note N, Ink I; Escape back to Select) and their colours: a drag over text highlights it (one highlight per page, one history entry), a click places a note (its text asked for), a drag draws ink (thinned to 0.5 pt). In Select, a click selects an annotation (highlight, note, ink; others are shown, not editable), a drag moves it (not a highlight), the corner handle resizes ink, the colours recolour it, Backspace / Delete removes it, a double-click edits a note. Every change is one `TomUndoStack` entry (Cmd+Z, Cmd+Shift+Z); new annotations get `T` (the host's author), `M` and `NM` (a UUID), and an annotation of the file without `NM` gets one when first edited. No appearance streams are written: PDFium, PDFKit (Preview) and Chrome draw the three subtypes from their entries; an edited annotation of the file has its old appearance stream cleared. The edited page is rendered again, its old image shown until the new one arrives. An encrypted document has the tools disabled; *Save as copy…* writes an unencrypted copy after a warning (DPPF-3). |
| Forms | `lib/src/controller.dart`, `lib/src/pdfium/pdfium_worker.dart` | AcroForm text fields, checkboxes and radio buttons are filled through PDFium's form-fill environment (`FPDFDOC_InitFormFillEnvironment`, the `FFI_Invalidate` callback `NativeCallable.isolateLocal` on the worker isolate, `FORM_OnAfterLoadPage` / `FORM_OnBeforeClosePage` following the page window, the focused field's page kept open). In the Select tool a click on a field goes to `FORM_OnLButtonDown` / `Up`; typed text to `FORM_OnChar`; Backspace, Delete, arrows, Home, End, Return and Tab (Shift+Tab) to `FORM_OnKeyDown`; Cmd+A selects the field's text; Cmd+Z first undoes the typing inside the focused field (`FORM_Undo`). The focus is released (`FORM_ForceToKillFocus`) when the editor loses the focus, an annotation tool is chosen, Escape, undo, redo or save. Pages `FFI_Invalidate` names are rendered again with `FPDF_FFLDraw`. Each committed change — a text field's text when it loses the focus, a checkbox or radio button at the click — is one history entry beside the annotations; undo sets the value back (`FORM_SetFocusedAnnot`, `FORM_SelectAllText`, `FORM_ReplaceSelection`; a click for a button). A radio group that had no button on cannot go back to none (PDFium has no call for it): that undo says so. Combo boxes, list boxes, push buttons and signature fields are drawn, not filled; no JavaScript runs. Encrypted documents are not filled (DPPF-3). |
| Controller | `lib/src/controller.dart` | `TomPdfEditorController`: opening (the library must be usable; the revision taken before and after the load), passwords (three attempts, never logged), permissions (an encrypted file opens view-only, DPPF-3; copy as the file allows), scanned PDFs (*no text layer*: no search or selection), XFA, read-only files, external changes, search (hits streamed, the view jumping to the first), selection and copy (unmapped characters skipped with a notice), links, saving (an incremental save to a temporary target, `TomBinaryFiles.replace`, reopen), the history (`TomUndoStack` with a saved marker). |
| Host | `lib/src/host.dart` | `TomPdfEditorHost`: the file, its access (`TomBinaryFiles`), the PDFium library (`TomPdfiumLibrary`) and the engine, notices, links, history changes. |
| Engine | `lib/src/engine/engine.dart`, `lib/src/pdfium/` | `TomPdfEngine`, positions in view points; `PdfiumEngine`, one worker isolate shared by every PDF tab that makes every PDFium call (PDFium is not thread-safe): renders by priority with cancelling, pages and text pages in a window of 12, search page by page, incremental saves with the cross-reference fix (`xref_fix.dart`: `/Type/XRef` inserted when PDFium leaves it out, so macOS Preview opens the file). |
| Locator | `lib/src/io/locator.dart` | `TomPdfiumLocator`: `tom_binaries/pdfium/darwin-arm64/libpdfium.dylib` from `TOM_BINARY_PATH`'s parent, refused when its `pdfium.version.json` names another release than the bindings (*PDFium not found*, *PDFium version mismatch*). |
| Bindings | `lib/src/pdfium/pdfium_bindings.g.dart`, `tool/ffigen.yaml`, `third_party/pdfium/include/` | our own FFIgen bindings (DPPF-1) from the pinned release's headers, only the functions used. |
| pdf.js view | `lib/src/pdfjs/`, `assets/pdfjs_forge/`, `third_party/pdfjs/6.5.438/` | `TomPdfJsView` and `TomPdfJsController` (`pdfjs.dart`): pdf.js 6.5.438's **legacy** build (the modern one does not start in macOS 15's WKWebView), vendored unmodified as assets, served with Forge's own files by `TomLocalContentServer` (`/<token>/pdfjs/…`, the document at `/<token>/doc/<n>/<name>` with `Range`, the save receiver at `/<token>/save`). **Modes** (`TomPdfJsMode`): `integrated` — the generic viewer with Forge's stylesheet hiding open, print, download, present, bookmark and pdf.js's find bar; `full` — the generic viewer unchanged; `components` — Forge's `components.html` with `pdf_viewer.mjs`'s `PDFViewer`, `PDFLinkService`, `PDFFindController` and annotation editor, and a toolbar drawn in Flutter (tools, undo, redo, zoom, find). The two generic pages are made from pdf.js's `web/viewer.html` and served beside it (its CSP forbids a `<base>`): an options script before the viewer starts (`defaultUrl` empty, `disablePreferences`, `disableHistory`, `enableScripting: false`, `isEvalSupported: false`, `enableXfa: false`, the signature editor off), the bridge after it. **Bridge** (`TomPdfJsChannel`): Dart → page `open`, `close`, `save`, `resetModified`, `undo`, `redo`, `find`, `setTool`, `zoom`, `checkModified` (started, never awaited in the page); page → Dart through the `forge` handler: `ready`, `loaded`, `textLayer`, `modified`, `history`, `findCount`, `saved`, `error`, `openLink`, `passwordRequested`, `shortcut` (Cmd+S, Cmd+F), `trail`. **Saving:** `saveDocument()`'s bytes are POSTed to the site and written through `TomBinaryFiles` (temporary target, replace over an unchanged file, else the conflict banner), then pdf.js's storage is reset and the document reopened. Forms are filled by pdf.js itself. Opening another document closes the previous one first. The history and the dirty state are pdf.js's own. |
| Debug | `lib/src/pdf_editor_trail.dart` | `kPdfEditorDebug` (switchable at run time), prefix `[PE]`: state changes, engine renders summarised once a second, search (never the term), save steps, focus; the heartbeat and the `FlutterError` intercept while on. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_pdf_editor/tom_pdf_editor.dart` | the widget, controller, host, view, cache, the engine interface | all (no `dart:io`, no `dart:ffi`) |
| `package:tom_pdf_editor/pdfium.dart` | `PdfiumEngine`, `fixXrefInFile` | desktop (`dart:ffi`, `dart:io`) |
| `package:tom_pdf_editor/io.dart` | `TomPdfiumLocator` | desktop (`dart:io`) |
| `package:tom_pdf_editor/pdfjs.dart` | `TomPdfJsView`, `TomPdfJsController`, `TomPdfJsChannel`, `TomPdfJsMode`, `TomPdfJsTool` | desktop (`dart:io`, the webview plugin) |
| `package:tom_pdf_editor/testing.dart` | `FakePdfEngine`, `MemoryBinaryFiles`, `FakePdfEditorHost`, `FakePdfJsChannel` | all |

## Dependencies

Flutter, `ffi`, `tom_undo`, `tom_basics`, `path`, `crypto`, `uuid`;
`tom_file_session` (`TomBinaryFiles`, `TomLocalContentServer`),
`tom_ui_support` and the webview fork `flutter_inappwebview`
(`tom_ai/xternal/tom_flutter_inappwebview`) by path.

## Usage

```dart
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/io.dart';
import 'package:tom_pdf_editor/pdfium.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';

class MyPdfHost implements TomPdfEditorHost {
  MyPdfHost(this.filePath);
  @override
  final String filePath;
  @override
  String get name => filePath.split('/').last;
  @override
  String get authorName => 'Me';
  @override
  TomBinaryFiles get files => const TomBinaryFileAccess();
  @override
  TomPdfiumLibrary get pdfium => const TomPdfiumLocator().locate();
  @override
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library) =>
      PdfiumEngine.acquire(library.path!);
  // notice, openLink, historyChanged ...
}

final controller = TomPdfEditorController(MyPdfHost('/path/to/file.pdf'))..open();
// TomPdfEditor(controller: controller)
```

The pdf.js view takes a `TomPdfViewHost` (the host without the PDFium
parts):

```dart
final controller = TomPdfJsController(MyPdfHost('/path/to/file.pdf'),
    mode: TomPdfJsMode.components);
// TomPdfJsView(controller: controller)
```

The example app (`example/`) is a complete desktop host
(`TOM_PDF_VIEW=pdfjs-components|pdfjs-integrated|pdfjs-full` shows the
pdf.js view). Building, taking in
a PDFium release and the tests: [_copilot_guidelines/build.md](_copilot_guidelines/build.md).
