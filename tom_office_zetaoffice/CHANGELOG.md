## 0.1.0

- Initial release: the ZetaOffice route of the office editor, out of
  `tom_office_editor` 0.5.0 unchanged in behaviour.
  `package:tom_office_zetaoffice/tom_office_zetaoffice.dart`:
  `TomZetaOfficeView` and `TomZetaOfficeController` (the download prompt
  with the size, the start's progress, ZetaOffice's full interface, save
  with `store()` and *Save as copy* with `storeToURL` through
  `TomBinaryFiles`, undo, redo and dirty through the office editor's
  `TomOfficeEditorHost`), `TomZetaOfficeCache`, `TomZetaOfficeServer`, the
  files, channel and serving interfaces, the trail `kZetaOfficeDebug`.
- `testing.dart`: `FakeZetaOfficeFiles`, `FakeZetaOfficeServing`,
  `FakeZetaOfficeChannel`.
- `assets/zetaoffice/`: the host page and zetajs's `zeta.js` (MIT).
- `example/`: a macOS app opening the samples in ZetaOffice, with its
  integration test.
