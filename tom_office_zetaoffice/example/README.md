# ZetaOffice example

ZetaOffice (`tom_office_zetaoffice`) in a macOS window. It opens a sample
DOCX, XLSX or PPTX (copied into a scratch folder first) or the file named in
`TOM_OFFICE_FILE` in `TomZetaOfficeView`; the first open asks before it
downloads ZetaOffice (52.5 MB) into the cache. Cmd+S saves, Cmd+Z /
Shift+Cmd+Z undo and redo, the refresh button reopens the file.

```sh
flutter run -d macos
flutter test integration_test/zetaoffice_test.dart -d macos
```

`TOM_OFFICE_SAMPLES` names the sample set's `files/` folder; by default it is
the tom_forge quest's `office_and_pdf_integration_prototype/samples/files`.
The app is not sandboxed: it opens documents anywhere and serves ZetaOffice
from the user's cache folder to the webview.
