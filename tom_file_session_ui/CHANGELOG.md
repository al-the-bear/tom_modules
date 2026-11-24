# Changelog

## 0.1.1

- A save of a CRLF file no longer doubles the CR when the editor's text already
  holds CRLF (an editor whose `textOf` hands back the session's own text, as
  Tom Forge's `.env` editor does): the text is normalised to LF before CRLF is
  written (test FSF-4b).
- Published on pub.dev.

## 0.1.0

- `ForgeSessionFile` and `ForgeSessionFileFrame`, moved here from
  `tom_file_editors` (which re-exports them) so that packages that must not
  take `tom_file_editors`' dependencies (Tom Forge's kit and its Markdown and
  YAML adapters) use the same implementation instead of a copy.
- Published on pub.dev; `tom_file_editors` takes it as a version from its
  staged copy.
