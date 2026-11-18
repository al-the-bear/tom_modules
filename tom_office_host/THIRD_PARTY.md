# Third-party components

| Component | Where | Licence | How it is used |
| --- | --- | --- | --- |
| LibreOfficeKit headers (LibreOffice `libreoffice-26.8.3.1`) | [`third_party/libreofficekit/`](third_party/libreofficekit/SOURCE.md) | MPL-2.0 ([text](third_party/libreofficekit/LICENSE); the notice is in each file) | unmodified; compiled into the C trampoline and read by FFIgen into `lib/src/lok/lok_bindings.g.dart` |
| LibreOffice | the user's installation, found at runtime (`--program`) | MPL-2.0 | loaded at runtime by `lok_init_2`; nothing of it is linked or shipped |

The Dart packages the helper depends on are listed with their licences by
`dart pub deps`; all are permissive (BSD-3-Clause, MIT, Apache-2.0).
