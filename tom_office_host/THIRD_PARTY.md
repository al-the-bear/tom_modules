# Third-party components

| Component | Where | Licence | How it is used |
| --- | --- | --- | --- |
| LibreOfficeKit headers (LibreOffice `libreoffice-26.8.3.1`) | [`third_party/libreofficekit/`](third_party/libreofficekit/SOURCE.md) | MPL-2.0 ([text](third_party/libreofficekit/LICENSE); the notice is in each file) | unmodified; compiled into the C trampoline and read by FFIgen into `lib/src/lok/lok_bindings.g.dart` |
| FFIgen bindings of those headers (generated, committed) | [`lib/src/lok/lok_bindings.g.dart`](lib/src/lok/lok_bindings.g.dart), and the spike's copy `tool/spike/lok_bindings.g.dart` | MPL-2.0 (the notice and `SPDX-License-Identifier: MPL-2.0` in each file's header, written by `tool/ffigen.yaml`'s preamble): they copy the headers' doc comments | their own files, so every other file of the package stays BSD-3; their source is the files themselves and the headers above |
| LibreOffice | the user's installation, found at runtime (`--program`) | MPL-2.0 | loaded at runtime by `lok_init_2`; nothing of it is linked or shipped |

The compiled helper (`tom_office_host`, `libtom_office_host_lok.dylib` in the
binaries layer) is BSD-3 with MPL-2.0 code inside it: the trampoline compiles
the headers' `static inline lok_init_2`. The Source Code Form of that MPL
code is `third_party/libreofficekit/` here, and LibreOffice's release named
in its `SOURCE.md` (MPL-2.0 §3.2(a)).

The Dart packages the helper depends on are listed with their licences by
`dart pub deps`; all are permissive (BSD-3-Clause, MIT, Apache-2.0).
