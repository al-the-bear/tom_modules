# Third-party components

| Component | Where | Licence | How it is used |
| --- | --- | --- | --- |
| PDFium (PDFium 159.0.8152.0, pdfium-binaries `chromium/8152`) — headers | [`third_party/pdfium/include/`](third_party/pdfium/SOURCE.md) | BSD-3-Clause ([text](third_party/pdfium/LICENSE)) | unmodified; FFIgen reads them into `lib/src/pdfium/pdfium_bindings.g.dart` |
| PDFium — the library | the binaries layer, `tom_binaries/pdfium/darwin-arm64/libpdfium.dylib`, loaded at runtime | BSD-3-Clause, with the third-party code built into it under permissive licences (FreeType, HarfBuzz, ICU, libjpeg-turbo, OpenJPEG, libpng, zlib, lcms2, abseil, …): one text each in `tom_binaries/pdfium/darwin-arm64/licenses/` | not shipped in this package; `TomPdfiumLocator` finds it |
| pdfium-binaries build scripts | `tom_binaries/pdfium/darwin-arm64/LICENSE` | MIT (Benoît Blanchon) | the scripts that built the library; nothing of them is in this package |

Nothing built into the library is copyleft (the GPL texts in ICU's licence
file are for ICU's Autoconf scripts, which are not built in). Forge's licence
audit covers the package.

The Dart packages it depends on are listed with their licences by
`flutter pub deps`; all are permissive (BSD-3-Clause, MIT, Apache-2.0).
