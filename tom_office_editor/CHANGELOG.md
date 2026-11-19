## 0.3.0

- LibreOffice's dialogs as windows (`TomOfficeDialogLayer`): overlays of the
  reported size, painted by `paintWindow`, modal, draggable, a combo box's
  list at its position; mouse, keys and typed characters back to the
  window; the controller's `windows`, `windowMouse`, `windowKey`,
  `windowText`, `closeWindow`. The core's closing of every dialog is gone.
- The dialog switch: `dialogMode`, `setDialogMode`, `jsonDialogsAvailable`
  (the helper's refusal keeps the tab with windows); *Dialogs: LibreOffice
  windows / Forge forms* in the status line.
- Fix: text committed by the input method is sent as the composition and its
  end; `end` alone inserted nothing in LibreOffice 26.8.3.1, so typing in the
  document was lost (a new `libreoffice`-tagged test guards it).
- Takes protocol 0.4.0 (window position, size, title, cursor visibility).

## 0.2.0

- The ribbon (`TomOfficeRibbon`, shown by `TomOfficeEditor` unless
  `showRibbon: false`): tabs and controls per document type, commands with
  their `STATE_CHANGED` state, dropdowns from `getCommandValues`, colour split
  buttons with the colour picker, keyboard traversal, *Insert image*, Cmd+F
  for Find & Replace.
- `TomOfficeEditorHost.pickImage` (breaking for hosts: implement it).
- The controller: `stateOf`, `isEnabled`, `isChecked`, `applyColour`,
  `recentColours`, `fonts`, `styles`, `find`, `insertImage`, `lastWindow`; a
  dialog's notice names what the helper sent; the trail names each `uno`
  command (never its arguments).
- The fake helper answers `getCommandValues` with scripted `values`.

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
