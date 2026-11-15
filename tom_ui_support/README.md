# tom_ui_support

Small Flutter building blocks every Tom application uses: colours kept
readable against their background (WCAG AA), the editing-surface marker that
tells a host which text field its clipboard and text commands act on, the
notice queue, and running a change after the frame being built.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Readable colours | `lib/src/colour/` | A hue kept and its lightness moved until it meets WCAG AA on its background (`tomReadableOn`), a tinted chip's three colours from one hue (`tomTintedChip`), and the ratio both use (`tomContrastRatio`). |
| Editing surface | `lib/src/editing/` | Marking the text field a host's clipboard and text commands act on (`TomEditingSurface`, of a `TomEditingSurfaceKind` — rich text, a cell editor, a secret — with the `TomEditingCommand`s it performs), and finding the one that has the keyboard focus (`tomFocusedEditingSurface`, `tomPerformFocusedTextCommand`), so a host offers cut, copy and paste only where they apply. |
| Notices | `lib/src/notices/` | The one way a surface shows a notice (`tomShowNotice`): it times out even with an action, after a duration that fits its text (`tomNoticeDuration`), and it has a **kind** — a notice replaces an earlier one of its kind whether on screen or waiting, while notices of other kinds still follow one another. |
| Frame | `lib/src/after_build.dart` | Running a change after the frame being built, when a notifier fires mid-build (`tomRunAfterBuild`). |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_ui_support/tom_ui_support.dart` | everything above | all |

## Dependencies

Flutter.

## Tests

`flutter test` from this folder.
