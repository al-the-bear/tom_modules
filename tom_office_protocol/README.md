# tom_office_protocol

Protocol 1 between the office editor (`tom_office_editor`) and its
LibreOfficeKit helper process (`tom_office_host`): the message types, the
frame codec of the stdio transport, and the protocol number. Pure Dart — no
Flutter and no `dart:io` — so the Flutter editor and the command-line helper
compile against one definition.

License: BSD-3-Clause (see [LICENSE](LICENSE)). Not published
(`publish_to: none`); taken by path inside the workspace.

## Components

| Component | File | What it does |
| --- | --- | --- |
| Messages | `lib/src/messages.dart` | One sealed class per message of the protocol table, prefixed `Office` (`OfficeHello`, `OfficeOpen`, `OfficeRenderTile`, `OfficeTile`, `OfficeKey`, `OfficeUno`, `OfficeSave`, `OfficeWindowOpened`, `OfficeError`, …), plus the clipboard messages `OfficeCopy`, `OfficeClipboard` and `OfficePaste`. Forge's messages extend `OfficeHelperCommand`, the helper's `OfficeHelperEvent`, so a `switch` over either side is exhaustive. A request with a reply implements `OfficeRequest` (`id`). Messages are values: equal when type, fields and pixel bytes are. JSON-valued fields (`lokVersion`, `args`, `json`) are the JSON text LibreOfficeKit takes or gives, passed through unparsed. `OfficeMessageType` names each type with its frame byte and direction. |
| Codec | `lib/src/codec.dart` | `OfficeProtocolCodec` encodes a message to a frame and decodes one back; `OfficeFrameReader` collects bytes from a pipe and gives the whole frames among them, however they were split; `decodeStream` does it for a stream; `checkHello` refuses a helper of another protocol number (`OfficeProtocolVersionMismatch`). |
| Errors | `lib/src/errors.dart` | `OfficeProtocolException` with its code: an unknown type, a malformed header or pixel count, a bad length, a stream ended inside a frame. |

### The frame

| Bytes | Holds |
| --- | --- |
| 4 | the length of everything after these 4 bytes, big-endian |
| 1 | the message type (`OfficeMessageType.code`) |
| n | the JSON header (UTF-8) — one line, since JSON text never holds a raw line break |
| 1 | `0x0A`, ending the header |
| rest | the pixels of `tile` (`pxW × pxH × 4`) and `windowPixels` (`w × h × 4`); nothing for other messages |

Fields are only added within protocol 1, never repurposed; a decoder ignores
fields it does not know, and a new message type takes a new code.

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_office_protocol/tom_office_protocol.dart` | everything above | all (no `dart:io`, no Flutter) |

## Dependencies

`meta`.

## Usage

```dart
import 'package:tom_office_protocol/tom_office_protocol.dart';

const codec = OfficeProtocolCodec();
final reader = OfficeFrameReader(codec);

// Forge: write a command to the helper's stdin.
helper.stdin.add(codec.encode(const OfficeOpen(path: '/docs/report.docx', language: 'en-US')));

// Forge: read the helper's stdout.
helper.stdout.listen((chunk) {
  for (final message in reader.add(chunk)) {
    switch (message as OfficeHelperEvent) {
      case final OfficeHello hello:
        OfficeProtocolCodec.checkHello(hello); // throws on another protocol
      case final OfficeTile tile:
        paint(tile.pixels, tile.pxW, tile.pxH);
      default:
        break;
    }
  }
});
```
