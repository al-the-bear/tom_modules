// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Builds the helper's C part (`src/lok_trampoline.c`) and the first spike's
/// (`tool/spike/native/lok_trampoline.c`, until todo later24 removes the
/// spike) against the vendored LibreOfficeKit headers. Nothing of LibreOffice
/// is linked: the trampoline loads it at runtime through `lok_init_2`.
library;

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final logger = Logger.detached('tom_office_host')
      ..level = Level.INFO
      ..onRecord.listen((record) => print(record.message));
    for (final (name, asset, source) in [
      ('tom_office_host_lok', 'lok_trampoline.dart', 'src/lok_trampoline.c'),
      (
        'tom_lok_trampoline',
        'spike/lok_trampoline.dart',
        'tool/spike/native/lok_trampoline.c',
      ),
    ]) {
      await CBuilder.library(
        name: name,
        assetName: asset,
        sources: [source],
        includes: ['third_party/libreofficekit'],
        std: 'c11',
        flags: [if (os != OS.windows) '-fvisibility=hidden'],
      ).run(input: input, output: output, logger: logger);
    }
  });
}
