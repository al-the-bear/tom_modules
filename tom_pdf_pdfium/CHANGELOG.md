## 0.2.0

- `TomPdfiumLocator` looks in the running application's bundle first:
  macOS `<App>.app/Contents/Frameworks/libpdfium.dylib`, then
  `Contents/MacOS/`; Linux beside the executable, then the bundle's `lib/`;
  Windows beside the executable. Then in the binaries layer as before. An
  application started from the Finder or the Start menu sees no
  `TOM_BINARY_PATH`, so a release carries the library in its bundle.
  `bundleFolders` replaces the bundle's folders for tests; `bundlePath` and
  `binariesPath` name the two places.
- `pdfium.version.json` is also read from a macOS bundle's
  `Contents/Resources/`.
- `platform` defaults to the running platform's folder (it was always
  `darwin-arm64`) and is nullable; `platformFolder` answers the one used.
- The lookup is `tom_basics`' `TomNativeBinaries` (`tom_basics: ^3.4.0`).

## 0.1.0

- The PDFium engine of the PDF editor as a package of its own (it was part
  of `tom_pdf_editor` 0.1.0): `PdfiumEngine` (one shared worker isolate makes
  every PDFium call; renders by priority, cancellable; documents from a path
  or from bytes; annotations and AcroForm filling through PDFium's form-fill
  environment; incremental saves with the cross-reference fix), the fix
  itself (`fixXrefInFile`, `startxrefOffset`, `xrefTypeInsertionPoint`,
  `fixXrefObject`), `TomPdfiumLocator` and `TomPdfiumLibrary`, the FFIgen
  bindings (`tool/ffigen.yaml`) over the vendored PDFium headers.
- `TomPdfiumLibrary` implements `tom_pdf_editor`'s `TomPdfEngineStatus`: a
  host answers it as `TomPdfEditorHost.engineStatus` and takes it back in
  `startEngine`.
- The engine's tests on the real library (tag `pdfium`) and the example app
  with its macOS integration tests (`example/`).
- A cancel no longer outlives its render. The worker kept every cancelled
  ticket in a set until a render with that ticket came; a cancel that
  arrived while its render ran, or after, stayed there, and dropped the next
  render sent with the same ticket (the first page of the next document
  opened on the shared engine never drew). The worker now drops a queued
  render at once and forgets a cancel that finds none; the engine sends no
  cancel for a ticket it has no render outstanding for, with a trail line
  (`cancel ticket <n>: no render outstanding, ignored`). Test
  `PDFIUM-RENDER-2`.
