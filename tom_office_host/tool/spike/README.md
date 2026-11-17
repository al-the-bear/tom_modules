# LibreOfficeKit spike (spike code)

**This is spike code, not the helper.** It is the first spike of
`tom_office_host`, the LibreOfficeKit helper process of the office/PDF
prototype (tom_forge quest, idea `office_and_pdf_integration_prototype`,
working document section `part-lok-helper`, *What the first spike must
prove*). Todo `officeproto8` reuses what held up here when it writes the
helper; todo `later24` removes this folder. Nothing outside it imports it.

The results, with the logs and images every command wrote, are in
`_ai/quests/tom_forge/ideas/office_and_pdf_integration_prototype/spikes/lok_spike.md`.

## What is here

| File | What it is |
| --- | --- |
| `lok_spike.dart` | the command-line program: one command per item of the spike |
| `lok.dart` | a thin wrapper over the bindings (`Office`, `Document`), the callback listener, PNG writing |
| `lok_trampoline.dart` | the `@Native` declarations of the C trampoline |
| `native/lok_trampoline.c` | the trampoline: `lok_init_2` exported (the header's is static inline), the callback that copies each payload (`strdup`) before handing it to Dart, a preset password answer |
| `lok_bindings.g.dart` | FFIgen bindings over `third_party/libreofficekit/` (generated, committed) |
| `ffigen.yaml` | the FFIgen configuration |

The package's build hook (`hook/build.dart`) compiles the trampoline with
`native_toolchain_c`.

## Building and running

Run by hand, on macOS arm64, with LibreOffice in `/Applications`:

```sh
dart run ffigen --config tool/spike/ffigen.yaml   # only when the headers change
dart build cli -t tool/spike/lok_spike.dart
B=build/cli/macos_arm64/bundle/bin/lok_spike
I=../../../_ai/quests/tom_forge/ideas/office_and_pdf_integration_prototype
$B tiles --samples $I/samples/files --out $I/spikes/lok_spike
```

`dart build cli` (not `dart compile exe`) is needed: it bundles the
trampoline's dylib beside the executable. Options: `--program` (default
`/Applications/LibreOffice.app/Contents/Frameworks`), `--samples` (the
sample set's `files/`), `--out` (where logs' images go), `--profile` (reuse
a profile URL).

| Command | Item |
| --- | --- |
| `init` | 1: `lok_init_2` with a private profile, version info |
| `tiles` | 2: DOCX, XLSX, PPTX tiles, the tile mode and a colour probe |
| `type` | 3 and 4: typing, callbacks under load, key-to-tile latency |
| `probe` | which callbacks follow input (`--doc`, `--how key\|uno`) |
| `save` | 5: `saveAs`, `.uno:ModifiedStatus`, reopening |
| `password` | protected files and `saveAs` |
| `helpers`, `child` | 6: two helpers with two profiles |
| `kill`, `parent-sim` | 7: `kill -9` of a helper and of its parent |
| `dialog` | 8: a dialog as a `WINDOW` (`--cmd`, `--steps "click:x,y;key:tab;text:abc"`) |
| `ribbon` | 9: the ribbon's commands (`--doc`, `--skip`) |

Every edit works on copies in a temporary folder; profiles go to
`$TMPDIR/office-host-spike/<pid>-<n>/profile`.
