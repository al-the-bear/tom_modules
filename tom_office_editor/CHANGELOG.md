## 0.1.0

- `TomOfficeEditor` and `TomOfficeEditorController`: one office document
  served by the LibreOfficeKit helper over protocol 1 — tiles with the tile
  cache, LibreOffice's caret, selection, cell cursor and pointer, scrolling
  and zoom, keys, input-method text, the mouse, the context menu, copy and
  paste; opening with passwords, read-only documents, saving through
  `TomBinaryFiles` with the conflict choices, CSV with explicit filter
  options, external changes, undo, redo and dirty from LibreOffice's state,
  the helper stopping (crash or hang), the spreadsheet's formula line,
  headers and sheet tabs, the slide strip, debug mode (`[OE]`).
- `io.dart`: `TomLibreOfficeDetector` (macOS search, *Auto-detect*, the
  states and the cross-check) and `TomOfficeProcessLauncher` (helper start,
  staged shutdown, clean-up of dead helpers).
- `testing.dart`: a fake helper channel and launcher.
