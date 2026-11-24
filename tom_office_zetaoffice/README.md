# tom_office_zetaoffice

The office editor's ZetaOffice route: `TomZetaOfficeView` shows one office
document in ZetaOffice — LibreOffice compiled to WebAssembly, with its full
interface — in a webview. It runs on the same host as the native office
editor (`TomOfficeEditorHost` from
[`tom_office_editor`](../tom_office_editor/)), so a shell opens a document in
either route the same way. ZetaOffice's files are downloaded once at run time
after the user confirms and kept on the machine; nothing of ZetaOffice is
bundled.

License: BSD-3-Clause (see [LICENSE](LICENSE)). Third-party notices:
[THIRD_PARTY.md](THIRD_PARTY.md). Not published (`publish_to: none`).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| View and controller | `lib/src/view.dart`, `lib/src/controller.dart` | `TomZetaOfficeView` and `TomZetaOfficeController`: the download prompt naming the size (52.5 MB from cdn.zetaoffice.net, nothing fetched before the user says yes; a damaged cache offered again), the download's progress, the start's progress for up to three minutes (`soffice.js`'s load event, then `Module.uno_main`), ZetaOffice's full interface in an `InAppWebView`. The document is handed in with `FS.writeFile`; *Save* runs `store()` in the file's own format and *Save as copy* `storeToURL`; the page POSTs the bytes back and `TomBinaryFiles` writes them (a changed file is a conflict; a failed or unanswered save is reported and leaves the document dirty). Undo, redo and dirty through the host (`historyChanged`). One ZetaOffice tab at a time; a killed web content process is reported with *Reopen*. |
| Cache | `lib/src/cache.dart`, `lib/src/files.dart` | `TomZetaOfficeCache`: the files under `~/Library/Caches/tom_office_editor/zetaoffice/`, the Brotli ones kept as `<name>.br`, `zetaoffice.version` with each file's size and SHA-256 (checked at every open). `TomZetaOfficeFiles` is the interface the controller takes. |
| Server | `lib/src/serving.dart` | `TomZetaOfficeServer`: the page from `assets/zetaoffice/` and the cache through `TomLocalContentServer`, cross-origin isolated (COOP/COEP), `.br` served with `Content-Encoding: br`, the document and the save routes. |
| Fakes | `lib/src/testing/fake_zetaoffice.dart` | `FakeZetaOfficeFiles`, `FakeZetaOfficeServing`, `FakeZetaOfficeChannel`. |
| Debug | `lib/src/trail.dart` | `kZetaOfficeDebug` (switchable at run time), prefix `[ZO]`. Errors are reported through `FlutterError.reportError` whether it is on or off. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_office_zetaoffice/tom_office_zetaoffice.dart` | `TomZetaOfficeView`, `TomZetaOfficeController`, `TomZetaOfficeCache`, `TomZetaOfficeServer`, the files, channel and serving interfaces, `kZetaOfficeDebug` | desktop (macOS: WKWebView) |
| `package:tom_office_zetaoffice/testing.dart` | `FakeZetaOfficeFiles`, `FakeZetaOfficeServing`, `FakeZetaOfficeChannel` | all |

## Usage

```dart
import 'package:tom_office_zetaoffice/tom_office_zetaoffice.dart';

final zeta = TomZetaOfficeController(
  host: host, // a TomOfficeEditorHost (package:tom_office_editor)
  files: TomZetaOfficeCache(),
  serving: TomZetaOfficeServer(files: host.files),
);
await zeta.prepare(); // the cache's check; the view asks before downloading
// In the tree:
TomZetaOfficeView(controller: zeta);
await zeta.save();
```

`example/` is a macOS app that opens the sample DOCX, XLSX and PPTX of the
tom_forge prototype in `TomZetaOfficeView`.

## Tests

```sh
testkit :test
cd example && flutter test integration_test/zetaoffice_test.dart -d macos
```

`zetaoffice_test.dart` (example) opens report.docx, sheet.xlsx and deck.pptx
in ZetaOffice (downloading it first when the cache is empty), edits each
through UNO, saves it, checks the saved file and reopens it from the cache
with the change; letter.docx, which ZetaOffice cannot store as DOCX, must
fail to save, stay dirty and leave the file as it was.
`--dart-define=ZETA_SAMPLES=deck.pptx` runs one sample.
