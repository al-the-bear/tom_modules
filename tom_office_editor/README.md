# tom_office_editor

A Flutter widget that shows and edits one office document (DOCX, XLSX, PPTX,
the OpenDocument formats, and the older `.doc`, `.xls`, `.ppt`, `.rtf`,
`.csv`) with the installed LibreOffice. LibreOffice runs in a helper process,
`tom_office_host` (`tom_ai/modules/tom_office_host`), one per document,
speaking protocol 1 (`tom_office_protocol`); everything LibreOffice renders
arrives as tiles, and everything it should do leaves as a protocol message. A
controller beside the widget is what a host drives: open, save, undo, redo,
the dirty state, external changes.

License: BSD-3-Clause (see [LICENSE](LICENSE)). LibreOffice is not bundled; the
user installs it. Not published (`publish_to: none`).

Beside it, `TomZetaOfficeView` shows a document in ZetaOffice — LibreOffice
compiled to WebAssembly, with its full interface — in a webview, as the
prototype's comparison route. Its files are downloaded once at run time after
the user confirms; third-party notices: [THIRD_PARTY.md](THIRD_PARTY.md).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| Editor | `lib/src/widgets/office_editor.dart` | `TomOfficeEditor`: the view for each state (loading with LibreOffice's progress, detection's state, the masked password question, *LibreOffice stopped* with *Reopen*, *could not be opened*), the read-only bar with *Save as copy* (for a password-protected document after a warning: *Save with password*, the default, or *Save without password*), the conflict banner (*Keep mine* after a confirmation, *Take theirs*, *Save as copy*), the deleted-file bar, a spreadsheet's formula line, row and column headers and sheet tabs, a presentation's slide strip with thumbnails, the zoom (50–300 % and *fit width*) and save state. It hands the controller's notices to the host. |
| View | `lib/src/widgets/document_view.dart` | `TomOfficeDocumentView`: the document as 256 × 256 tiles (twice the pixels at device pixel ratio 2), visible ones first and one ring around them, other zooms' tiles shown scaled until the new ones arrive; LibreOffice's caret (blinking), text selection with drag handles, a shape's frame, the cell cursor and the mouse pointer; scrolling in Flutter (two scroll controllers), `view` sent after each scroll or zoom; Cmd + / − / 0, Ctrl + wheel and pinch zoom. Input while focused: keys without text as VCL key codes, text through the platform's input method (`DeltaTextInputClient`: composing text as `textInput input`, the commit as `textInput end`, the caret rectangle reported for the candidate window), mouse clicks with their count and buttons, hover moves at most every 50 ms, the right click and LibreOffice's context menu (every entry), copy, cut and paste (text). Cmd+S, Cmd+Z, Shift+Cmd+Z, Cmd+W and Cmd+F are left to the shell. |
| Ribbon | `lib/src/ribbon/` | `TomOfficeRibbon` above the document: the tabs Home, Insert, Layout, Data, Review and View with the controls of the document type (`officeRibbonTabs`), only commands that work in LibreOfficeKit (the first spike's item 9 and its retest: `.uno:InsertSymbol`, the footer with its page style, `.uno:Color` for the font colour, super- and subscript while a cell is edited, Impress's paragraph, list and colour commands in a text's edit mode). A command button shows `STATE_CHANGED` (`true` checked, `disabled` disabled); the font, size and paragraph-style dropdowns are filled from `getCommandValues`; font colour, highlighting and background colour are split buttons with the colour picker (LibreOffice's Standard palette, recent colours, *Automatic*, *Custom colour…* opening the properties dialog whose page holds *Pick…*). Tab and the arrow keys move between the controls; *Insert image* asks the host (`pickImage`); Cmd+F opens Find & Replace. A dialog a command opens is closed with a notice naming it until the dialog part shows them. |
| Dialogs | `lib/src/widgets/dialog_layer.dart` | `TomOfficeDialogLayer` over the document: LibreOffice's dialogs as windows (window mode, DPLH-4). A `windowOpened` becomes an overlay of the reported size, modal (a barrier under it), centred and draggable by its title bar (whose close button sends `windowClose`); a child window (a combo box's list) sits at its `position` in its parent. Its pixels come by `paintWindow` and are asked again on `invalidate` and `size_changed` (one paint at a time per window); LibreOffice's text cursor is drawn on them. Mouse, keys and typed characters go back as `windowMouse` and `windowKey`. *Dialogs: LibreOffice windows / Forge forms* in the status line sends `dialogMode` (a host's tab menu calls `setDialogMode`); a tab starts with windows. LibreOffice's desktop build has no JSON dialogs: the helper refuses `json`, the tab stays with windows and says so, and a `JSDIALOG` would only be counted. |
| Controller | `lib/src/controller.dart` | `TomOfficeEditorController`: opening (detection must be `found`; the revision taken before `open` and after `opened`, a file changed during the load reopened), passwords (three attempts, never stored or logged), read-only documents (the host's request, a file that cannot be written, another LibreOffice's lock, a cancelled password to modify, a password-protected file: DPOE-3), tiles (requests coalesced per tile, decoded with `decodeImageFromPixels`), the repaint after the editor's own input (LibreOffice 26.8.3.1 sends no `INVALIDATE_TILES` for edits: the visible tiles are marked stale at the next cursor, state, cell or size callback, or 100 ms after the input), saving (a temporary target beside the file, `save` in the file's own format, `TomBinaryFiles.replace` over an unchanged original, else the conflict), CSV with explicit filter options both ways, external changes (`checkExternal`), undo, redo and dirty from `STATE_CHANGED` (`.uno:Undo`, `.uno:Redo`, `.uno:ModifiedStatus`), the helper stopping (a crash, or a hang: no `pong` in 20 s), a dialog closed with a notice until the dialog part shows them. |
| Host | `lib/src/host.dart` | `TomOfficeEditorHost`: the file, its access (`TomBinaryFiles`), the helper launcher, notices, links (`HYPERLINK_CLICKED`), history changes, the image picker of *Insert image* (`pickImage`). |
| Tiles | `lib/src/tiles/tile_cache.dart` | `TileCache`: least recently used, bounded by memory (256 MiB), keyed by part, zoom, column and row; invalidation by twip rectangle. |
| Callbacks | `lib/src/callbacks.dart` | The callback payloads as LibreOffice 26.8.3.1 sends them, parsed: rectangles, selections, the cell cursor, `INVALIDATE_TILES`, `STATE_CHANGED`, the context menu, links, command results. |
| Detection | `lib/src/io/detector.dart`, `lib/src/detection/installation.dart` | `TomLibreOfficeDetector` (macOS): the user's path (its state, no fallback), `/Applications`, `~/Applications`, Spotlight (the newest usable copy); *Auto-detect* (`autoDetect`) adds `PATH`, the installation folders one level down (`LibreOffice*.app`, `LibreOfficeDev*.app`, `Collabora Office*.app`), Homebrew casks and MacPorts. A copy is read from `Info.plist` without starting anything, checked for its parts, the minimum version (26.8.3.1, the version on mbp: DPLD-1), the architecture (`lipo`), the signature (`codesign --verify`), quarantine (`xattr`, `spctl`), and cross-checked with `soffice --headless --version` under a private profile (15 s). States: `found`, `missing`, `tooOld`, `damaged`, `quarantined`. |
| Launcher | `lib/src/io/process_launcher.dart` | `TomOfficeProcessLauncher`: starts `tom_office_host` (found with `findHelper` in `$TOM_BINARY_PATH/<os>-<arch>/`) with the program folder and a private profile under `<temp>/office-host/<pid>-<n>/`; `close` sends `close`, then SIGTERM after 5 s, SIGKILL after 2 s more. `cleanUp` removes what dead helpers left: profiles, the `.~lock.<name>#` file naming a dead helper's profile, the temporary files of an interrupted save. |
| Fake helper | `lib/src/testing/fake_helper.dart` | `FakeOfficeHelperChannel` (fixed tiles, scripted callbacks, passwords, saves, a crash or a hang) and `FakeOfficeHelperLauncher`. |
| ZetaOffice | `lib/src/zetaoffice/` | `TomZetaOfficeView` and `TomZetaOfficeController`: the download prompt naming the size (52.5 MB from cdn.zetaoffice.net, nothing fetched before the user says yes; a damaged cache offered again), the download's progress, the start's progress for up to three minutes (`soffice.js`'s load event, then `Module.uno_main`), ZetaOffice's full interface in an `InAppWebView`. The document is handed in with `FS.writeFile`; *Save* runs `store()` in the file's own format and *Save as copy* `storeToURL`; the page POSTs the bytes back and `TomBinaryFiles` writes them (a changed file is a conflict; a failed or unanswered save is reported and leaves the document dirty). Undo, redo and dirty through the same host as the native editor (`historyChanged`). One ZetaOffice tab at a time; a killed web content process is reported with *Reopen*. `TomZetaOfficeCache`: the files under `~/Library/Caches/tom_office_editor/zetaoffice/`, the Brotli ones kept as `<name>.br`, `zetaoffice.version` with each file's size and SHA-256 (checked at every open). `TomZetaOfficeServer`: the page from `assets/zetaoffice/` and the cache through `TomLocalContentServer`, cross-origin isolated (COOP/COEP), `.br` served with `Content-Encoding: br`, the document and the save routes. Trail `kZetaOfficeDebug`, prefix `[ZO]`. |
| Debug | `lib/src/office_editor_trail.dart` | `kOfficeEditorDebug` (switchable at run time), prefix `[OE]`: state changes, every message by type and id (tiles summarised once a second), callback types, input as kind and key code (text by its length), save steps and conflicts, the helper's exit and stderr, focus changes; the heartbeat and the `FlutterError` intercept while on. Errors are reported through `FlutterError.reportError` whether it is on or off. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_office_editor/tom_office_editor.dart` | the widget, controller, host, tile cache, detection's answer, the helper channel interface | all (no `dart:io`) |
| `package:tom_office_editor/io.dart` | `TomLibreOfficeDetector`, `TomOfficeProcessLauncher`, `TomBinaryFileAccess` | desktop (`dart:io`) |
| `package:tom_office_editor/zetaoffice.dart` | `TomZetaOfficeView`, `TomZetaOfficeController`, `TomZetaOfficeCache`, `TomZetaOfficeServer`, the files, channel and serving interfaces, `kZetaOfficeDebug` | desktop (macOS: WKWebView) |
| `package:tom_office_editor/testing.dart` | `FakeOfficeHelperChannel`, `FakeOfficeHelperLauncher`, `FakeZetaOfficeFiles`, `FakeZetaOfficeServing`, `FakeZetaOfficeChannel` | all |

## Usage

```dart
import 'package:tom_office_editor/io.dart';
import 'package:tom_office_editor/tom_office_editor.dart';

final installation = await TomLibreOfficeDetector().detect();
final controller = TomOfficeEditorController(
  host: MyOfficeHost(
    filePath: path,
    files: TomBinaryFileAccess(),
    helper: TomOfficeProcessLauncher(
      installation: installation,
      helperExecutable: TomOfficeProcessLauncher.findHelper()!,
    ),
  ),
);
await controller.open();
// In the tree:
TomOfficeEditor(controller: controller);
// The shell's commands:
await controller.save();
controller.undo();
await controller.checkExternal(); // when the window regains focus
```

ZetaOffice:

```dart
import 'package:tom_office_editor/zetaoffice.dart';

final zeta = TomZetaOfficeController(
  host: host, // the same TomOfficeEditorHost
  files: TomZetaOfficeCache(),
  serving: TomZetaOfficeServer(files: host.files),
);
await zeta.prepare(); // the cache's check; the view asks before downloading
// In the tree:
TomZetaOfficeView(controller: zeta);
await zeta.save();
```

`example/` is a macOS app that opens the sample DOCX, XLSX and PPTX of the
tom_forge prototype; its integration test opens, edits, saves and reopens each.
The *ZetaOffice* switch opens them in `TomZetaOfficeView` instead.

## Tests

```sh
testkit :test                       # widget, detection, payload and tile tests
testkit :test --test-args="-x libreoffice"   # without the real helper
cd example && flutter test integration_test/samples_test.dart -d macos
cd example && flutter test integration_test/ribbon_test.dart -d macos
cd example && flutter test integration_test/dialogs_test.dart -d macos
cd example && flutter test integration_test/zetaoffice_test.dart -d macos
```

`zetaoffice_test.dart` opens report.docx, sheet.xlsx and deck.pptx in
ZetaOffice (downloading it first when the cache is empty), edits each through
UNO, saves it, checks the saved file and reopens it from the cache with the
change; letter.docx, which ZetaOffice cannot store as DOCX, must fail to save,
stay dirty and leave the file as it was. `--dart-define=ZETA_SAMPLES=deck.pptx`
runs one sample.

`ribbon_test.dart` formats each sample through the ribbon (text: font, size,
bold, colour, alignment, list, paragraph style; sheet: sort, bold, background,
currency; slides: new slide, layout, colour, alignment), saves it and checks
the saved file. `dialogs_test.dart` opens Character, Paragraph, Page Style,
Find & Replace, Format Cells, the colour dialog, the Chart Wizard and Insert
Table from the ribbon, checks each is painted and takes input, and closes it.

The `libreoffice`-tagged tests start the real helper from the binaries layer
against the installed LibreOffice and skip themselves where either is missing.

## Not yet in this package

JSON dialogs as Flutter forms: LibreOffice's desktop build sends none.
Detection covers macOS; Linux and Windows locations come later.
