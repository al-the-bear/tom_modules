# tom_pdf_editor

The PDF editor without an engine: a Flutter widget that shows one PDF an
engine renders — scroll and zoom, a page list with thumbnails and the
outline, search with the hits highlighted, text selection and copy, links,
annotations (highlights on text, notes and ink, changed and removed) and form
filling, with undo and redo, saved incrementally. A controller beside it is
what a host drives (open, save, undo, redo, find, the dirty state), in the
same shape as the office editor's, so a host treats both alike.

The engines are packages of their own, one engine each, so an application
takes only the one it uses:

| Package | Engine |
| --- | --- |
| [`tom_pdf_pdfium`](../tom_pdf_pdfium/) | `PdfiumEngine`: PDFium over FFI on a worker isolate, the engine of `TomPdfEditor`; the PDFium locator. |
| [`tom_pdf_pdfjs`](../tom_pdf_pdfjs/) | `TomPdfJsView`: Mozilla's pdf.js in the workspace's webview fork, a view of its own over `TomPdfViewHost`. |

This package has no `dart:ffi`, no `dart:io`, no webview and no assets.

License: BSD-3-Clause (see [LICENSE](LICENSE)). Not published
(`publish_to: none`).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| Editor | `lib/src/editor.dart` | `TomPdfEditor`: the zoom bar, the page list (thumbnails 120 px wide, the outline), the find bar (match case, whole word, previous / next, the count; `onFind` hands Cmd+F and the find button to a host's own find bar instead), the bars for read-only files, conflicts (*Keep mine*, *Take theirs*, *Save as copy*) and deleted files, the password dialog, *could not open*. |
| View | `lib/src/view/` | `PdfPageView`: the page column laid out from the page sizes alone (`PdfLayout`), zoom 50–400 % plus fit width and fit page (Cmd + / − / 0, Ctrl + wheel, pinch); renders by priority (visible, then thumbnails, then prefetch), cancelling what scrolled away; one bitmap per page up to 2048 px wide, 512-px tiles above (`planTiles`); the LRU cache of 256 MiB (`PdfRenderCache`), the old zoom shown until the new one has arrived; search hits and the selection drawn over the pages; drag, double- and triple-click selection, Cmd+C, links with a hand cursor. |
| Annotations | `lib/src/controller.dart`, `lib/src/engine/annotation.dart` | The tools (Select V, Highlight H, Note N, Ink I; Escape back to Select) and their colours: a drag over text highlights it (one highlight per page, one history entry), a click places a note (its text asked for), a drag draws ink (thinned to 0.5 pt). In Select, a click selects an annotation (highlight, note, ink; others are shown, not editable), a drag moves it (not a highlight), the corner handle resizes ink, the colours recolour it, Backspace / Delete removes it, a double-click edits a note. Every change is one `TomUndoStack` entry (Cmd+Z, Cmd+Shift+Z); new annotations get `T` (the host's author), `M` and `NM` (a UUID), and an annotation of the file without `NM` gets one when first edited. No appearance streams are written: PDFium, PDFKit (Preview) and Chrome draw the three subtypes from their entries; an edited annotation of the file has its old appearance stream cleared. The edited page is rendered again, its old image shown until the new one arrives. An encrypted document has the tools disabled; *Save as copy…* writes an unencrypted copy after a warning (DPPF-3). |
| Controller | `lib/src/controller.dart` | `TomPdfEditorController`: opening (the engine's status must be usable; the revision taken before and after the load), passwords (three attempts, never logged), permissions (an encrypted file opens view-only, DPPF-3; copy as the file allows), scanned PDFs (*no text layer*: no search or selection), XFA, read-only files, external changes, search (hits streamed, the view jumping to the first), selection and copy (unmapped characters skipped with a notice), links, saving (an incremental save to a temporary target, `TomBinaryFiles.replace`, reopen; with a `TomBinaryFileBytes` the document is opened from and saved into bytes), the view position (`viewPosition`, `restoreView`: page, offset, zoom), the history (`TomUndoStack` with a saved marker) of annotation and form edits (a form field's committed value is one entry; undo sets it back through the engine). |
| Host | `lib/src/host.dart` | `TomPdfViewHost`, what every PDF view asks of the application: the file, its access (`TomBinaryFiles`), notices, links, history changes. `TomPdfEditorHost` adds the engine: `engineStatus` (a `TomPdfEngineStatus`: usable, or the tab's message why not) and `startEngine(status)`; an engine package's status type (`TomPdfiumLibrary`) implements `TomPdfEngineStatus`, and a host may declare that type for both (`startEngine` takes it covariantly). |
| Engine interface | `lib/src/engine/` | `TomPdfEngine`, positions in view points, and its value types (documents, pages, text, links, annotations, form fields, search hits, renders as BGRA). |
| Bars | `lib/src/view/bars.dart`, `lib/src/view/note_dialog.dart` | `PdfNoticeBar` and `PdfToolbarRow`, shared by every PDF view (the pdf.js view's too): notices that put their actions on a line of their own at narrow widths, a toolbar that scrolls sideways; the note dialog. |
| Debug | `lib/src/pdf_editor_trail.dart` | `kPdfEditorDebug` (switchable at run time), prefix `[PE]`; `pdfEditorTrail` and `pdfEditorReport` for the engine packages' trails (`[PE:js]`): state changes, engine renders summarised once a second, search (never the term), save steps, focus; the heartbeat and the `FlutterError` intercept while on. |
| Test support | `lib/src/testing/` | `FakePdfEngine` (fixed page images, text and links from `FakePdfDocument`s), `MemoryBinaryFiles`, `FakePdfEditorHost` with `FakePdfEngineStatus`. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_pdf_editor/tom_pdf_editor.dart` | the widget, controller, hosts, engine status, view, cache, bars, trail, the engine interface | all |
| `package:tom_pdf_editor/testing.dart` | `FakePdfEngine`, `MemoryBinaryFiles`, `FakePdfEditorHost`, `FakePdfEngineStatus` | all |

## Dependencies

Flutter, `tom_undo`, `tom_basics`, `path`, `uuid`; `tom_file_session`
(`TomBinaryFiles`) and `tom_ui_support` by path.

## Usage

With the PDFium engine (`tom_pdf_pdfium`):

```dart
import 'package:tom_file_session/io.dart';
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfium/tom_pdf_pdfium.dart';

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
  TomPdfiumLibrary get engineStatus => const TomPdfiumLocator().locate();
  @override
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library) =>
      PdfiumEngine.acquire(library.path!);
  // notice, openLink, historyChanged ...
}

final controller = TomPdfEditorController(MyPdfHost('/path/to/file.pdf'))..open();
// TomPdfEditor(controller: controller)
```

The pdf.js view (`tom_pdf_pdfjs`) takes a `TomPdfViewHost`. The tests run
against `testing.dart`'s fake engine (`flutter test`); the engines' own
tests, the examples and the macOS integration tests are in the engine
packages.
