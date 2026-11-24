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

  group('OE-DETECT Linux and Windows', () {
    /// A fake program folder at `<root>/<parts>/program` holding [files].
    String makeProgram(List<String> parts, List<String> files) {
      final folder = Directory(p.joinAll([root.path, ...parts, 'program']))
        ..createSync(recursive: true);
      for (final f in files) {
        File(p.join(folder.path, f)).writeAsStringSync('x');
      }
      return folder.path;
    }

    TomLibreOfficeDetector onPlatform(
      TomToolPlatform platform,
      ScriptedRunner run, {
      String userPath = '',
      String searchPath = '',
    }) => TomLibreOfficeDetector(
      platform: platform,
      userPath: userPath,
      programFolderPatterns: [
        p.join(root.path, 'opt', 'libreoffice*', 'program'),
        p.join(root.path, 'usr', 'lib', 'libreoffice', 'program'),
      ],
      run: run.call,
      scratch: p.join(root.path, 'scratch'),
      searchPath: searchPath,
    );

    TomDetectionRun reports(String version) =>
        TomDetectionRun(0, 'LibreOffice $version 861effc\n', '');

    test('OE-DETECT-12: Linux: TDF\'s /opt folder, newest usable', () async {
      final tdf = makeProgram(
        ['opt', 'libreoffice26.8'],
        ['soffice', 'libmergedlo.so'],
      );
      makeProgram(['usr', 'lib', 'libreoffice'], ['soffice', 'libmergedlo.so']);
      final run = ScriptedRunner({'soffice': reports('26.8.3.1')});
      final r = await onPlatform(TomToolPlatform.linux, run).detect();
      expect(r.state, LibreOfficeState.found);
      expect(r.programPath, tdf);
      expect(r.sofficePath, p.join(tdf, 'soffice'));
      expect(r.bundlePath, p.join(root.path, 'opt', 'libreoffice26.8'));
      expect(r.source, 'folder');
      final soffice = run.calls.firstWhere((c) => c.startsWith('soffice'));
      expect(soffice, contains('-env:UserInstallation=file://'));
    });

    test('OE-DETECT-13: Linux\'s minimum 26.8.0: 26.8.2.2 is found there, '
        'too old on macOS', () async {
      makeProgram(['opt', 'libreoffice26.8'], ['soffice', 'libmergedlo.so']);
      final linux = await onPlatform(
        TomToolPlatform.linux,
        ScriptedRunner({'soffice': reports('26.8.2.2')}),
      ).detect();
      expect(linux.state, LibreOfficeState.found);
      expect(linux.version, '26.8.2.2');

      makeBundle(apps, version: '26.8.2.2');
      final mac = await detector(ScriptedRunner()).detect();
      expect(mac.state, LibreOfficeState.tooOld);
      expect(mac.minimumVersion, '26.8.3.1');

      makeProgram(['opt', 'libreoffice24.2'], ['soffice', 'libmergedlo.so']);
      final old = await onPlatform(
        TomToolPlatform.linux,
        ScriptedRunner({'soffice': reports('24.2.7.2')}),
      ).check(p.join(root.path, 'opt', 'libreoffice24.2'));
      expect(old.state, LibreOfficeState.tooOld);
      expect(old.minimumVersion, '26.8.0');
      expect(
        libreOfficeStateMessage(old),
        'LibreOffice 24.2.7.2 is older than 26.8.0.',
      );
    });

    test('OE-DETECT-14: Linux: a leftover folder is no copy; the setting '
        'names an unusable path', () async {
      makeProgram(['opt', 'libreoffice26.8'], ['soffice']);
      final run = ScriptedRunner({'soffice': reports('26.8.3.1')});
      final r = await onPlatform(TomToolPlatform.linux, run).detect();
      expect(r.state, LibreOfficeState.missing);
      final notLo = Directory(p.join(root.path, 'tools'))..createSync();
      final s = await onPlatform(
        TomToolPlatform.linux,
        run,
        userPath: notLo.path,
      ).detect();
      expect(s.state, LibreOfficeState.damaged);
      expect(s.isUnusableSetting, isTrue);
      expect(s.reason, contains('is not a LibreOffice program folder'));
      expect(s.reason, contains('soffice, libmergedlo.so missing'));
    });

    test(
      'OE-DETECT-15: Linux: soffice on PATH names its program folder',
      () async {
        final folder = makeProgram(
          ['elsewhere', 'lo'],
          ['soffice', 'libmergedlo.so'],
        );
        final bin = Directory(p.join(root.path, 'bin'))..createSync();
        Link(p.join(bin.path, 'soffice')).createSync(p.join(folder, 'soffice'));
        final all = await onPlatform(
          TomToolPlatform.linux,
          ScriptedRunner({'soffice': reports('26.8.3.1')}),
          searchPath: bin.path,
        ).autoDetect();
        expect(
          all.single.programPath,
          Directory(folder).resolveSymbolicLinksSync(),
        );
        expect(all.single.source, 'path');
      },
    );

    test(
      'OE-DETECT-16: Windows: soffice.exe and mergedlo.dll, version.ini',
      () async {
        final folder = makeProgram(
          ['opt', 'libreoffice'],
          ['soffice.exe', 'mergedlo.dll'],
        );
        File(p.join(folder, 'version.ini')).writeAsStringSync(
          '[Version]\nMsiProductVersion=26.8.3.1\nbuildid=861effc\n',
        );
        var r = await onPlatform(
          TomToolPlatform.windows,
          ScriptedRunner({'soffice.exe': reports('26.8.3.1')}),
        ).detect();
        expect(r.state, LibreOfficeState.found);
        expect(r.sofficePath, p.join(folder, 'soffice.exe'));
        r = await onPlatform(
          TomToolPlatform.windows,
          ScriptedRunner({'soffice.exe': reports('26.8.2.2')}),
        ).detect();
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('version.ini says 26.8.3.1'));
        // The leftover seen on legiondary01: only program\logs.
        final leftover = makeProgram(['usr', 'lib', 'libreoffice'], []);
        r = await onPlatform(
          TomToolPlatform.windows,
          ScriptedRunner(),
        ).check(leftover, source: 'programFiles');
        expect(r.state, LibreOfficeState.damaged);
        expect(r.reason, contains('soffice.exe, mergedlo.dll missing'));
      },
    );

    test('OE-DETECT-17: the defaults come from the descriptor', () {
      final d = TomLibreOfficeDetector(platform: TomToolPlatform.linux);
      expect(d.programFolderPatterns, [
        ('/opt/libreoffice*/program', 'tdf'),
        ('/usr/lib/libreoffice/program', 'distribution'),
        ('/usr/lib64/libreoffice/program', 'distribution'),
      ]);
      expect(d.minimumVersion, '26.8.0');
      final mac = TomLibreOfficeDetector(platform: TomToolPlatform.macos);
      expect(mac.applicationFolders.first, '/Applications');
      expect(mac.caskFolders, [
        '/opt/homebrew/Caskroom/libreoffice',
        '/usr/local/Caskroom/libreoffice',
      ]);
      expect(mac.minimumVersion, kLibreOfficeMinimumVersion);
    });

    test('OE-DETECT-18: which install routes can run here', () {
      final bin = Directory(p.join(root.path, 'bin'))..createSync();
      for (final name in ['dpkg', 'pkexec', 'apt-get']) {
        File(p.join(bin.path, name)).writeAsStringSync('x');
      }
      final available = installRouteAvailability(
        TomLibreOfficeTool.standard.routes(TomToolPlatform.linux),
        searchPath: bin.path,
        platform: TomToolPlatform.linux,
      );
      expect(available, {
        'linux-tdf-deb': true,
        'linux-tdf-rpm': false,
        // add-apt-repository is missing.
        'linux-apt-ppa': false,
        'linux-download': true,
      });
    });

    test('OE-DETECT-19: Windows: winget\'s app execution alias counts as on '
        'PATH', () {
      // Dart sees the alias in %LOCALAPPDATA%\Microsoft\WindowsApps as a
      // link that cannot be followed (legiondary01): File.existsSync is false.
      final apps = Directory(p.join(root.path, 'WindowsApps'))..createSync();
      final alias = p.join(apps.path, 'winget.exe');
      Link(alias).createSync(p.join(root.path, 'nowhere', 'winget.exe'));
      expect(File(alias).existsSync(), isFalse);
      expect(installExecutableExists(alias, windows: true), isTrue);
      expect(installExecutableExists(alias, windows: false), isFalse);
      expect(
        installRouteAvailability(
          TomLibreOfficeTool.standard.routes(TomToolPlatform.windows),
          searchPath: apps.path,
          platform: TomToolPlatform.windows,
        ),
        {
          'windows-winget': true,
          'windows-choco': false,
          'windows-download': true,
        },
      );
    });

    test('OE-DETECT-20: Windows: reg query\'s values name program folders', () {
      // `reg query HKLM\SOFTWARE\LibreOffice\UNO\InstallPath` after TDF's
      // MSI (winget, Chocolatey) on legiondary01, a German Windows.
      const installed = '''

HKEY_LOCAL_MACHINE\\SOFTWARE\\LibreOffice\\UNO\\InstallPath
    (Standard)    REG_SZ    C:\\Program Files\\LibreOffice\\program
    LibreOffice 26.8    REG_SZ    C:\\Program Files\\LibreOffice\\program

''';
      expect(TomLibreOfficeDetector.programFoldersInRegQuery(installed), [
        r'C:\Program Files\LibreOffice\program',
      ]);
      expect(
        TomLibreOfficeDetector.programFoldersInRegQuery(
          '    Path    REG_SZ    D:\\LO\\program\\soffice.exe\r\n'
          '    (Default)    REG_EXPAND_SZ    E:\\Office\\program\\\r\n'
          '    Count    REG_DWORD    0x1\r\n',
        ),
        [r'D:\LO\program', r'E:\Office\program'],
      );
      // A missing key (the leftover's MaintenanceService only): an error on
      // stderr, nothing on stdout.
      expect(TomLibreOfficeDetector.programFoldersInRegQuery(''), isEmpty);
    });

    test('OE-DETECT-21: Windows: a program folder the registry names is '
        'found there', () async {
      final folder = makeProgram(
        ['D', 'LibreOffice'],
        ['soffice.exe', 'mergedlo.dll'],
      );
      final run = ScriptedRunner({
        'soffice.exe': reports('26.8.3.1'),
        'reg': TomDetectionRun(
          0,
          '\nHKEY_LOCAL_MACHINE\\SOFTWARE\\LibreOffice\\UNO\\InstallPath\n'
              '    (Default)    REG_SZ    $folder\n',
          '',
        ),
      });
      final r = await onPlatform(TomToolPlatform.windows, run).detect();
      expect(r.state, LibreOfficeState.found);
      expect(r.programPath, folder);
      expect(r.source, 'registry');
      expect(run.calls.where((c) => c.startsWith('reg ')), [
        r'reg query HKLM\SOFTWARE\LibreOffice\UNO\InstallPath',
        r'reg query HKLM\SOFTWARE\WOW6432Node\LibreOffice\UNO\InstallPath',
        r'reg query HKCU\SOFTWARE\LibreOffice\UNO\InstallPath',
      ]);
      // Linux reads no registry.
      final linux = ScriptedRunner();
      await onPlatform(TomToolPlatform.linux, linux).detect();
      expect(linux.calls.where((c) => c.startsWith('reg ')), isEmpty);
    });

    test(
      'OE-DETECT-22: a byte that is no UTF-8 does not break a run',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('needs /bin/sh');
          return;
        }
        // reg.exe's German "Schlüssel" in the console code page (0xfc, cp1252;
        // 0x81 in cp850).
        final r = await runDetectionProcess('/bin/sh', [
          '-c',
          r"printf 'Schl\374ssel\201' >&2; printf 'ok'",
        ]);
        expect(r.ok, isTrue);
        expect(r.stdout, 'ok');
        expect(r.stderr, startsWith('Schl'));
      },
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
