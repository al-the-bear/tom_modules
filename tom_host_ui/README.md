# tom_host_ui

Host capabilities of a Flutter application on desktop and in the browser: copy
with formatting (HTML and plain text placed together), the protected-value
clipboard binding that clears a copied secret, and printing a self-contained
HTML document through the platform's own print dialog.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Clipboard | `lib/src/clipboard/` | Copy with formatting — HTML and plain text placed together, in one act (`TomRichClipboard`, `tomPlaceOnBrowserClipboard`); protected-value bindings for `tom_basics`' `TomProtectedClipboard` (`TomFlutterClipboardPort`, `TomDesktopClipboardPort`). |
| Print | `lib/src/print/` | Printing one self-contained HTML document through the platform's own print dialog, which also saves a PDF (`tomPrintHtmlWithPlatform`, `tomPrintHtmlInBrowser`). |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_host_ui/tom_host_ui.dart` | `TomClipboardPlacement`, `TomPlaceOnClipboard`, `TomPrintHtml`, `TomFlutterClipboardPort` | all (no `dart:io`, no `package:web`) |
| `package:tom_host_ui/desktop.dart` | the above, plus `TomRichClipboard`, `TomDesktopClipboardPort`, `tomPrintHtmlWithPlatform`, and the pure builders `tomCfHtml`, `tomWindowsText`, `tomAppleScriptClipboardProgram` | macOS, Linux, Windows |
| `package:tom_host_ui/web.dart` | the portable part, plus `tomPlaceOnBrowserClipboard`, `tomPrintHtmlInBrowser` | browser (a VM test gets stubs answering "could not") |

## Dependencies

Flutter, `tom_basics`, `web`.

## Usage

```dart
import 'package:flutter/services.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_host_ui/desktop.dart';

const channel = MethodChannel('my_app/clipboard');

// Copy with formatting: both flavours, and an honest answer.
final placed = await const TomRichClipboard(channel: channel)
    .place(html: '<p><b>Hello</b></p>', text: 'Hello');
if (placed == TomClipboardPlacement.plainTextOnly) {
  // Say so: the paste will have no formatting.
}

// A password copy that clears itself after 30 s.
final protected = TomProtectedClipboard(
  port: const TomDesktopClipboardPort(channel: channel),
);
await protected.copy('hunter2');

// Print (or save as PDF) through the platform's dialog.
await tomPrintHtmlWithPlatform('Report', '<html>…</html>');
```

## What a host application provides

The Dart halves run everywhere; three things need native code in the host
application's runner, answering one `MethodChannel` the host names and passes
in:

| Platform | Method | Arguments → answer | Used by |
| --- | --- | --- | --- |
| Linux (GTK) | `place` | `html` (UTF-8 bytes), `text` → `bool` | `TomRichClipboard` |
| Windows (Win32) | `place` | `html` (a CF_HTML payload from `tomCfHtml`), `text` (CRLF) → `bool` | `TomRichClipboard` |
| macOS | `placeConcealed` | `text` → the pasteboard's new `changeCount` | `TomDesktopClipboardPort` |
| macOS | `clearIfUnchanged` | `changeCount` → `bool` | `TomDesktopClipboardPort` |

macOS copy-with-formatting needs no runner code: one `osascript` statement
sets both flavours. A runner that does not answer the channel is not an error:
copy-with-formatting reports `plainTextOnly`, and the protected-value binding
falls back to Flutter's clipboard with a text comparison.

The Webwork application's runners are a complete example: `tom_webwork_app`'s
`linux/runner/webwork_clipboard_gtk.cc`, `windows/runner/webwork_clipboard_win32.cpp`
and `macos/Runner/MainFlutterWindow.swift`, on the channel
`tom_webwork_app/clipboard`; `tom_webwork_app/tool/clipboard_check/run.sh`
exercises the Linux and Windows halves in containers.

## Tests

`flutter test` from this folder. `test/browser/` holds `@TestOn('browser')` files that `test/browser_suite_test.dart` runs on Chrome (`tom_test_support`'s `TomBrowserSuite`; `TOM_SKIP_BROWSER_TESTS=1` turns it off on a machine without Chrome).
