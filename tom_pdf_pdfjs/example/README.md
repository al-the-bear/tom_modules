# tom_pdf_pdfjs_example

The pdf.js view (`tom_pdf_pdfjs`) in a macOS window, in the mode
`TOM_PDF_VIEW` names (`components`, the default, `integrated` or `full`).

```sh
TOM_PDF_FILE=/path/to/a.pdf TOM_PDF_VIEW=integrated flutter run -d macos
flutter test integration_test -d macos   # all three modes, the content process
```

The app is unsandboxed like `tom_forge_app` and may act as a server (the
local content server pdf.js is served from). `integration_test/pdfjs_test.dart`
reads the saved files back with PDFium, so the integration tests (only they)
take `tom_pdf_pdfium` as a dev dependency and need the library in the
binaries layer.
