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
- Redo works after undoing one of several entries (the controller kept the
  newest entry by popping and pushing it, which emptied the redo stack).
- `TomPdfiumLocator` (`io.dart`): the library from the binaries layer,
  checked against the bindings' release.
- `testing.dart`: `FakePdfEngine`, `MemoryBinaryFiles`, `FakePdfEditorHost`.
- Debug trail `[PE]` with `kPdfEditorDebug`.
