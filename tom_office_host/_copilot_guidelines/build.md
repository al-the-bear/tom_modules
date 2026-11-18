# Building tom_office_host

## The executable

```sh
dart build cli -t bin/tom_office_host.dart
```

The bundle is `build/cli/<os>_<arch>/bundle/`: `bin/tom_office_host` and, in
`lib/`, the trampoline's dylib. `dart build cli` (not `dart compile exe`) is
needed because only it runs the build hook and bundles the native asset. The
office editor runs the bundle from the binaries layer.

Run from source, as the integration test does:

```sh
dart run bin/tom_office_host.dart --program /Applications/LibreOffice.app/Contents/Frameworks \
    --profile file:///tmp/office-host/manual/profile --protocol 1
```

`dart run` runs the build hook too; its "Running build hooks..." goes to
stderr, so stdout stays protocol frames only.

## The C part

`hook/build.dart` compiles `src/lok_trampoline.c` with `native_toolchain_c`
(as `tom_ai/basics/tom_pqc` does for its vendored C), against the headers in
`third_party/libreofficekit/`, into the code asset
`package:tom_office_host/lok_trampoline.dart`. It also builds the first
spike's trampoline (`tool/spike/native/`, asset `spike/lok_trampoline.dart`)
until todo later24 removes the spike.

The trampoline:

- exports `lok_init_2` (static inline in the header) as `tom_lok_init_2`;
- copies every callback payload (`strdup`) before LibreOfficeKit frees it, and
  hands the copy to the Dart `NativeCallable.listener`, which frees it;
- answers `DOCUMENT_PASSWORD(_TO_MODIFY)` from LibreOffice's thread with the
  answer armed before the load (`tom_lok_set_password_answer`), once per
  arming, and records what was asked (`tom_lok_password_asked`). Calling
  `setDocumentPassword` before the load crashes LibreOffice 26.8.3.1.

## The bindings

```sh
dart run ffigen --config tool/ffigen.yaml
```

It writes `lib/src/lok/lok_bindings.g.dart` (committed, excluded from
analysis): the structs, function-pointer typedefs and enums of the headers.
The headers export no functions; every call goes through the classes'
function pointers. FFIgen needs libclang (the Command Line Tools' one is
found on macOS).

## Taking in new LibreOfficeKit headers

1. Fetch `LibreOfficeKit.h`, `LibreOfficeKitEnums.h`, `LibreOfficeKitInit.h`
   and `LibreOfficeKitTypes.h` unchanged from `include/LibreOfficeKit/` of the
   release tag (`libreoffice-<version>`) into `third_party/libreofficekit/`.
2. Update `SOURCE.md` there: the tag, the commit, the date.
3. Regenerate the bindings (above).
4. Run the tests: `LOK-SLOTS-1` checks the function slots the helper checks
   against `nSize` (`LokDocumentSlot`), and `LOK-NAMES-1` the callback names
   (`LokCallbackType.names`) against the new headers; fix the tables where
   they fail.
5. Run the integration test against a LibreOffice of that version.

## Tests

```sh
testkit :test                         # all, the LibreOffice ones included
dart test -x libreoffice              # without LibreOffice
```

The integration test (`test/integration_test.dart`, tag `libreoffice`) needs
LibreOffice (`TOM_LIBREOFFICE_PROGRAM`, default the macOS application) and the
tom_forge sample set (`TOM_OFFICE_SAMPLES`, default the quest's
`samples/files`); without them it skips. Each helper it starts loads
LibreOffice (about 1.5–3 GB of memory with a document), so it needs free
memory: on a machine short of it, process starts stall.
