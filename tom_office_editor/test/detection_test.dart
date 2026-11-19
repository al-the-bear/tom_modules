// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_office_editor/io.dart';
import 'package:tom_office_editor/tom_office_editor.dart';

/// A fake LibreOffice bundle at `<folder>/<name>`.
String makeBundle(
  String folder, {
  String name = 'LibreOffice.app',
  String version = '26.8.3.1',
  String id = 'org.libreoffice.script',
  bool library = true,
  bool soffice = true,
  bool resources = true,
  bool plist = true,
}) {
  final bundle = p.join(folder, name);
  final contents = Directory(p.join(bundle, 'Contents'))
    ..createSync(recursive: true);
  if (plist) {
    File(p.join(contents.path, 'Info.plist')).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$id</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
</dict>
</plist>
''');
  }
  if (library) {
    File(p.join(contents.path, 'Frameworks', 'libmergedlo.dylib'))
      ..createSync(recursive: true)
      ..writeAsStringSync('dylib');
  }
  if (soffice) {
    File(p.join(contents.path, 'MacOS', 'soffice'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh');
  }
  if (resources) Directory(p.join(contents.path, 'Resources')).createSync();
  return bundle;
}

/// A runner answering by program: [answers] maps `lipo`, `codesign`,
/// `xattr`, `spctl`, `soffice` and `mdfind` to a run; a missing one answers
/// as a healthy copy would.
class ScriptedRunner {
  ScriptedRunner([this.answers = const {}]);

  final Map<String, TomDetectionRun> answers;
  final calls = <String>[];

  Future<TomDetectionRun> call(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final name = p.basename(executable);
    calls.add('$name ${arguments.join(' ')}');
    final scripted = answers[name];
    if (scripted != null) return scripted;
    if (name == 'soffice') {
      // The version in the bundle's Info.plist: reported as LibreOffice
      // does.
      final bundle = TomLibreOfficeDetector.bundleOf(executable)!;
      final info = readPlistStrings(
        File(p.join(bundle, 'Contents', 'Info.plist')).readAsStringSync(),
      );
      return TomDetectionRun(
        0,
        'LibreOffice ${info['CFBundleShortVersionString']} 0123abc\n',
        '',
      );
    }
    return switch (name) {
      'uname' => const TomDetectionRun(0, 'arm64\n', ''),
      'lipo' => const TomDetectionRun(0, 'arm64\n', ''),
      'codesign' => const TomDetectionRun(0, '', ''),
      // No quarantine attribute.
      'xattr' => const TomDetectionRun(1, '', 'No such xattr'),
      'mdfind' => const TomDetectionRun(0, '', ''),
      _ => const TomDetectionRun(0, '', ''),
    };
  }
}

void main() {
  late Directory root;
  late String apps;
  late String home;

  setUp(() {
    root = Directory.systemTemp.createTempSync('office-detect-');
    apps = p.join(root.path, 'Applications');
    home = p.join(root.path, 'home', 'Applications');
    Directory(apps).createSync(recursive: true);
    Directory(home).createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  TomLibreOfficeDetector detector(
    ScriptedRunner run, {
    String userPath = '',
    String searchPath = '',
    bool spotlight = true,
  }) => TomLibreOfficeDetector(
    userPath: userPath,
    applicationFolders: [apps, home],
    caskFolders: [p.join(root.path, 'Caskroom', 'libreoffice')],
    macPortsFolders: [p.join(root.path, 'MacPorts')],
    run: run.call,
    scratch: p.join(root.path, 'scratch'),
    searchPath: searchPath,
    useSpotlight: spotlight,
  );

  group('OE-DETECT states', () {
    test('OE-DETECT-1: found, with the paths the helper needs', () async {
      final bundle = makeBundle(apps);
      final run = ScriptedRunner();
      final found = await detector(run).detect();
      expect(found.state, LibreOfficeState.found);
      expect(found.version, '26.8.3.1');
      expect(found.source, 'applications');
      expect(found.programPath, '$bundle/Contents/Frameworks');
      expect(found.sofficePath, '$bundle/Contents/MacOS/soffice');
      // The cross-check ran with a private profile.
      final soffice = run.calls.singleWhere((c) => c.startsWith('soffice'));
      expect(soffice, contains('-env:UserInstallation=file://'));
      expect(soffice, contains('--headless --version'));
    });

    test('OE-DETECT-2: missing when no copy is anywhere', () async {
      final r = await detector(ScriptedRunner()).detect();
      expect(r.state, LibreOfficeState.missing);
    });

    test('OE-DETECT-3: too old below the minimum version', () async {
      makeBundle(home, version: '24.2.7.2');
      final r = await detector(ScriptedRunner()).detect();
      expect(r.state, LibreOfficeState.tooOld);
      expect(r.version, '24.2.7.2');
      expect(r.source, 'home');
    });

    test(
      'OE-DETECT-4: damaged: incomplete, Intel, signature, cross-check',
      () async {
        final incomplete = makeBundle(apps, library: false);
        var r = await detector(ScriptedRunner()).check(incomplete);
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('Contents/Frameworks/libmergedlo.dylib'));

        final noPlist = makeBundle(apps, name: 'B.app', plist: false);
        r = await detector(ScriptedRunner()).check(noPlist);
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('Info.plist'));

        final intel = makeBundle(apps, name: 'Intel.app');
        r = await detector(
          ScriptedRunner({'lipo': const TomDetectionRun(0, 'x86_64\n', '')}),
        ).check(intel);
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, 'Intel build on an Apple Silicon Mac.');

        r = await detector(
          ScriptedRunner({
            'codesign': const TomDetectionRun(1, '', 'invalid signature'),
          }),
        ).check(intel);
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('invalid signature'));

        r = await detector(
          ScriptedRunner({
            'soffice': const TomDetectionRun(0, 'LibreOffice 26.2.1.0 abc', ''),
          }),
        ).check(intel);
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('soffice reports 26.2.1.0'));

        r = await detector(
          ScriptedRunner({
            'soffice': const TomDetectionRun(-1, '', '', timedOut: true),
          }),
        ).check(intel);
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('did not answer'));
      },
    );

    test('OE-DETECT-5: quarantined until Gatekeeper accepts it', () async {
      final bundle = makeBundle(apps);
      final attribute = const TomDetectionRun(0, '0083;6789;Safari;', '');
      var r = await detector(
        ScriptedRunner({
          'xattr': attribute,
          'spctl': const TomDetectionRun(3, '', 'rejected'),
        }),
      ).check(bundle);
      expect(r.state, LibreOfficeState.quarantined);
      r = await detector(
        ScriptedRunner({
          'xattr': attribute,
          'spctl': const TomDetectionRun(0, '', 'accepted'),
        }),
      ).check(bundle);
      expect(r.state, LibreOfficeState.found);
    });
  });

  group('OE-DETECT search', () {
    test('OE-DETECT-6: the user\'s path wins, without falling back', () async {
      makeBundle(apps);
      final r = await detector(
        ScriptedRunner(),
        userPath: p.join(root.path, 'elsewhere', 'LibreOffice.app'),
      ).detect();
      expect(r.state, LibreOfficeState.missing);
      expect(r.source, 'setting');
    });

    test('OE-DETECT-7: a path inside a bundle names the bundle', () async {
      final bundle = makeBundle(p.join(root.path, 'opt'));
      final r = await detector(
        ScriptedRunner(),
        userPath: '$bundle/Contents/Frameworks',
      ).detect();
      expect(r.state, LibreOfficeState.found);
      expect(r.bundlePath, bundle);
    });

    test('OE-DETECT-8: Spotlight: the newest usable hit', () async {
      final old = makeBundle(p.join(root.path, 'a'), version: '26.8.3.1');
      final newer = makeBundle(p.join(root.path, 'b'), version: '26.8.4.2');
      final broken = makeBundle(
        p.join(root.path, 'c'),
        version: '26.9.0.0',
        soffice: false,
      );
      final r = await detector(
        ScriptedRunner({
          'mdfind': TomDetectionRun(0, '$old\n$newer\n$broken\n', ''),
        }),
      ).detect();
      expect(r.state, LibreOfficeState.found);
      expect(r.bundlePath, newer);
      expect(r.source, 'spotlight');
    });

    test('OE-DETECT-9: Auto-detect lists every copy, usable first', () async {
      makeBundle(apps);
      makeBundle(
        p.join(apps, 'Office'),
        name: 'LibreOfficeDev.app',
        version: '26.9.0.0',
        id: 'org.libreoffice.script.dev',
      );
      makeBundle(
        home,
        name: 'Collabora Office.app',
        version: '24.4.1.1',
        id: 'com.collabora.office',
      );
      final cask = makeBundle(
        p.join(root.path, 'Caskroom', 'libreoffice', '26.8.3'),
      );
      final bin = Directory(p.join(root.path, 'bin'))..createSync();
      Link(
        p.join(bin.path, 'soffice'),
      ).createSync(p.join(cask, 'Contents', 'MacOS', 'soffice'));
      final all = await detector(
        ScriptedRunner(),
        searchPath: bin.path,
        spotlight: false,
      ).autoDetect();
      expect(all.map((c) => (p.basename(c.bundlePath!), c.state)), [
        ('LibreOfficeDev.app', LibreOfficeState.found),
        ('LibreOffice.app', LibreOfficeState.found),
        ('LibreOffice.app', LibreOfficeState.found),
        ('Collabora Office.app', LibreOfficeState.tooOld),
      ]);
      expect(all.map((c) => c.source), containsAll(['path', 'applications']));
    });
  });

  test('OE-DETECT-10: versions compare numerically', () {
    expect(compareLibreOfficeVersions('26.8.10', '26.8.9'), greaterThan(0));
    expect(compareLibreOfficeVersions('26.8', '26.8.0.0'), 0);
    expect(
      compareLibreOfficeVersions('24.2.7.2', kLibreOfficeMinimumVersion),
      lessThan(0),
    );
  });

  test('OE-DETECT-11: the real copy on this Mac, when there is one', () async {
    const real = '/Applications/LibreOffice.app';
    if (!Directory(real).existsSync()) {
      markTestSkipped('no LibreOffice in /Applications');
      return;
    }
    final r = await TomLibreOfficeDetector(
      scratch: p.join(root.path, 'scratch'),
      useSpotlight: false,
    ).detect();
    expect(r.state, LibreOfficeState.found, reason: '$r');
    expect(r.version, kLibreOfficeMinimumVersion);
  }, tags: ['libreoffice']);
}
