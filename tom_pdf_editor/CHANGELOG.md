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
- `TomPdfiumLocator` (`io.dart`): the library from the binaries layer,
  checked against the bindings' release.
- `testing.dart`: `FakePdfEngine`, `MemoryBinaryFiles`, `FakePdfEditorHost`.
- Debug trail `[PE]` with `kPdfEditorDebug`.
