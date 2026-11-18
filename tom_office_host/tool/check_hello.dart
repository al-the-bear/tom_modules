// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// Checks a built helper: starts it, expects `hello` of this protocol, sends
/// `close`, expects `closed` and exit code 0. With `--beside`, also checks
/// that it loaded its trampoline from beside the executable (the flattened
/// layout of the binaries layer).
///
/// ```sh
/// dart run tool/check_hello.dart <helper> [--program <Frameworks>] [--beside]
/// ```
///
/// Exit 0 when the helper passes, 1 otherwise. Used by the `buildkit.yaml`
/// pipeline after the copy into `$TOM_BINARY_PATH`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tom_office_protocol/tom_office_protocol.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: check_hello <helper> [--program <Frameworks>] [--beside]',
    );
    exit(2);
  }
  final helper = File(args.first).absolute.path;
  final i = args.indexOf('--program');
  final program = i >= 0 && i + 1 < args.length
      ? args[i + 1]
      : '/Applications/LibreOffice.app/Contents/Frameworks';
  final beside = args.contains('--beside');

  final profile = Directory.systemTemp.createTempSync('office-host-check-');
  final process = await Process.start(helper, [
    '--program',
    program,
    '--profile',
    profile.uri.toString(),
    '--protocol',
    '$kOfficeProtocolVersion',
  ]);
  final log = <String>[];
  final logDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(log.add);
  const codec = OfficeProtocolCodec();
  final reader = OfficeFrameReader(codec);
  final messages = StreamController<OfficeMessage>();
  process.stdout.listen(
    (chunk) => reader.add(chunk).forEach(messages.add),
    onDone: messages.close,
  );
  final incoming = StreamIterator(messages.stream);

  String? failure;
  try {
    if (!await incoming.moveNext().timeout(const Duration(seconds: 60))) {
      failure = 'no message before the helper ended';
    } else if (incoming.current case final OfficeHello hello) {
      OfficeProtocolCodec.checkHello(hello);
      stdout.writeln(
        'hello: protocol ${hello.protocol}, helper ${hello.helperVersion}, '
        'pid ${hello.pid}',
      );
      process.stdin.add(codec.encode(const OfficeClose()));
      await process.stdin.flush();
      var closed = false;
      while (await incoming.moveNext().timeout(const Duration(seconds: 30))) {
        if (incoming.current is OfficeClosed) closed = true;
      }
      if (!closed) failure = 'no closed after close';
    } else {
      failure = 'the first message is ${incoming.current}, not hello';
    }
  } on TimeoutException {
    failure = 'timed out';
  } on Object catch (e) {
    failure = '$e';
  }
  if (failure != null) process.kill(ProcessSignal.sigkill);
  final code = await process.exitCode;
  await logDone;
  if (failure == null && code != 0) failure = 'exit code $code';
  final source = log.firstWhere(
    (l) => l.contains('trampoline: '),
    orElse: () => '',
  );
  if (failure == null &&
      beside &&
      !source.contains(
        File(
          helper,
        ).resolveSymbolicLinksSync().replaceFirst(RegExp(r'/[^/]+$'), ''),
      )) {
    failure =
        'the trampoline was not loaded from beside the executable: '
        '${source.isEmpty ? 'not reported' : source}';
  }
  if (profile.existsSync()) profile.deleteSync(recursive: true);
  if (failure != null) {
    stderr.writeln('check_hello: FAILED: $failure');
    stderr.writeln(log.join('\n'));
    exit(1);
  }
  stdout.writeln('check_hello: ok ($source)');
}
