# tom_pdf_editor

A Flutter widget that shows one PDF, rendered natively by PDFium over FFI:
scroll and zoom, a page list with thumbnails and the outline, search with the
hits highlighted, text selection and copy, links. A controller beside it is
what a host drives (open, save, undo, redo, find, the dirty state), in the
same shape as the office editor's, so a host treats both alike.

License: BSD-3-Clause (see [LICENSE](LICENSE)); PDFium is BSD-3-Clause, with
permissive third-party code ([THIRD_PARTY.md](THIRD_PARTY.md)). Not published
(`publish_to: none`). Annotations and form filling are added by later work
(the history and the save path are in place for them).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| Editor | `lib/src/editor.dart` | `TomPdfEditor`: the zoom bar, the page list (thumbnails 120 px wide, the outline), the find bar (match case, whole word, previous / next, the count), the bars for read-only files, conflicts (*Keep mine*, *Take theirs*, *Save as copy*) and deleted files, the password dialog, *could not open*. |
| View | `lib/src/view/` | `PdfPageView`: the page column laid out from the page sizes alone (`PdfLayout`), zoom 50–400 % plus fit width and fit page (Cmd + / − / 0, Ctrl + wheel, pinch); renders by priority (visible, then thumbnails, then prefetch), cancelling what scrolled away; one bitmap per page up to 2048 px wide, 512-px tiles above (`planTiles`); the LRU cache of 256 MiB (`PdfRenderCache`), the old zoom shown until the new one has arrived; search hits and the selection drawn over the pages; drag, double- and triple-click selection, Cmd+C, links with a hand cursor. |
| Controller | `lib/src/controller.dart` | `TomPdfEditorController`: opening (the library must be usable; the revision taken before and after the load), passwords (three attempts, never logged), permissions (an encrypted file opens view-only, DPPF-3; copy as the file allows), scanned PDFs (*no text layer*: no search or selection), XFA, read-only files, external changes, search (hits streamed, the view jumping to the first), selection and copy (unmapped characters skipped with a notice), links, saving (an incremental save to a temporary target, `TomBinaryFiles.replace`, reopen), the history (`TomUndoStack` with a saved marker). |
| Host | `lib/src/host.dart` | `TomPdfEditorHost`: the file, its access (`TomBinaryFiles`), the PDFium library (`TomPdfiumLibrary`) and the engine, notices, links, history changes. |
| Engine | `lib/src/engine/engine.dart`, `lib/src/pdfium/` | `TomPdfEngine`, positions in view points; `PdfiumEngine`, one worker isolate shared by every PDF tab that makes every PDFium call (PDFium is not thread-safe): renders by priority with cancelling, pages and text pages in a window of 12, search page by page, incremental saves with the cross-reference fix (`xref_fix.dart`: `/Type/XRef` inserted when PDFium leaves it out, so macOS Preview opens the file). |
| Locator | `lib/src/io/locator.dart` | `TomPdfiumLocator`: `tom_binaries/pdfium/darwin-arm64/libpdfium.dylib` from `TOM_BINARY_PATH`'s parent, refused when its `pdfium.version.json` names another release than the bindings (*PDFium not found*, *PDFium version mismatch*). |
| Bindings | `lib/src/pdfium/pdfium_bindings.g.dart`, `tool/ffigen.yaml`, `third_party/pdfium/include/` | our own FFIgen bindings (DPPF-1) from the pinned release's headers, only the functions used. |
| Debug | `lib/src/pdf_editor_trail.dart` | `kPdfEditorDebug` (switchable at run time), prefix `[PE]`: state changes, engine renders summarised once a second, search (never the term), save steps, focus; the heartbeat and the `FlutterError` intercept while on. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_pdf_editor/tom_pdf_editor.dart` | the widget, controller, host, view, cache, the engine interface | all (no `dart:io`, no `dart:ffi`) |
| `package:tom_pdf_editor/pdfium.dart` | `PdfiumEngine`, `fixXrefInFile` | desktop (`dart:ffi`, `dart:io`) |
| `package:tom_pdf_editor/io.dart` | `TomPdfiumLocator` | desktop (`dart:io`) |
| `package:tom_pdf_editor/testing.dart` | `FakePdfEngine`, `MemoryBinaryFiles`, `FakePdfEditorHost` | all |

## Dependencies

Flutter, `ffi`, `tom_undo`, `tom_basics`, `path`, `crypto`, `uuid`;
`tom_file_session` (`TomBinaryFiles`) and `tom_ui_support` by path.

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

The example app (`example/`) is a complete desktop host. Building, taking in
a PDFium release and the tests: [_copilot_guidelines/build.md](_copilot_guidelines/build.md).
