## 0.1.0

- The vendored pdf.js `third_party/pdfjs/6.5.438/build/` (`pdf.mjs`, its worker,
  sandbox and renderer, byte-identical to the release zip) is in the package:
  the `.gitignore` rule `build/` hid it, so a fresh clone had a viewer that
  never started. The rule is `/build/` now; `PDFJS-VENDOR-1` checks the files.

- The pdf.js view of the PDF editor as a package of its own (it was part of
  `tom_pdf_editor` 0.1.0, `pdfjs.dart`): `TomPdfJsView`,
  `TomPdfJsController`, `TomPdfJsChannel` in the modes `integrated`, `full`
  and `components`, pdf.js 6.5.438 (legacy build, vendored unmodified but for
  its Liberation Sans fonts, the OFL 2.1.5 release) with Forge's own files
  (`assets/pdfjs_forge/`), served by `TomLocalContentServer`; saves through
  `TomBinaryFiles` with the conflict banner; the content-process recovery.
- The assets are `packages/tom_pdf_pdfjs/...` (`kPdfJsAssets`,
  `kPdfJsForgeAssets`); `tool/pdfjs_assets.py` keeps the asset list.
- `testing.dart`: `FakePdfJsChannel`.
- The example app (`example/`) with the view's macOS integration tests.
