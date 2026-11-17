# LibreOfficeKit headers

`LibreOfficeKit.h`, `LibreOfficeKitEnums.h`, `LibreOfficeKitInit.h` and
`LibreOfficeKitTypes.h`, unchanged, from `include/LibreOfficeKit/` of
LibreOffice's core source.

| | |
| --- | --- |
| Release tag | `libreoffice-26.8.3.1` (the version installed on mbp, `getVersionInfo` BuildId `861effc5289d539f15c4c18d1ba8579ffd78728b`) |
| Commit | `861effc5289d539f15c4c18d1ba8579ffd78728b` |
| Fetched from | `https://raw.githubusercontent.com/LibreOffice/core/libreoffice-26.8.3.1/include/LibreOfficeKit/` (LibreOffice's official mirror of git.libreoffice.org/core; the gitiles front end of git.libreoffice.org does not serve raw files) |
| Fetched | 2026-11-17 |
| Not from | the workspace's `tom_libreoffice_core` fork |

## Licence

Mozilla Public License 2.0 (each file carries the notice):

> This Source Code Form is subject to the terms of the Mozilla Public
> License, v. 2.0. If a copy of the MPL was not distributed with this
> file, You can obtain one at http://mozilla.org/MPL/2.0/.

The files are used unmodified; nothing of LibreOffice is linked into this
package. LibreOffice is loaded at runtime from its installation.

## Notes

- `LibreOfficeKitEnums.h` has C++-only inline helpers under
  `LOK_USE_UNSTABLE_API`; C code that includes it fails to compile, so the
  spike's trampoline uses the two callback numbers it needs directly.
- These headers declare neither `LOK_CALLBACK_JSDIALOG` (46) nor
  `sendDialogEvent`.
- The VCL key codes (`KEY_RETURN` = 1280, …) for `postKeyEvent` are not in
  these headers (they are `vcl/keycodes.hxx` / `com.sun.star.awt.Key`).
