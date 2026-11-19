# tom_office_host

The LibreOfficeKit helper process of the office editors. It holds exactly one
office document open in LibreOfficeKit and serves the office editor
(`tom_office_editor`) over protocol 1 of
[`tom_office_protocol`](../tom_office_protocol/README.md) on its stdin and
stdout. Nothing of LibreOffice is linked: the helper loads it at runtime from
the installation it is given, so a crash or hang in LibreOffice ends only the
helper.

License: BSD-3-Clause (see [LICENSE](LICENSE)); the vendored LibreOfficeKit
headers are MPL-2.0 ([THIRD_PARTY.md](THIRD_PARTY.md)). Not published
(`publish_to: none`). An application package: its `pubspec.lock` is tracked.

## Command line

```text
tom_office_host --program <Frameworks path> --profile <profile url> --protocol 1
```

| Option | Meaning |
| --- | --- |
| `--program` | LibreOffice's program folder, the one holding `libmergedlo` (`/Applications/LibreOffice.app/Contents/Frameworks` on macOS, the default) |
| `--profile` | the helper's private profile as a `file://` URL, one per helper; deleted on a clean close (default: a new folder under the system temp) |
| `--protocol` | the protocol number the caller speaks; anything but 1 is refused |
| `--version`, `--help` | from `tom_build_base` |

The office editor starts it; it is not meant to be run by hand. stdout carries
only protocol frames; stderr is the helper's log, which never holds a
password or typed text.

## What it serves

| Area | Messages | LibreOfficeKit |
| --- | --- | --- |
| Start | `hello` (protocol, versions, pid) | `lok_init_2`, `setOptionalFeatures` (passwords, comments as callbacks) |
| Open | `open` → `opened`, or `passwordNeeded` ↔ `password` | `documentLoadWithOptions`; the password is answered by the C trampoline during the load (once per answer, so a wrong one asks again) |
| Tiles | `renderTile` → `tile` (BGRA on macOS) | `paintPartTile`; queued requests for one area are coalesced into the newest |
| Input | `key`, `textInput`, `mouse`, `selection`, `copy` → `clipboard`, `paste` | `postKeyEvent`, `postWindowExtTextInputEvent` (window 0), `postMouseEvent`, `set*Selection`, `getTextSelection`, `paste` |
| Commands | `uno`, `commandValues` → `values`, `view`, `setPart` | `postUnoCommand` from a second isolate (a modal dialog blocks the call until it closes), `getCommandValues`, `setClientZoom` / `setClientVisibleArea`, `setPart` |
| Callbacks | `callback` (name and payload, uninterpreted) | every `LOK_CALLBACK_*` except the password ones |
| Dialogs | `windowOpened`, `windowChanged`, `paintWindow` → `windowPixels`, `windowMouse`, `windowKey`, `windowTextInput`, `windowClose`, `jsDialog`; `dialogMode json` and `dialogEvent` answered with `jsonDialogsUnavailable` | `WINDOW` callbacks, `paintWindow(DPI)`, `postWindow*Event`, `postWindow` (close) |
| Save | `save` → `saved` | `saveAs` to the temporary target in the file's own format with `TakeOwnership` (so the modified flag clears); a document opened with a password is saved with `.uno:SaveAs` and its password, because `saveAs` drops the encryption |
| Liveness, end | `ping` → `pong`, `close` → `closed` | `destroy`; the end of stdin closes the same way |

Every refused or failed request is an `error` message with the request's
`id`. A document is reported `readOnly` in `opened` when the open asked for
it, a lock file of another LibreOffice is beside it (`lockedBy` names its
owner), the password to modify was not given, or LibreOffice reports
`.uno:EditDoc=false`.

## Components

| Component | File | What it does |
| --- | --- | --- |
| Command line | `bin/tom_office_host.dart`, `lib/src/cli.dart` | the options on `tom_build_base`; runs the host on stdin/stdout and exits explicitly (the callback listener keeps the process alive) |
| Host | `lib/src/host.dart` | `OfficeHost`: the frame loop and the dispatch of every protocol message, against the `LokRuntime` interface |
| LibreOfficeKit interface | `lib/src/lok/lok_api.dart` | `LokRuntime`, `LokOffice`, `LokDocument`, the callback names; the tests' fake implements them |
| FFI | `lib/src/lok/ffi_lok.dart`, `trampoline.dart`, `lok_bindings.g.dart` | the implementation over the FFIgen bindings, with the `nSize` check before optional calls |
| C trampoline | `src/lok_trampoline.c`, built by `hook/build.dart` | `lok_init_2` exported, the callback that copies each payload before Dart reads it, the password answer |
| First spike | `tool/spike/` | spike code, kept until todo later24 removes it |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_office_host/tom_office_host.dart` | `OfficeHost`, the `Lok*` interfaces, `FfiLokRuntime`, `runOfficeHost` | macOS (the helper runs where LibreOffice runs; `dart:io`, `dart:ffi`) |

## Tests

- `test/host_test.dart` — the frame loop and dispatch against a fake
  LibreOfficeKit (`test/fake_lok.dart`).
- `test/integration_test.dart` — tagged `libreoffice`: `dart run
  bin/tom_office_host.dart` against the installed LibreOffice, opening a DOCX
  (tile, typing, save), a dialog window (Format Cells in `sheet.xlsx`) and a
  password-protected DOCX. It skips itself where LibreOffice or the tom_forge
  sample set is missing; `-x libreoffice` leaves it out.

The binaries layer holds the built helper as
`tom_binaries/tom/darwin-arm64/tom_office_host` with
`libtom_office_host_lok.dylib` beside it (`buildkit :compiler`).

Building into the binaries layer, regenerating the bindings and taking in new
headers:
`_agent_guidelines/build.md` in this package.
