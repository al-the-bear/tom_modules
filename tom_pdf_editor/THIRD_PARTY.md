# Third-party components

| Component | Where | Licence | How it is used |
| --- | --- | --- | --- |
| PDFium (PDFium 159.0.8152.0, pdfium-binaries `chromium/8152`) — headers | [`third_party/pdfium/include/`](third_party/pdfium/SOURCE.md) | BSD-3-Clause ([text](third_party/pdfium/LICENSE)) | unmodified; FFIgen reads them into `lib/src/pdfium/pdfium_bindings.g.dart` |
| PDFium — the library | the binaries layer, `tom_binaries/pdfium/darwin-arm64/libpdfium.dylib`, loaded at runtime | BSD-3-Clause, with the third-party code built into it under permissive licences (FreeType, HarfBuzz, ICU, libjpeg-turbo, OpenJPEG, libpng, zlib, lcms2, abseil, …): one text each in `tom_binaries/pdfium/darwin-arm64/licenses/` | not shipped in this package; `TomPdfiumLocator` finds it |
| pdf.js 6.5.438 (Mozilla) — the **legacy** generic viewer build, `build/` and `web/` from `pdfjs-6.5.438-legacy-dist.zip` (SHA-256 `55138aa3…6daa6a844`), without the source maps | [`third_party/pdfjs/6.5.438/`](third_party/pdfjs/6.5.438/pdfjs.version.json) | Apache-2.0 ([text](third_party/pdfjs/6.5.438/LICENSE)); the build carries core-js (MIT) polyfills | unmodified Flutter assets, served to the pdf.js view's webview by `TomLocalContentServer`; Forge's changes are its own files in `assets/pdfjs_forge/` |
| pdf.js 6.5.438 viewer components — `legacy/web/pdf_viewer.mjs`, `pdf_viewer.css` and `images/` from the npm package `pdfjs-dist` 6.5.438 (SHA-256 `7461aefc…3d6faa`) | [`third_party/pdfjs/6.5.438/components/`](third_party/pdfjs/6.5.438/components/LICENSE) | Apache-2.0 | unmodified, for the `components` mode |
| pdfium-binaries build scripts | `tom_binaries/pdfium/darwin-arm64/LICENSE` | MIT (Benoît Blanchon) | the scripts that built the library; nothing of them is in this package |

pdf.js's `web/` brings data with licences of its own, each beside it:
`wasm/` (OpenJPEG BSD-2-Clause, PDFium's JBIG2 decoder BSD-3-Clause, qcms
MIT, QuickJS MIT, with pdf.js's notices for each), `iccs/` (CC0-1.0),
`standard_fonts/` (the Foxit fonts BSD-3-Clause; **the Liberation Sans fonts
GPL-2.0 with a font exception**, `LICENSE_LIBERATION`). The Liberation fonts
are the one copyleft part: separate data files pdf.js fetches when a PDF
lacks its own fonts, kept unmodified with pdf.js; whether they stay under
Forge's licence rule (no copyleft in an app built on Forge) is an open
decision of the tom_forge quest.

pdf.js is vendored with its version file `pdfjs.version.json` (tag, build,
the SHA-256 of both archives and what was taken from each). Taking in a new
release: replace the folder, update the version file and the asset list
(`python3 tool/pdfjs_assets.py`), run the tests.

Nothing built into the PDFium library is copyleft (the GPL texts in ICU's licence
file are for ICU's Autoconf scripts, which are not built in). Forge's licence
audit covers the package.

The Dart packages it depends on are listed with their licences by
`flutter pub deps`; all are permissive (BSD-3-Clause, MIT, Apache-2.0).
