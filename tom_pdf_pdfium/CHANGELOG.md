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
