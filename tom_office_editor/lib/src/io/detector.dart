// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../detection/installation.dart';

/// The result of a short process detection runs.
final class TomDetectionRun {
  /// A result from its parts. [timedOut] when it was stopped.
  const TomDetectionRun(
    this.exitCode,
    this.stdout,
    this.stderr, {
    this.timedOut = false,
  });

  /// The exit code (−1 when it could not be started or was stopped).
  final int exitCode;

  /// Its standard output.
  final String stdout;

  /// Its standard error.
  final String stderr;

  /// Whether it was stopped at the timeout.
  final bool timedOut;

  /// Whether it exited 0.
  bool get ok => exitCode == 0 && !timedOut;

  /// What it printed, both streams.
  String get output =>
      [stdout.trim(), stderr.trim()].where((s) => s.isNotEmpty).join('\n');
}

/// Runs [executable] with [arguments], stopped after [timeout].
typedef TomDetectionRunner =
    Future<TomDetectionRun> Function(
      String executable,
      List<String> arguments, {
      Duration timeout,
    });

/// The default runner: `Process.start`, killed at the timeout.
Future<TomDetectionRun> runDetectionProcess(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException catch (e) {
    return TomDetectionRun(-1, '', e.message);
  }
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  unawaited(process.stdin.close());
  var timedOut = false;
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  return TomDetectionRun(
    code,
    await out.timeout(const Duration(seconds: 2), onTimeout: () => ''),
    await err.timeout(const Duration(seconds: 2), onTimeout: () => ''),
    timedOut: timedOut,
  );
}

/// LibreOffice detection on macOS (`part-libreoffice-detection`): where to
/// look, what to read from a copy, the cross-check, the states. It starts
/// nothing that stays running.
class TomLibreOfficeDetector {
  /// A detector. [userPath] is the user's setting (empty: search).
  /// [applicationFolders] default to `/Applications` and `~/Applications`;
  /// [run] runs the short processes (`mdfind`, `lipo`, `codesign`, `xattr`,
  /// `spctl`, `soffice`); [scratch] holds the cross-check's private profile.
  /// Tests pass fake bundles in a temporary folder and a scripted runner.
  TomLibreOfficeDetector({
    this.userPath = '',
    List<String>? applicationFolders,
    List<String>? caskFolders,
    List<String>? macPortsFolders,
    TomDetectionRunner? run,
    String? scratch,
    String? searchPath,
    String? machineArchitecture,
    this.useSpotlight = true,
    this.crossCheckTimeout = const Duration(seconds: 15),
  }) : applicationFolders =
           applicationFolders ??
           [
             '/Applications',
             if (Platform.environment['HOME'] case final home?)
               p.join(home, 'Applications'),
           ],
       caskFolders =
           caskFolders ??
           [
             '/opt/homebrew/Caskroom/libreoffice',
             '/usr/local/Caskroom/libreoffice',
           ],
       macPortsFolders =
           macPortsFolders ??
           ['/opt/local/Applications', '/Applications/MacPorts'],
       _run = run ?? runDetectionProcess,
       _scratch =
           scratch ?? p.join(Directory.systemTemp.path, 'tom-office-detect'),
       _searchPath = searchPath ?? Platform.environment['PATH'] ?? '',
       _arch = machineArchitecture;

  /// The user's path setting; empty means *search*.
  final String userPath;

  /// The installation folders searched (`LibreOffice.app` in them first).
  final List<String> applicationFolders;

  /// Homebrew's cask folders (*Auto-detect*).
  final List<String> caskFolders;

  /// MacPorts' application folders (*Auto-detect*).
  final List<String> macPortsFolders;

  /// Whether Spotlight is asked.
  final bool useSpotlight;

  /// The cross-check's timeout.
  final Duration crossCheckTimeout;

  final TomDetectionRunner _run;
  final String _scratch;
  final String _searchPath;
  String? _arch;

  /// LibreOffice's bundle identifier.
  static const bundleId = 'org.libreoffice.script';

  /// The bundle names *Auto-detect* takes in the installation folders.
  static final autoDetectNames = RegExp(
    r'^(LibreOffice.*|LibreOfficeDev.*|Collabora Office.*)\.app$',
  );

  /// The start-up search: the user's path (its state, no fallback), then
  /// `/Applications/LibreOffice.app`, `~/Applications/LibreOffice.app`,
  /// then Spotlight (the newest usable hit). The first place holding a copy
  /// answers.
  Future<LibreOfficeInstallation> detect() async {
    final setting = userPath.trim();
    if (setting.isNotEmpty) return check(setting, source: 'setting');
    for (final (i, folder) in applicationFolders.indexed) {
      final bundle = p.join(folder, 'LibreOffice.app');
      if (Directory(bundle).existsSync()) {
        return check(bundle, source: i == 0 ? 'applications' : 'home');
      }
    }
    if (useSpotlight) {
      final hits = await _spotlight();
      if (hits.isNotEmpty) {
        final checked = [
          for (final hit in hits) await check(hit, source: 'spotlight'),
        ];
        return _best(checked);
      }
    }
    return const LibreOfficeInstallation(
      state: LibreOfficeState.missing,
      reason: 'No LibreOffice.app in the installation folders or Spotlight.',
    );
  }

  /// *Auto-detect*: the wider search. Every copy found on `PATH`, in the
  /// installation folders and one level below them (`LibreOffice*.app`,
  /// `LibreOfficeDev*.app`, `Collabora Office*.app`), in Homebrew's casks,
  /// MacPorts and Spotlight, each checked, newest first.
  Future<List<LibreOfficeInstallation>> autoDetect() async {
    final found = <String, String>{}; // bundle → source
    final seen = <String>{}; // the bundles' real paths
    void add(String? bundle, String source) {
      if (bundle == null) return;
      final normal = p.normalize(bundle);
      String real;
      try {
        real = Directory(normal).resolveSymbolicLinksSync();
      } on FileSystemException {
        real = normal;
      }
      // One copy reached two ways (a PATH symlink into a cask, /var and
      // /private/var) is listed once.
      if (!seen.add(real)) return;
      found.putIfAbsent(normal, () => source);
    }

    for (final dir in _searchPath.split(':')) {
      if (dir.isEmpty) continue;
      for (final name in ['soffice', 'libreoffice']) {
        final file = File(p.join(dir, name));
        if (!file.existsSync()) continue;
        try {
          add(bundleOf(file.resolveSymbolicLinksSync()), 'path');
        } on FileSystemException {
          continue;
        }
      }
    }
    for (final folder in applicationFolders) {
      for (final bundle in _bundlesIn(folder, depth: 1)) {
        add(bundle, 'applications');
      }
    }
    for (final folder in caskFolders) {
      for (final bundle in _bundlesIn(folder, depth: 1)) {
        add(bundle, 'homebrew');
      }
    }
    for (final folder in macPortsFolders) {
      for (final bundle in _bundlesIn(folder, depth: 0)) {
        add(bundle, 'macports');
      }
    }
    if (useSpotlight) {
      for (final hit in await _spotlight()) {
        add(hit, 'spotlight');
      }
    }
    final checked = [
      for (final MapEntry(:key, :value) in found.entries)
        await check(key, source: value),
    ];
    checked.sort((a, b) {
      final byState = (a.isUsable ? 0 : 1).compareTo(b.isUsable ? 0 : 1);
      if (byState != 0) return byState;
      return compareLibreOfficeVersions(b.version ?? '0', a.version ?? '0');
    });
    return checked;
  }

  /// The `.app` bundle above [path] (an executable or a folder inside a
  /// bundle), or [path] itself when it is one; `null` when there is none.
  static String? bundleOf(String path) {
    var current = p.normalize(path);
    while (true) {
      if (current.endsWith('.app')) return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  Iterable<String> _bundlesIn(String folder, {required int depth}) sync* {
    final dir = Directory(folder);
    if (!dir.existsSync()) return;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      final name = p.basename(e.path);
      if (e is! Directory && e is! Link) continue;
      if (autoDetectNames.hasMatch(name)) {
        yield e.path;
      } else if (depth > 0 && !name.endsWith('.app')) {
        yield* _bundlesIn(e.path, depth: depth - 1);
      }
    }
  }

  Future<List<String>> _spotlight() async {
    final run = await _run('mdfind', [
      "kMDItemCFBundleIdentifier == '$bundleId'",
    ], timeout: const Duration(seconds: 10));
    if (!run.ok) return const [];
    return const LineSplitter()
        .convert(run.stdout)
        .map((l) => l.trim())
        .where((l) => l.endsWith('.app'))
        .toList();
  }

  LibreOfficeInstallation _best(List<LibreOfficeInstallation> copies) {
    final usable = copies.where((c) => c.isUsable).toList()
      ..sort(
        (a, b) =>
            compareLibreOfficeVersions(b.version ?? '0', a.version ?? '0'),
      );
    if (usable.isNotEmpty) return usable.first;
    return copies.first;
  }

  /// Checks the copy at [path] (a bundle, or a path inside one): what it
  /// reads, the architecture, the signature, quarantine and the
  /// cross-check.
  Future<LibreOfficeInstallation> check(
    String path, {
    String source = 'setting',
  }) async {
    final bundle = bundleOf(path) ?? path;
    LibreOfficeInstallation answer(
      LibreOfficeState state, {
      String? version,
      String? id,
      String? reason,
    }) => LibreOfficeInstallation(
      state: state,
      bundlePath: bundle,
      version: version,
      bundleId: id,
      reason: reason,
      source: source,
    );

    if (!Directory(bundle).existsSync()) {
      return LibreOfficeInstallation(
        state: LibreOfficeState.missing,
        bundlePath: bundle,
        reason: 'Nothing at $bundle.',
        source: source,
      );
    }
    final plist = File(p.join(bundle, 'Contents', 'Info.plist'));
    if (!plist.existsSync()) {
      return answer(
        LibreOfficeState.damaged,
        reason: 'Contents/Info.plist is missing.',
      );
    }
    final info = readPlistStrings(plist.readAsStringSync());
    final version = info['CFBundleShortVersionString'];
    final id = info['CFBundleIdentifier'];
    if (version == null) {
      return answer(
        LibreOfficeState.damaged,
        id: id,
        reason: 'Info.plist has no CFBundleShortVersionString.',
      );
    }
    if (source != 'setting' && id != bundleId && !_knownOtherId(id)) {
      return answer(
        LibreOfficeState.damaged,
        version: version,
        id: id,
        reason: '$bundle is not a LibreOffice bundle (identifier $id).',
      );
    }
    final missing = [
      for (final part in [
        'Contents/Frameworks/libmergedlo.dylib',
        'Contents/MacOS/soffice',
        'Contents/Resources',
      ])
        if (FileSystemEntity.typeSync(p.join(bundle, part)) ==
            FileSystemEntityType.notFound)
          part,
    ];
    if (missing.isNotEmpty) {
      return answer(
        LibreOfficeState.damaged,
        version: version,
        id: id,
        reason: 'The bundle is incomplete: ${missing.join(', ')} missing.',
      );
    }
    if (compareLibreOfficeVersions(version, kLibreOfficeMinimumVersion) < 0) {
      return answer(LibreOfficeState.tooOld, version: version, id: id);
    }
    // The architecture: LibreOfficeKit cannot be loaded across
    // architectures, not even under Rosetta.
    final arch = _arch ??= (await _run('uname', ['-m'])).stdout.trim();
    final lipo = await _run('lipo', [
      '-archs',
      p.join(bundle, 'Contents', 'Frameworks', 'libmergedlo.dylib'),
    ]);
    if (lipo.ok && arch.isNotEmpty) {
      final archs = lipo.stdout.trim().split(RegExp(r'\s+'));
      if (!archs.contains(arch)) {
        return answer(
          LibreOfficeState.damaged,
          version: version,
          id: id,
          reason: arch == 'arm64' && archs.contains('x86_64')
              ? 'Intel build on an Apple Silicon Mac.'
              : 'libmergedlo.dylib is built for ${archs.join(', ')}, '
                    'this Mac is $arch.',
        );
      }
    }
    final codesign = await _run('codesign', ['--verify', bundle]);
    if (!codesign.ok) {
      return answer(
        LibreOfficeState.damaged,
        version: version,
        id: id,
        reason: 'codesign --verify failed: ${codesign.output}',
      );
    }
    final quarantine = await _run('xattr', [
      '-p',
      'com.apple.quarantine',
      bundle,
    ]);
    if (quarantine.ok) {
      final assess = await _run('spctl', [
        '--assess',
        '--type',
        'execute',
        bundle,
      ]);
      if (!assess.ok) {
        return answer(LibreOfficeState.quarantined, version: version, id: id);
      }
    }
    final cross = await _crossCheck(bundle);
    if (!cross.ok) {
      return answer(
        LibreOfficeState.damaged,
        version: version,
        id: id,
        reason: cross.timedOut
            ? 'soffice --version did not answer in '
                  '${crossCheckTimeout.inSeconds} s.'
            : 'soffice --version failed (exit ${cross.exitCode}): '
                  '${cross.output}',
      );
    }
    final reported = RegExp(
      r'(\d+(?:\.\d+)+)',
    ).firstMatch(cross.stdout)?.group(1);
    if (reported == null ||
        compareLibreOfficeVersions(reported, version) != 0) {
      return answer(
        LibreOfficeState.damaged,
        version: version,
        id: id,
        reason:
            'soffice reports ${reported ?? 'no version'}, Info.plist says '
            '$version: ${cross.output}',
      );
    }
    return answer(LibreOfficeState.found, version: version, id: id);
  }

  static bool _knownOtherId(String? id) =>
      id != null &&
      (id.startsWith('org.libreoffice') || id.contains('collabora'));

  Future<TomDetectionRun> _crossCheck(String bundle) async {
    final profile = Directory(p.join(_scratch, 'lo-detect'));
    try {
      profile.createSync(recursive: true);
    } on FileSystemException {
      // The run reports what goes wrong.
    }
    return _run(p.join(bundle, 'Contents', 'MacOS', 'soffice'), [
      '-env:UserInstallation=${profile.uri}',
      '--headless',
      '--version',
    ], timeout: crossCheckTimeout);
  }
}

/// The `<key>` / `<string>` pairs of an XML property list (the values the
/// detector reads), without starting anything.
Map<String, String> readPlistStrings(String xml) {
  final result = <String, String>{};
  final pair = RegExp(r'<key>\s*([^<]+?)\s*</key>\s*<string>([^<]*)</string>');
  for (final m in pair.allMatches(xml)) {
    result[m.group(1)!] = _unescape(m.group(2)!.trim());
  }
  return result;
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
