## 0.3.0

- `open` gains `filterOptions`, the import filter's options (a CSV file's
  separator, quote, encoding and first line); a header without it reads as
  empty.

## 0.2.0

- `opened` gains `readOnly` (a header without it reads as false) and
  `lockedBy` (who holds the lock file that made the document read-only).

## 0.1.0

- Protocol 1 between the office editor and `tom_office_host`: a sealed
  message class for every row of the protocol table (start, open, password,
  tiles, input, selection, UNO commands and their values, view, parts,
  callbacks, saving, dialogs as windows and as JSON, ping, shutdown, errors)
  and the clipboard messages `copy`, `clipboard` and `paste`.
- `OfficeProtocolCodec`: frames of a 4-byte big-endian length, a 1-byte type,
  a one-line JSON header ended by a line feed, and the raw pixel bytes of
  `tile` and `windowPixels`; `OfficeFrameReader` for frames split across
  reads; `checkHello` for the protocol number.
- `kOfficeProtocolVersion = 1`.
