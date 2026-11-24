// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/tom_office_editor.dart';

void main() {
  const tool = TomLibreOfficeTool.standard;

  test('OE-TOOL-1: the routes per platform, the by-hand route last', () {
    expect(tool.routes(TomToolPlatform.macos).map((r) => r.id), [
      'macos-brew-cask',
      'macos-download',
    ]);
    expect(tool.routes(TomToolPlatform.windows).map((r) => r.id), [
      'windows-winget',
      'windows-choco',
      'windows-download',
    ]);
    expect(tool.routes(TomToolPlatform.linux).map((r) => r.id), [
      'linux-tdf-deb',
      'linux-tdf-rpm',
      'linux-apt-ppa',
      'linux-download',
    ]);
    for (final platform in TomToolPlatform.values) {
      final last = tool.routes(platform).last;
      expect(last.kind, TomInstallRouteKind.byHand);
      expect(last.url, kLibreOfficeDownloadPage);
      expect(last.runnable, isFalse);
      expect(last.commands, isEmpty);
      for (final route in tool.routes(platform)) {
        expect(route.platform, platform);
        expect(route.steps, isNotEmpty, reason: route.id);
        expect(tool.route(route.id), same(route));
      }
    }
    expect(
      kLibreOfficeDownloadPage,
      'https://www.libreoffice.org/download/download-libreoffice/',
    );
  });

  test('OE-TOOL-2: commands, elevation, package managers, versions', () {
    final brew = tool.route('macos-brew-cask')!;
    expect(brew.commands, [
      ['brew', 'install', '--cask', 'libreoffice'],
    ]);
    expect(brew.elevation, TomInstallElevation.none);
    expect(brew.packageManager!.executables, ['brew']);
    expect(brew.versionOffered, '26.8.3');

    final winget = tool.route('windows-winget')!;
    // The agreements are accepted on the command line: the user confirmed
    // the route, and nothing is typed into a run.
    expect(winget.commandLines, [
      'winget install --id TheDocumentFoundation.LibreOffice -e '
          '--accept-package-agreements --accept-source-agreements',
    ]);
    expect(winget.elevation, TomInstallElevation.installerRaises);
    expect(winget.versionOffered, '26.8.3.1');

    final choco = tool.route('windows-choco')!;
    expect(choco.commandLines, ['choco install libreoffice-fresh -y']);
    expect(choco.elevation, TomInstallElevation.elevatedShell);
    expect(choco.packageManager!.executables, ['choco']);

    final ppa = tool.route('linux-apt-ppa')!;
    expect(ppa.kind, TomInstallRouteKind.packageManager);
    expect(ppa.commandLines, [
      'pkexec add-apt-repository -y ppa:libreoffice/ppa',
      'pkexec apt-get update',
      'pkexec apt-get install -y libreoffice',
    ]);
    expect(ppa.elevation, TomInstallElevation.pkexec);
    expect(ppa.packageManager!.executables, [
      'apt-get',
      'add-apt-repository',
      'pkexec',
    ]);
    // The PPA as installed on Ubuntu 24.04 on 2026-11-24.
    expect(ppa.versionOffered, '26.8.3.1');
    // Every Linux route reaches Linux's minimum (DPLD-4); a PPA build a
    // bugfix release behind (26.8.2.2) still would, not macOS's.
    for (final route in tool.routes(TomToolPlatform.linux)) {
      expect(
        tool.meetsMinimum(route.versionOffered!, TomToolPlatform.linux),
        isTrue,
        reason: route.id,
      );
    }
    expect(tool.meetsMinimum('26.8.2.2', TomToolPlatform.linux), isTrue);
    expect(tool.meetsMinimum('26.8.2.2', TomToolPlatform.macos), isFalse);
  });

  test('OE-TOOL-3: the managed downloads and their hash check', () {
    final deb = tool.route('linux-tdf-deb')!;
    expect(deb.kind, TomInstallRouteKind.managedDownload);
    expect(deb.elevation, TomInstallElevation.pkexec);
    final d = deb.download!;
    expect(
      d.url(),
      'https://download.documentfoundation.org/libreoffice/stable/26.8.3/'
      'deb/x86_64/LibreOffice_26.8.3_Linux_x86-64_deb.tar.gz',
    );
    expect(d.hashUrl(), '${d.url()}.sha256');
    expect(d.signatureUrl(), '${d.url()}.asc');
    expect(d.hash.algorithm, 'sha256');
    expect(d.fileName(), 'LibreOffice_26.8.3_Linux_x86-64_deb.tar.gz');
    expect(d.packageGlob, 'LibreOffice_*_Linux_x86-64_deb/DEBS/*.deb');
    expect(
      d.url('26.8.4'),
      contains('/26.8.4/deb/x86_64/LibreOffice_26.8.4_Linux_x86-64_deb'),
    );
    expect(deb.commandsWith(['/s/a.deb', '/s/b.deb']), [
      ['pkexec', 'dpkg', '-i', '/s/a.deb', '/s/b.deb'],
    ]);

    final rpm = tool.route('linux-tdf-rpm')!;
    expect(
      rpm.download!.hashUrl(),
      'https://download.documentfoundation.org/libreoffice/stable/26.8.3/'
      'rpm/x86_64/LibreOffice_26.8.3_Linux_x86-64_rpm.tar.gz.sha256',
    );
    expect(
      rpm.download!.packageGlob,
      'LibreOffice_*_Linux_x86-64_rpm/RPMS/*.rpm',
    );
    expect(rpm.commandsWith(['x.rpm']), [
      ['pkexec', 'rpm', '-Uvh', 'x.rpm'],
    ]);

    // The published hash file: "<digest>  <file name>".
    expect(
      TomDownloadHashCheck.digestIn(
        'E7CD3538E85818FF9DD9BB65386769FDE927011242AACE5A144989F4000DCABF  '
        'LibreOffice_26.8.3_Linux_x86-64_deb.tar.gz\n',
      ),
      'e7cd3538e85818ff9dd9bb65386769fde927011242aace5a144989f4000dcabf',
    );
    expect(TomDownloadHashCheck.digestIn('<html>not found</html>'), isNull);
  });

  test('OE-TOOL-4: minimum versions, locations and warnings', () {
    expect(tool.minimumVersion(TomToolPlatform.macos), '26.8.3.1');
    expect(tool.minimumVersion(TomToolPlatform.windows), '26.8.3.1');
    expect(tool.minimumVersion(TomToolPlatform.linux), '26.8.0');
    expect(tool.meetsMinimum('26.8.2.2', TomToolPlatform.linux), isTrue);
    expect(tool.meetsMinimum('26.8.2.2', TomToolPlatform.macos), isFalse);
    expect(tool.meetsMinimum('24.2.7.2', TomToolPlatform.linux), isFalse);

    final linux = tool.spec(TomToolPlatform.linux);
    expect(linux.allSearchLocations, [
      '/opt/libreoffice*/program',
      '/usr/lib/libreoffice/program',
      '/usr/lib64/libreoffice/program',
    ]);
    expect(linux.programFiles, ['soffice', 'libmergedlo.so']);
    expect(linux.programFolder, '/opt/libreoffice<x.y>/program');
    expect(linux.warnings.join('\n'), contains('Snap and Flatpak'));

    final windows = tool.spec(TomToolPlatform.windows);
    expect(windows.allSearchLocations, [
      r'C:\Program Files\LibreOffice\program',
    ]);
    expect(windows.programFiles, ['soffice.exe', 'mergedlo.dll']);
    // The keys TDF's MSI writes the program folder under (read by the
    // detector; checked on legiondary01 after winget and Chocolatey).
    expect(windows.registryKeys, [
      r'HKLM\SOFTWARE\LibreOffice\UNO\InstallPath',
      r'HKLM\SOFTWARE\WOW6432Node\LibreOffice\UNO\InstallPath',
      r'HKCU\SOFTWARE\LibreOffice\UNO\InstallPath',
    ]);
    expect(windows.warnings, isEmpty);
    expect(tool.spec(TomToolPlatform.macos).searchLocations.keys, [
      'applications',
      'home',
      'homebrew',
      'macports',
    ]);
    expect(TomToolPlatform.fromName('linux'), TomToolPlatform.linux);
    expect(TomToolPlatform.fromName('android'), isNull);
  });

  test('OE-TOOL-5: the run controller streams output, then its end', () async {
    final c = TomLibreOfficeInstallRunController();
    c.add('one ');
    c.add('two');
    final text = c.run.output.join();
    c.finish(3, message: 'apt failed');
    c.finish(0); // ignored
    expect(await text, 'one two');
    final result = await c.run.result;
    expect(result.exitCode, 3);
    expect(result.ok, isFalse);
    expect(result.message, 'apt failed');
    expect(c.isFinished, isTrue);
  });
}
