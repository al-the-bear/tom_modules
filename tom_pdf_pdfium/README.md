# tom_pdf_pdfium

The PDFium engine of the PDF editor (`tom_pdf_editor`): `PdfiumEngine`, one
worker isolate shared by every PDF tab that makes every PDFium call over FFI,
the cross-reference fix applied to its saves, and `TomPdfiumLocator`, which
finds the PDFium library in the application's bundle or the binaries layer.
`TomPdfEditor` and its
controller come from `tom_pdf_editor`; a host gives them this engine through
`TomPdfEditorHost`.

The library itself is not in this package: a release carries it in its
bundle, a development machine has it in the binaries layer
(`tom_binaries/pdfium/<platform>/`). No webview and no assets.

License: BSD-3-Clause (see [LICENSE](LICENSE)); PDFium is BSD-3-Clause, with
the third-party parts listed in [THIRD_PARTY.md](THIRD_PARTY.md). Not
published (`publish_to: none`).

## Components

| Component | Where | What it does |
| --- | --- | --- |
| Engine | `lib/src/pdfium_engine.dart`, `lib/src/pdfium_worker.dart`, `lib/src/xref_fix.dart` | `PdfiumEngine` (`tom_pdf_editor`'s `TomPdfEngine`), one worker isolate shared by every PDF tab that makes every PDFium call (PDFium is not thread-safe): renders by priority with cancelling, pages and text pages in a window of 12, search page by page, incremental saves with the cross-reference fix (`/Type/XRef` inserted when PDFium leaves it out, so macOS Preview opens the file). |
| Forms | `lib/src/pdfium_worker.dart` (the editor's `TomPdfEditorController` in `tom_pdf_editor` keeps the history) | AcroForm text fields, checkboxes and radio buttons are filled through PDFium's form-fill environment (`FPDFDOC_InitFormFillEnvironment`, the `FFI_Invalidate` callback `NativeCallable.isolateLocal` on the worker isolate, `FORM_OnAfterLoadPage` / `FORM_OnBeforeClosePage` following the page window, the focused field's page kept open). In the Select tool a click on a field goes to `FORM_OnLButtonDown` / `Up`; typed text to `FORM_OnChar`; Backspace, Delete, arrows, Home, End, Return and Tab (Shift+Tab) to `FORM_OnKeyDown`; Cmd+A selects the field's text; Cmd+Z first undoes the typing inside the focused field (`FORM_Undo`). The focus is released (`FORM_ForceToKillFocus`) when the editor loses the focus, an annotation tool is chosen, Escape, undo, redo or save. Pages `FFI_Invalidate` names are rendered again with `FPDF_FFLDraw`. Each committed change — a text field's text when it loses the focus, a checkbox or radio button at the click — is one history entry beside the annotations; undo sets the value back (`FORM_SetFocusedAnnot`, `FORM_SelectAllText`, `FORM_ReplaceSelection`; a click for a button). A radio group that had no button on cannot go back to none (PDFium has no call for it): that undo says so. Combo boxes, list boxes, push buttons and signature fields are drawn, not filled; no JavaScript runs. Encrypted documents are not filled (DPPF-3). |
| Locator | `lib/src/locator.dart`, `lib/src/library.dart` | `TomPdfiumLocator`: the library in the application's bundle, else `tom_binaries/pdfium/<platform>/libpdfium.dylib` from `TOM_BINARY_PATH`'s parent (see *Where the library is looked for*), refused when its `pdfium.version.json` names another release than the bindings (*PDFium not found*, *PDFium version mismatch*); it answers a `TomPdfiumLibrary`, the editor's `TomPdfEngineStatus` (`kPdfiumBindingsTag` the release the bindings were made for). |
| Bindings | `lib/src/pdfium_bindings.g.dart`, `tool/ffigen.yaml`, `third_party/pdfium/include/` | our own FFIgen bindings (DPPF-1) from the pinned release's headers, only the functions used. |
| Debug | `lib/src/pdfium_trail.dart` | the engine's start and end on the editor's `[PE]` trail (`kPdfEditorDebug`). |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_pdf_pdfium/tom_pdf_pdfium.dart` | `PdfiumEngine`, `fixXrefInFile` and the cross-reference fix's parts, `TomPdfiumLocator`, `TomPdfiumLibrary`, `TomPdfiumProblem`, `kPdfiumBindingsTag` | desktop (`dart:ffi`, `dart:io`) |

## Dependencies

Flutter, `ffi`, `tom_basics` (the bundle-then-binaries lookup,
`native_binaries.dart`), `tom_pdf_editor` by path.

## Where the library is looked for

`TomPdfiumLocator().locate()` takes the first of these that exists:

1. **The running application's bundle**, found from
   `Platform.resolvedExecutable`. macOS:
   `<App>.app/Contents/Frameworks/libpdfium.dylib`, then `Contents/MacOS/`.
   Linux: beside the executable, then the bundle's `lib/` (`libpdfium.so`).
   Windows: beside the executable (`pdfium.dll`). An application started from
   the Finder or the Start menu sees no shell variable, so a release carries
   the library here.
2. **The binaries layer**: `<binaries root>/pdfium/<platform>/<file>`, the
   root being `binariesRoot` or the parent of `$TOM_BINARY_PATH`, the
   platform folder `platform` or the running one (`darwin-arm64`,
   `linux-x64`, `win32-x64`). `flutter run` and `flutter test` reach this
   step.

`libraryPath` replaces both. The release tag is read from
`pdfium.version.json` beside the library, or — in a macOS bundle, which keeps
non-code files out of `Contents/Frameworks/` — from `Contents/Resources/`.
`bundleFolders` and `environment` stand in for the process's, for tests on
fake folders.

## Usage

```dart
import 'package:tom_pdf_editor/tom_pdf_editor.dart';
import 'package:tom_pdf_pdfium/tom_pdf_pdfium.dart';

class MyPdfHost implements TomPdfEditorHost {
  // filePath, name, authorName, files, notice, openLink, historyChanged ...
  @override
  TomPdfiumLibrary get engineStatus => const TomPdfiumLocator().locate();
  @override
  Future<TomPdfEngine> startEngine(TomPdfiumLibrary library) =>
      PdfiumEngine.acquire(library.path!);
}
```

The example app (`example/`) is a complete desktop host with the macOS
integration tests. Building, taking in a PDFium release and the tests:
`_agent_guidelines/build.md` in this package.
