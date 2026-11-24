# Building and testing tom_pdf_pdfjs

## pdf.js

The vendored pdf.js is `third_party/pdfjs/<version>/` (`pdfjs.version.json`
records the archives and their SHA-256). Taking in a new release:

1. Download `pdfjs-<version>-legacy-dist.zip` (the legacy build: the modern
   one needs ES2026 APIs macOS 15's WebKit lacks) and the npm tarball
   `pdfjs-dist-<version>.tgz`; check their SHA-256 / `integrity`.
2. Replace the folder: the zip's `LICENSE`, `build/` and `web/` without the
   `.map` files; `components/` from the tarball's `legacy/web/pdf_viewer.mjs`,
   `pdf_viewer.css`, `images/` and its `LICENSE`. Update the version file and
   `kPdfJsVersion` (`lib/src/controller.dart`).
   Then re-apply the recorded deviation: pdf.js's GPL Liberation Sans in
   `web/standard_fonts/` are replaced by the OFL Liberation Sans 2.x
   (`deviations` in `pdfjs.version.json`: the archive, its SHA-256 and each
   font's); `PDFJS-LIC-1` fails while a GPL text is in the folder.
3. `python3 tool/pdfjs_assets.py` writes the asset folders into
   `pubspec.yaml` (`--check` tells whether they are current).
4. `hostPage` checks that `web/viewer.html` still has the two lines it adds
   beside; run every test, `PDFJS-SITE-1` and the example's
   `integration_test/pdfjs_test.dart` included.

Forge's own files (`assets/pdfjs_forge/`): `options.js` (the viewer's
options), `bridge.mjs` (the bridge and its test hooks), `generic.mjs` (the
bridge on the generic viewer), `integrated.css`, `components.html` /
`.mjs` / `.css`.

## Tests

```sh
flutter test                    # the view against FakePdfJsChannel
```

`test/pdfjs_test.dart`: the content site, the host pages, the bridge both
ways and the save path against the fake channel and the real local server;
`PDFJS-LIC-1` checks the vendored folder's licences.

## The example app

`example/` is the pdf.js view in a window:

```sh
cd example
TOM_PDF_FILE=/path/to/a.pdf TOM_PDF_VIEW=integrated flutter run -d macos
flutter test integration_test -d macos   # all three modes, the content process
```

It is unsandboxed like `tom_forge_app` and may act as a server (the local
content server). `integration_test/pdfjs_test.dart` reads the saved files
back with PDFium, so the example (only it, as a dev dependency) takes
`tom_pdf_pdfium` and the integration tests need the library in the binaries
layer.
