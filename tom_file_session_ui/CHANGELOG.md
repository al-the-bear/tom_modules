# Changelog

## 0.1.0

- `ForgeSessionFile` and `ForgeSessionFileFrame`, moved here from
  `tom_file_editors` (which re-exports them) so that packages that must not
  take `tom_file_editors`' dependencies (Tom Forge's kit and its Markdown and
  YAML adapters) use the same implementation instead of a copy.
- Published on pub.dev; `tom_file_editors` takes it as a version from its
  staged copy.
