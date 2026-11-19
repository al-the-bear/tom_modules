# Office editor example

The office editor (`tom_office_editor`) in a macOS window. It opens a sample
DOCX, XLSX or PPTX (copied into a scratch folder first) or the file named in
`TOM_OFFICE_FILE`, with the installed LibreOffice and the helper
`tom_office_host` from the binaries layer (`$TOM_BINARY_PATH`). Cmd+S saves,
Cmd+Z / Shift+Cmd+Z undo and redo, the refresh button reopens the file.

```sh
flutter run -d macos
flutter test integration_test/samples_test.dart -d macos
```

`TOM_OFFICE_SAMPLES` names the sample set's `files/` folder; by default it is
the tom_forge quest's `office_and_pdf_integration_prototype/samples/files`.
The app is not sandboxed (it starts the helper from the binaries layer).
