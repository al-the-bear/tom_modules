// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The LibreOfficeKit helper of the office editors. Run with `--help`.
library;

import 'dart:io';

import 'package:tom_office_host/tom_office_host.dart';

Future<void> main(List<String> args) async {
  exitCode = await runOfficeHost(args);
}
