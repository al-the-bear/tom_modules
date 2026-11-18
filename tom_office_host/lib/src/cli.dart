// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The command line, on `tom_build_base`:
/// `tom_office_host --program <Frameworks path> --profile <profile url> --protocol 1`,
/// with `--version` and `--help`.
library;

import 'dart:async';
import 'dart:io';

import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import 'host.dart';
import 'lok/ffi_lok.dart';
import 'version.dart';

/// LibreOffice's program folder on macOS when `--program` is not given.
const kDefaultProgram = '/Applications/LibreOffice.app/Contents/Frameworks';

/// The helper's options.
const officeHostOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'program',
    description:
        'LibreOffice\'s program folder, the one holding libmergedlo '
        '(default $kDefaultProgram)',
    valueName: 'path',
  ),
  OptionDefinition.option(
    name: 'profile',
    description:
        'The helper\'s private LibreOffice profile as a file:// URL; deleted '
        'on a clean close (default: a new folder under the system temp)',
    valueName: 'url',
  ),
  OptionDefinition.option(
    name: 'protocol',
    description:
        'The protocol number the caller speaks; refused unless it is '
        '$kOfficeProtocolVersion',
    valueName: 'n',
  ),
];

/// The `tom_office_host` tool definition.
final officeHostTool = ToolDefinition(
  name: 'tom_office_host',
  description:
      'The LibreOfficeKit helper of the office editors: one document, '
      'protocol $kOfficeProtocolVersion on stdin and stdout',
  version: kOfficeHostVersion,
  versionString:
      'tom_office_host $kOfficeHostVersion '
      '(protocol $kOfficeProtocolVersion)',
  mode: ToolMode.singleCommand,
  features: const NavigationFeatures(
    projectTraversal: false,
    gitTraversal: false,
    recursiveScan: false,
    interactiveMode: false,
    dryRun: false,
    jsonOutput: false,
    verbose: false,
  ),
  globalOptions: officeHostOptions,
  helpFooter:
      '''
Started by the office editor, not by hand. It speaks protocol
$kOfficeProtocolVersion (package tom_office_protocol) as frames on stdin and
stdout; stderr is its log. It holds one document; it exits after `close`, and
at the end of stdin (its parent went away).

Example:
  tom_office_host --program /Applications/LibreOffice.app/Contents/Frameworks \\
      --profile file:///tmp/office-host/1234-0/profile --protocol 1
''',
);

/// Runs the helper as the command's single executor.
class OfficeHostExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.failure(
        path: context.path,
        name: context.name,
        error: 'tom_office_host visits no projects',
      );

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final options = args.extraOptions;
    final protocol = options['protocol'] as String?;
    if (protocol != null && protocol != '$kOfficeProtocolVersion') {
      stderr.writeln(
        'tom_office_host: protocol $protocol asked for, this helper speaks '
        '$kOfficeProtocolVersion',
      );
      return ToolResult.failure('protocol mismatch', exitCode: 2);
    }
    final program = (options['program'] as String?) ?? kDefaultProgram;
    final profileUrl =
        (options['profile'] as String?) ?? _newProfile().uri.toString();
    final runtime = FfiLokRuntime();
    final host = OfficeHost(
      runtime: runtime,
      program: program,
      profileUrl: profileUrl,
      output: stdout.add,
      log: (line) => stderr.writeln('[tom_office_host $pid] $line'),
      pid: pid,
    );
    final code = await host.serve(stdin);
    await stdout.flush();
    runtime.close();
    // The NativeCallable.listener and LibreOffice's threads keep the process
    // alive: leave explicitly.
    exit(code);
  }

  static Directory _newProfile() {
    final base = Directory('${Directory.systemTemp.path}/office-host');
    for (var n = 0; ; n++) {
      final dir = Directory('${base.path}/$pid-$n');
      if (!dir.existsSync()) return dir..createSync(recursive: true);
    }
  }
}

/// Runs the command line: `--help` and `--version` print to stdout; while
/// serving, everything but protocol frames goes to stderr.
Future<int> runOfficeHost(List<String> args) async {
  final informational = args.any(
    (a) => const {
      '--help',
      '-h',
      '--version',
      '-v',
      '-version',
      '-help',
    }.contains(a),
  );
  final runner = ToolRunner(
    tool: officeHostTool,
    executors: {'default': OfficeHostExecutor()},
    output: informational ? stdout : stderr,
    errorOutput: stderr,
  );
  final result = await runner.run(args);
  return result.success ? 0 : (result.exitCode == 0 ? 1 : result.exitCode);
}
