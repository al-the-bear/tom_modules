// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The LibreOfficeKit helper process of the office editors: [OfficeHost]
/// (protocol 1's frame loop and dispatch over a [LokRuntime]), the FFI
/// implementation of LibreOfficeKit ([FfiLokRuntime]) and the command line
/// ([runOfficeHost]).
library;

export 'src/cli.dart' show runOfficeHost, officeHostTool, kDefaultProgram;
export 'src/host.dart';
export 'src/lok/ffi_lok.dart' show FfiLokRuntime, LokDocumentSlot, lokHasSlot;
export 'src/lok/lok_api.dart';
export 'src/version.dart';
