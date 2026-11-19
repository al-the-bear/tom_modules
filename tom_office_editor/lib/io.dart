// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The office editor's `dart:io` side: LibreOffice detection
/// ([TomLibreOfficeDetector]), the process-backed helper launcher
/// ([TomOfficeProcessLauncher]) and the binary save rules over local files
/// (`TomBinaryFileAccess`, from `tom_file_session`).
library;

export 'package:tom_file_session/io.dart' show TomBinaryFileAccess;

export 'src/io/detector.dart';
export 'src/io/process_launcher.dart';
