# PDFium headers

The public headers of PDFium, unchanged, from the `include/` folder of the
pdfium-binaries release the binaries layer holds
(`tom_binaries/pdfium/darwin-arm64/`):

| | |
| --- | --- |
| Project | [pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) |
| Release tag | `chromium/8152` (PDFium 159.0.8152.0) |
| Asset | `pdfium-mac-arm64.tgz`, SHA-256 `30b0c3f55448840f0947b54bedbe35185bbaccbadd35b8cd960270d6fa6caf80` |
| Build | `is_debug=false pdf_enable_v8=false pdf_enable_xfa=false target_cpu=arm64 target_os=mac` |
| Taken in | 2026-11-18 |

`fpdfview.h.orig` from the archive (a patch leftover of its build) is left
out. The bindings in `lib/src/pdfium/pdfium_bindings.g.dart` are generated
from these headers (`tool/ffigen.yaml`); `TomPdfiumLocator` refuses a library
whose `pdfium.version.json` names another tag.

## Licence

PDFium is BSD-3-Clause ([LICENSE](LICENSE), PDFium's own `pdfium.txt` from the
archive's `licenses/`).
