# Building and testing tom_pdf_editor

## PDFium

The library is not in this package. It lives in the binaries layer,
`tom_binaries/pdfium/<platform>/` (only `darwin-arm64` in the prototype):
`libpdfium.dylib` (re-signed ad hoc), `LICENSE`, `licenses/` and
`pdfium.version.json`. `TomPdfiumLocator` finds it from `TOM_BINARY_PATH`'s
parent and refuses a library whose version file names another release than
`kPdfiumBindingsTag` (`lib/src/engine/library.dart`).

## Taking in a PDFium release

All of these together, in one change:

1. Download the release's `pdfium-mac-arm64.tgz` from
   [pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases)
   and check its SHA-256 against the digest GitHub records for the asset.
2. In the binaries layer: replace `libpdfium.dylib` (re-sign it:
   `codesign -s - -f libpdfium.dylib`), `LICENSE`, `licenses/`, and update
   `pdfium.version.json` (tag, version, asset SHA-256, date). Push with
   `/tom_push_binaries`.
3. Here: replace `third_party/pdfium/include/` with the archive's `include/`
   (leave out `fpdfview.h.orig`), update `third_party/pdfium/SOURCE.md` and
   `LICENSE` (the archive's `licenses/pdfium.txt`).
4. Regenerate the bindings (below) and set `kPdfiumBindingsTag` to the new
   tag.
5. Run every test, the `pdfium` ones included. `PDFIUM-SAVE-1` shows whether
   the new PDFium still needs the cross-reference fix (when it writes
   `/Type /XRef` itself, the fix is a no-op).

## The bindings

```sh
dart run ffigen --config tool/ffigen.yaml
```

It writes `lib/src/pdfium/pdfium_bindings.g.dart` (committed, excluded from
analysis): only the functions `tool/ffigen.yaml` lists, as a class over a
`DynamicLibrary` (the library is opened at runtime from the locator's path).
A new call means adding it to the list and regenerating. FFIgen needs
libclang (the Command Line Tools' one is found on macOS).

## Tests

```sh
testkit :test                   # all, the PDFium ones included
flutter test -x pdfium          # without PDFium
```

- `test/editor_test.dart`, `test/units_test.dart`: the widget and the pure
  parts against `testing.dart`'s fake engine.
- `test/integration/` (tag `pdfium`): the engine and the controller on the
  real library over the tom_forge sample set (`TOM_PDF_SAMPLES` overrides the
  folder); they skip where either is missing. On macOS `PDFIUM-SAVE-1` also
  opens the saved files with PDFKit (Preview's engine), with and without the
  cross-reference fix. `PDF-ANNOT-1` creates, changes and removes
  annotations, saves incrementally (the original bytes a prefix of the
  saved file), reopens and has PDFKit list them. `PDF-FORM-1` (engine) and
  `PDF-REAL-5` (controller) fill `pdf-form`'s text fields and checkboxes,
  undo, redo, save, reopen and have PDFKit read the values.
- Chrome's viewer cannot be screenshotted headless (the PDF plugin does not
  draw there); to check a saved file in it, start Chrome with
  `--remote-debugging-port` and take `Page.captureScreenshot` over the
  DevTools protocol.

## pdf.js

The vendored pdf.js is `third_party/pdfjs/<version>/` (`pdfjs.version.json`
records the archives and their SHA-256). Taking in a new release:

1. Download `pdfjs-<version>-legacy-dist.zip` (the legacy build: the modern
   one needs ES2026 APIs macOS 15's WebKit lacks) and the npm tarball
   `pdfjs-dist-<version>.tgz`; check their SHA-256 / `integrity`.
2. Replace the folder: the zip's `LICENSE`, `build/` and `web/` without the
   `.map` files; `components/` from the tarball's `legacy/web/pdf_viewer.mjs`,
   `pdf_viewer.css`, `images/` and its `LICENSE`. Update the version file and
   `kPdfJsVersion` (`lib/src/pdfjs/controller.dart`).
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

## The example app

`example/` is the editor in a window on the real library:

```sh
cd example
TOM_PDF_FILE=/path/to/a.pdf flutter run -d macos
flutter test integration_test -d macos   # the samples: open, scroll, zoom, search, copy
flutter test integration_test/pdfjs_test.dart -d macos   # the pdf.js view, all three modes
```

It is unsandboxed like `tom_forge_app`: the App Sandbox blocks loading
PDFium from the binaries layer.
