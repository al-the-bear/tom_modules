## 0.7.0

- `TomOfficeProcessLauncher.findHelper` looks in the binaries layer's own
  Windows folder `win32-x64` (it looked in `windows-x64`, so the helper was
  never found on Windows); the folder names come from
  `binariesPlatformFolder` (`darwin-arm64`, `linux-x64`, `win32-x64`).
- Checked on real hosts (bigbeast Ubuntu 24.04, a Fedora 43 container,
  legiondary01 Windows 11): on Windows the detector reads the installer's
  `UNO\InstallPath` registry keys (`programFoldersInRegQuery`, source
  `registry`) and survives non-UTF-8 tool output (a German `reg.exe`);
  winget's app execution alias counts as present (`installExecutableExists`);
  the winget route accepts the package and source agreements; the PPA route
  offers 26.8.3.1. On Linux `soffice --version` stays the version source.
- The LibreOffice tool descriptor, `TomLibreOfficeTool.standard`
  (`lib/src/detection/libreoffice_tool.dart`, no `dart:io`): per platform
  (`TomToolPlatform`) the minimum version (macOS and Windows 26.8.3.1,
  Linux 26.8.0: DPLD-4), the search locations, the files a program folder
  must hold, the warnings (Linux: no Snap or Flatpak; the program folder at
  `/opt/libreoffice<x.y>/program`) and the install routes
  (`TomInstallRoute`: argv commands, elevation, steps, the package manager
  it needs, the version it delivers): Homebrew's cask; winget and
  Chocolatey; TDF's `.deb` and `.rpm` archives as managed downloads
  (`TomManagedDownload`, checked against the published `.sha256`) and apt
  with `ppa:libreoffice/ppa` through `pkexec`; the download page
  `kLibreOfficeDownloadPage` as the by-hand route on each.
- `TomLibreOfficeInstallHelp`: what is missing (not found, too old, the
  path set unusable, damaged) and why, the platform's routes, a
  confirmation naming the commands and the elevation, the run's streamed
  output and end (`TomLibreOfficeInstallRun`,
  `TomLibreOfficeInstallRunController`; the host runs the commands through
  `onInstall`), the download page (`onOpenDownloadPage`) and *Check again*.
- `TomLibreOfficeDetector` detects on Linux and Windows too: program
  folders from the descriptor (`/opt/libreoffice*/program`,
  `/usr/lib/libreoffice/program`, `/usr/lib64/libreoffice/program`;
  `C:\Program Files\LibreOffice\program`) and `soffice` on `PATH`; a
  folder counts only with `soffice` and `libmergedlo.so` (`soffice.exe`,
  `mergedlo.dll`); the version from `soffice --version` under a private
  profile (on Windows checked against `version.ini`). It uses the
  platform's minimum (`platform`, `tool`, `programFolderPatterns`); the
  macOS defaults now come from the descriptor.
- `LibreOfficeInstallation`: `programFolder`, `sofficeExecutable`,
  `minimumVersion` (set on `tooOld`, shown in the message),
  `isUnusableSetting`.
- `io.dart`: `installRouteAvailability`, which routes' package managers are
  on `PATH`.

## 0.6.0

- The ZetaOffice route moved to its own package, `tom_office_zetaoffice`
  (one route per package): `package:tom_office_editor/zetaoffice.dart` is
  now `package:tom_office_zetaoffice/tom_office_zetaoffice.dart`, the
  ZetaOffice fakes left `testing.dart` for
  `package:tom_office_zetaoffice/testing.dart`, `assets/zetaoffice/` went
  with it. This package no longer depends on `flutter_inappwebview`.
- `example/`: the *ZetaOffice* switch and `zetaoffice_test.dart` moved to
  `tom_office_zetaoffice/example`.

## 0.5.0

- *Save as copy* of a password-protected document: the warning offers
  *Save with password* (the default) and *Save without password*;
  `TomOfficeEditorController.saveAsCopy` takes `keepPassword` (DPOE-3).

## 0.4.1

- ZetaOffice: a bridge call the page does not answer (its event loop
  stalled, e.g. while the window cannot be seen) no longer hangs the caller:
  `TomZetaOfficeChannel.call` gives up after ten seconds, so `save()` and the
  others reach their own timeouts.
- `TomZetaOfficeChannel.snapshot` and the controller's test hooks for the
  office evaluation: `exportPdfForTest` (the document as ZetaOffice's PDF
  export), `runInPageForTest` and `pageMessagesForTest` (measuring scripts in
  the page), `snapshotForTest` (the webview's image).

## 0.4.0

- ZetaOffice in the webview (`package:tom_office_editor/zetaoffice.dart`):
  `TomZetaOfficeView` and `TomZetaOfficeController` — the download prompt
  with the size, the cache with checksums and `zetaoffice.version`
  (`TomZetaOfficeCache`), the page and the cached files served cross-origin
  isolated with Brotli (`TomZetaOfficeServer`), the start's progress for up to
  three minutes, ZetaOffice's full interface, save with `store()` and *Save
  as copy* with `storeToURL` through the POST route and `TomBinaryFiles`, a
  failed or unanswered save reported and the document left dirty, undo, redo
  and dirty through the host, one tab at a time, a killed content process
  reported; trail `[ZO]`.
- `testing.dart`: `FakeZetaOfficeFiles`, `FakeZetaOfficeServing`,
  `FakeZetaOfficeChannel`.
- Vendors zetajs's `zeta.js` (MIT) in `assets/zetaoffice/`.

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
