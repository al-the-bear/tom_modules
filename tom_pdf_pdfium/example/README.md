# tom_pdf_pdfium_example

The PDF editor (`tom_pdf_editor`) in a macOS window on the PDFium engine
(`tom_pdf_pdfium`), the library taken from the binaries layer
(`TOM_BINARY_PATH`'s parent, `pdfium/darwin-arm64/`).

```sh
TOM_PDF_FILE=/path/to/a.pdf flutter run -d macos
flutter test integration_test -d macos   # the samples: open, scroll, zoom, search, copy
```

The app is unsandboxed like `tom_forge_app`: the App Sandbox blocks loading
PDFium from the binaries layer. The pdf.js view has its own example,
`tom_pdf_pdfjs/example`.
