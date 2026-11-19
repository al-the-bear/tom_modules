## 0.3.1

- A PDF export (`saveAs` to `pdf`) no longer passes `TakeOwnership`:
  LibreOffice refused the export with 0x81a, and an export must not make
  the PDF the document's file anyway. Other `saveAs` calls still take
  ownership.

## 0.3.0

- `WINDOW` callbacks carry what the editor needs to show a dialog: a child
  window's `position` (`windowOpened.x` / `y`), the size of `size_changed`,
  the title of `title_changed`, the cursor's visibility (protocol 0.4.0).

## 0.2.0

- `open` takes `filterOptions` (protocol package 0.3.0): the load options
  are `Language=<tag>`, which LibreOfficeKit reads (the JSON form before was
  handed to the import filter instead), with the filter options and
  `Batch=true` in front when given, so a CSV file opens with its separator
  and encoding and without the Text Import dialog, which blocked the load.

## 0.1.0

- The LibreOfficeKit helper: one document per process, protocol 1
  (`tom_office_protocol`) on stdin and stdout, the log on stderr.
  - Open, with the password flow (`passwordNeeded` / `password`, answered by
    the C trampoline during the load; a wrong password asks again), and a
    read-only open reported in `opened` (a lock file, a password to modify not
    given, `.uno:EditDoc` false).
  - Tiles (`paintPartTile`), queued requests for one area coalesced; keys,
    text input, mouse, selection, copy and paste; `uno` commands posted from a
    second isolate, so a modal dialog never blocks the loop; command values,
    view and part.
  - Callbacks forwarded; `WINDOW` as `windowOpened` / `windowChanged`,
    `paintWindow` and the window input; `JSDIALOG` as `jsDialog`;
    `dialogMode json` and `dialogEvent` refused (this LibreOffice has no JSON
    dialogs).
  - Saving to the temporary target only: `saveAs` with `TakeOwnership` in
    the file's own format, or `.uno:SaveAs` with the password for a document
    opened with one, so it stays encrypted.
  - `ping` / `pong`, `close` / `closed`; the end of stdin closes the same
    way; the private profile is deleted on a clean close.
- The command line on `tom_build_base`: `--program`, `--profile`,
  `--protocol`, `--version`, `--help`.
- `buildkit.yaml`: `buildkit :compiler` builds the helper into the
  binaries layer, flattened (the trampoline beside the executable, which the
  helper loads from there before the code-asset mapping), re-signed, and
  checked to answer `hello` (`tool/check_hello.dart`); the version comes from
  `buildkit :versioner`.
- The first spike stays in `tool/spike/` (todo later24 removes it).
