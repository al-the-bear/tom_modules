// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_file_session/io.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import '../detection/installation.dart';
import '../helper/helper_channel.dart';
import '../office_editor_trail.dart';

/// Starts `tom_office_host` processes: one per document, each with a
/// private LibreOffice profile under [workRoot]
/// (`<workRoot>/<our pid>-<n>/profile`), speaking protocol 1 over its stdin
/// and stdout.
class TomOfficeProcessLauncher implements TomOfficeHelperLauncher {
  /// A launcher of [helperExecutable] for [installation]. [workRoot]
  /// defaults to `<system temp>/office-host`.
  TomOfficeProcessLauncher({
    required this.installation,
    required this.helperExecutable,
    String? workRoot,
    this.closeTimeout = const Duration(seconds: 5),
    this.termTimeout = const Duration(seconds: 2),
  }) : workRoot = workRoot ?? p.join(Directory.systemTemp.path, 'office-host');

  @override
  final LibreOfficeInstallation installation;

  /// The helper (`tom_office_host`).
  final String helperExecutable;

  /// Where the helpers' profiles live.
  final String workRoot;

  /// How long `close` waits before SIGTERM.
  final Duration closeTimeout;

  /// How long SIGTERM waits before SIGKILL.
  final Duration termTimeout;

  int _count = 0;

  /// The helper in the binaries layer: `<binaries>/<platform>/tom_office_host`,
  /// [binaryPath] defaulting to `$TOM_BINARY_PATH`; `null` when it is not
  /// there.
  static String? findHelper({String? binaryPath}) {
    final root = binaryPath ?? Platform.environment['TOM_BINARY_PATH'];
    if (root == null || root.isEmpty) return null;
    final arch = _arch();
    final os = Platform.isMacOS
        ? 'darwin'
        : Platform.isLinux
        ? 'linux'
        : Platform.isWindows
        ? 'windows'
        : Platform.operatingSystem;
    final name = Platform.isWindows ? 'tom_office_host.exe' : 'tom_office_host';
    final file = File(p.join(root, '$os-$arch', name));
    return file.existsSync() ? file.path : null;
  }

  static String _arch() {
    final v = Platform.version;
    if (v.contains('arm64')) return 'arm64';
    if (v.contains('x64')) return 'x64';
    return 'x64';
  }

  @override
  Future<TomOfficeHelperChannel> start({required String documentPath}) async {
    final program = installation.programPath;
    if (!installation.isUsable || program == null) {
      throw StateError('LibreOffice is not usable: $installation');
    }
    final folder = Directory(p.join(workRoot, '$pid-${_count++}'));
    final profile = Directory(p.join(folder.path, 'profile'))
      ..createSync(recursive: true);
    final process = await Process.start(helperExecutable, [
      '--program',
      program,
      '--profile',
      profile.uri.toString(),
      '--protocol',
      '$kOfficeProtocolVersion',
    ]);
    File(p.join(folder.path, 'owner.json')).writeAsStringSync(
      jsonEncode({
        'helperPid': process.pid,
        'editorPid': pid,
        'document': documentPath,
        'profile': profile.path,
      }),
    );
    officeTrail('helper started: pid ${process.pid}');
    return _ProcessChannel(
      process,
      closeTimeout: closeTimeout,
      termTimeout: termTimeout,
    );
  }

  /// Removes what dead helpers left (the office editors' module start):
  /// their profile folders, the `.~lock.<name>#` file beside a document a
  /// killed helper held (when it names that helper's profile), and the
  /// temporary files of a save the crash interrupted. Returns the paths
  /// removed.
  static Future<List<String>> cleanUp({String? workRoot}) async {
    final root = Directory(
      workRoot ?? p.join(Directory.systemTemp.path, 'office-host'),
    );
    if (!root.existsSync()) return const [];
    final removed = <String>[];
    for (final entry in root.listSync()) {
      if (entry is! Directory) continue;
      final owner = File(p.join(entry.path, 'owner.json'));
      Map<String, Object?> data = const {};
      if (owner.existsSync()) {
        try {
          data = (jsonDecode(owner.readAsStringSync()) as Map)
              .cast<String, Object?>();
        } on FormatException {
          data = const {};
        }
      }
      final helperPid = data['helperPid'];
      if (helperPid is int && _alive(helperPid)) continue;
      final document = data['document'];
      if (document is String) {
        final lock = File(
          p.join(p.dirname(document), '.~lock.${p.basename(document)}#'),
        );
        if (lock.existsSync()) {
          final text = lock.readAsStringSync();
          final profile = '${data['profile'] ?? ''}';
          if (profile.isNotEmpty &&
              (text.contains(profile) ||
                  text.contains(Uri.directory(profile).toString()))) {
            lock.deleteSync();
            removed.add(lock.path);
          }
        }
        if (File(document).existsSync()) {
          removed.addAll(
            await TomBinaryFileAccess().removeTemporaryFiles(document),
          );
        }
      }
      try {
        entry.deleteSync(recursive: true);
        removed.add(entry.path);
      } on FileSystemException {
        continue;
      }
    }
    return removed;
  }

  static bool _alive(int pid) {
    if (Platform.isWindows) return false;
    return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
  }
}

class _ProcessChannel implements TomOfficeHelperChannel {
  _ProcessChannel(
    this._process, {
    required this.closeTimeout,
    required this.termTimeout,
  }) {
    _events = const OfficeProtocolCodec()
        .decodeStream(_process.stdout)
        .where((m) => m is OfficeHelperEvent)
        .cast<OfficeHelperEvent>()
        .asBroadcastStream();
    _log = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          _tail.add(line);
          if (_tail.length > 20) _tail.removeAt(0);
          return line;
        })
        .asBroadcastStream();
    // Keep stderr drained when nobody listens.
    _log.listen((_) {});
    _exit = _process.exitCode.then(
      (code) => TomOfficeHelperExit(
        code: code,
        reason: code < 0 ? 'signal ${-code}' : 'exit $code',
        stderrTail: _tail.join('\n'),
      ),
    );
  }

  final Process _process;
  final Duration closeTimeout;
  final Duration termTimeout;
  late final Stream<OfficeHelperEvent> _events;
  late final Stream<String> _log;
  late final Future<TomOfficeHelperExit> _exit;
  final _tail = <String>[];
  bool _stdinClosed = false;

  @override
  Stream<OfficeHelperEvent> get events => _events;

  @override
  Stream<String> get log => _log;

  @override
  Future<TomOfficeHelperExit> get exit => _exit;

  @override
  void send(OfficeHelperCommand command) {
    if (_stdinClosed) return;
    _process.stdin.add(const OfficeProtocolCodec().encode(command));
  }

  @override
  Future<TomOfficeHelperExit> close() async {
    try {
      send(const OfficeClose());
      await _process.stdin.flush();
    } catch (_) {
      // Already gone.
    }
    final clean = await _exit.timeout(
      closeTimeout,
      onTimeout: () async {
        _process.kill(ProcessSignal.sigterm);
        return _exit.timeout(
          termTimeout,
          onTimeout: () {
            _process.kill(ProcessSignal.sigkill);
            return _exit;
          },
        );
      },
    );
    await _closeStdin();
    return clean;
  }

  Future<void> _closeStdin() async {
    if (_stdinClosed) return;
    _stdinClosed = true;
    try {
      await _process.stdin.close();
    } catch (_) {
      // The pipe is gone with the process.
    }
  }

  @override
  void kill() => _process.kill(ProcessSignal.sigkill);
}
