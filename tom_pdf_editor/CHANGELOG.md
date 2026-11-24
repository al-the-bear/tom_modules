## 0.2.0

- The engines moved out, one package each: the PDFium engine
  (`PdfiumEngine`, `fixXrefInFile` and the cross-reference fix,
  `TomPdfiumLocator`, `TomPdfiumLibrary`, `TomPdfiumProblem`,
  `kPdfiumBindingsTag`, the bindings, the PDFium headers, the example app)
  is `tom_pdf_pdfium`; the pdf.js view (`TomPdfJsView`, `TomPdfJsController`,
  `TomPdfJsChannel` and its types, the vendored pdf.js, Forge's host files,
  `FakePdfJsChannel`) is `tom_pdf_pdfjs`. `pdfium.dart`, `io.dart` and
  `pdfjs.dart` are gone; `ffi`, `flutter_inappwebview`, `crypto`, `ffigen`
  and the assets with them.
- `TomPdfEditorHost` names no engine: `engineStatus` (a new
  `TomPdfEngineStatus`: `isUsable`, `message`) replaces `pdfium`, and
  `startEngine` takes the status (covariant, so a host may declare its
  engine package's type, e.g. `TomPdfiumLibrary`). The failure when the
  engine does not start reads *The PDF engine did not start*.
- `FakePdfEditorHost` takes `engineStatus` (default
  `FakePdfEngineStatus.usable()`) instead of `pdfium`.
- Exported for every PDF view: `PdfNoticeBar`, `PdfToolbarRow`, and the
  trail helpers `pdfEditorTrail` and `pdfEditorReport` the engine packages
  write with.
- Page 1 is drawn after every open. A render answered `null` without the
  view having cancelled it left the page grey for good: each page view and
  page list counted its render tickets from the same start, while a cancel
  that reached the engine after its render had run was kept for the ticket's
  next use, so the next document on the shared engine had its first render
  dropped (seen after a password open, which uses the fewest tickets). Now
  every caller takes its tickets from `nextPdfRenderTicket` (one counter per
  isolate), a render dropped without a cancel is asked for again (the
  thumbnail too), and a new view starts from the controller's generation, so
  its first renders are not cancelled and sent again at the first
  notification. `TomPdfEngine.cancel` says it: a cancel of a render that has
  run changes nothing and is not kept; `FakePdfEngine` models it (with
  `tickets` and `dropNextRenders` for the tests). Trail lines for every
  render request, result and cancel. Tests `PDF-DRAW-1` … `PDF-DRAW-3`.

## 0.1.0

- `TomPdfEditor`, the PDF viewer over PDFium: the page column laid out from
  the page sizes alone, zoom 50–400 % plus fit width and fit page (Cmd + /
  − / 0, Ctrl + wheel, pinch), one bitmap per page up to 2048 px and 512-px
  tiles above, an LRU render cache of 256 MiB with the old zoom shown until
  the new one has arrived, the page list (thumbnails 120 px wide, the
  outline), search with streamed hits, text selection (drag, double- and
  triple-click, across pages) and copy, links.
- `TomPdfEditorController` and `TomPdfEditorHost` in the shape of the office
  editor's: open, the password dialog (three attempts), permissions
  (encrypted files view-only, DPPF-3; copy as allowed), scanned PDFs, XFA
  notice, read-only files, external changes, save through `TomBinaryFiles`
  with the conflict banner, the history on `TomUndoStack` with its saved
  marker.
- `PdfiumEngine` (`pdfium.dart`): one shared worker isolate makes every
  PDFium call; renders by priority, cancellable; incremental saves with the
  cross-reference fix (`/Type/XRef` inserted when PDFium leaves it out).
- Annotations: highlight on text, note and ink tools; select, move, resize
  (ink), recolour, edit a note's text, delete; every change one history
  entry, saved incrementally; no appearance streams written (an edited
  annotation of the file has its own cleared); an edited page re-renders
  behind its old image. Encrypted documents: tools disabled, *Save as copy…*
  writes an unencrypted copy after a warning (DPPF-3).
- Form filling: text fields, checkboxes and radio buttons through PDFium's
  form-fill environment; clicks, typed text and keys to the focused field,
  its own typing undo, the focus released when the editor loses it or a
  tool is chosen; each committed change one history entry, saved
  incrementally; combo and list boxes, push buttons, signatures and
  JavaScript left out; encrypted documents not filled (DPPF-3).
- `TomPdfJsView` (`pdfjs.dart`): pdf.js 6.5.438 (legacy build, vendored
  unmodified with its version file) in the webview fork, served by
  `TomLocalContentServer`, in three modes (`integrated`, `full`,
  `components`); the bridge both ways through handlers; `saveDocument()`'s
  bytes POSTed and written through `TomBinaryFiles` with the conflict
  banner; forms filled by pdf.js; the previous document closed before the
  next opens; the `[PE:js]` trail. `TomPdfViewHost` is the host both views
  share; `TomPdfEditorHost` adds the PDFium parts.
- The vendored pdf.js's Liberation Sans fonts are the OFL-1.1 2.1.5
  release instead of pdf.js's GPL-2.0 copy (recorded in
  `pdfjs.version.json`; checked by `PDFJS-LIC-1`).
- Redo works after undoing one of several entries (the controller kept the
  newest entry by popping and pushing it, which emptied the redo stack).
- `TomPdfiumLocator` (`io.dart`): the library from the binaries layer,
  checked against the bindings' release.
- `testing.dart`: `FakePdfEngine`, `MemoryBinaryFiles`, `FakePdfEditorHost`.
- Debug trail `[PE]` with `kPdfEditorDebug`.
- Documents from bytes: a host whose files are a `TomBinaryFileBytes`
  (e.g. `TomFileSystemBinaryFiles`) has PDFium open the document from memory
  (`FPDF_LoadMemDocument64`, `TomPdfEngine.openBytes`) and save into bytes
  (`saveIncrementalBytes`, `saveCopyBytes`) written to the temporary target;
  pdf.js gets them through its content site.
- The view position: `PdfViewPosition` (page, offset, zoom) and
  `PdfJsViewPosition` (page, scale) — `viewPosition`, `restoreView` on both
  controllers, applied once the document has loaded; the pdf.js bridge sends
  `view` and takes `scrollTo(page)`.
- `onFind` on `TomPdfEditor` and `TomPdfJsView`: Cmd+F and the find button
  go to the host (its own find bar) instead of the editor's.

- Both views fit any width down to Forge's narrowest editor (240 px):
  the notices (`PdfNoticeBar`, shared) put their actions on a line of their
  own and take at most two fifths of the height, scrolling beyond it; the
  pdf.js toolbar scrolls sideways like the PDFium editor's; the password and
  could-not-open panels scroll.
- The `[PE]` trail's FlutterError line names the widget the error came
  from (`pdfErrorSummary`: message, library, first information line).
- The bridge's test hooks reach the viewer and its find controller in every
  mode (`forgeBridge.test.adapter.pdfViewer`, `.findController`), for the
  integration tests and the PDF routes' evaluation harness.
- The pdf.js view after its WebKit content process ended: the failure is
  shown without the webview, the controller lets go of the dead channel, and
  `reload()` gets a new webview that loads the page and reopens the
  document (it called the dead webview before and failed). A view that
  leaves the tree detaches its channel too, so a later `close()` sends
  nothing to a disposed webview (PDFJS-MAC-CRASH-1, PDFJS-MAC-CLOSE-1/2 in
  the example's macOS integration tests).
- Closing the PDFium controller while its editor is still shown (as Forge
  does when a tab closes) reports nothing: no new render, thumbnail or text
  request starts once the document is closed, and an answer the closing
  overtook (a thumbnail, a search, the text-layer check) is dropped
  quietly (`TomPdfEditorController.isOpenDocument`; PDF-CLOSE-2).