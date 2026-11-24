// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The LibreOffice tool descriptor (`part-libreoffice-detection`, *Reuse by
/// the guided install*; DPLD-3, DPLD-4): per platform the minimum version,
/// where a copy is looked for, the warnings, and the install routes the
/// install help offers. Pure Dart, no `dart:io`: the detector (`io.dart`)
/// and [TomLibreOfficeInstallHelp] read it; a host runs the routes.
library;

import 'package:flutter/foundation.dart';

import 'installation.dart';

/// A desktop platform a tool is described for.
enum TomToolPlatform {
  /// macOS.
  macos,

  /// Linux.
  linux,

  /// Windows.
  windows;

  /// The platform named as `Platform.operatingSystem` names it (`macos`,
  /// `linux`, `windows`); `null` for any other.
  static TomToolPlatform? fromName(String name) => switch (name) {
    'macos' => macos,
    'linux' => linux,
    'windows' => windows,
    _ => null,
  };

  /// The platform this app runs on ([defaultTargetPlatform]); `null` on a
  /// platform without a description (Android, iOS, Fuchsia).
  static TomToolPlatform? get current => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => macos,
    TargetPlatform.linux => linux,
    TargetPlatform.windows => windows,
    _ => null,
  };

  /// The name shown to the user.
  String get label => switch (this) {
    macos => 'macOS',
    linux => 'Linux',
    windows => 'Windows',
  };
}

/// How a route gets the rights it needs.
enum TomInstallElevation {
  /// Runs as the user (Homebrew).
  none,

  /// Runs as the user; the installer it starts asks for the rights itself
  /// (winget's MSI raises the UAC prompt).
  installerRaises,

  /// Must be started from an elevated shell (Chocolatey: PowerShell run as
  /// administrator).
  elevatedShell,

  /// Each command runs through `pkexec`, which asks for the password
  /// (polkit) before it runs.
  pkexec;

  /// What the confirmation says about it.
  String get description => switch (this) {
    none => 'Runs as you; no administrator rights are asked for.',
    installerRaises =>
      'Runs as you; the installer asks for administrator rights '
          '(a Windows security prompt).',
    elevatedShell =>
      'Needs administrator rights: it must run in a PowerShell started '
          'as administrator.',
    pkexec =>
      'Needs administrator rights: the system asks for your password '
          '(pkexec) before each command.',
  };
}

/// What a route is.
enum TomInstallRouteKind {
  /// A package manager installs it.
  packageManager,

  /// The host downloads TDF's archive, checks its hash, unpacks it and
  /// installs its packages ([TomManagedDownload]).
  managedDownload,

  /// The user downloads and installs it by hand from the download page.
  byHand,
}

/// A program a route needs, and how a host checks it is there: every one of
/// [executables] on `PATH` (`installRouteAvailability` in `io.dart`).
@immutable
final class TomPackageManager {
  /// A package manager from its parts.
  const TomPackageManager({
    required this.id,
    required this.name,
    required this.executables,
    this.homepage,
  });

  /// Its id, e.g. `brew`.
  final String id;

  /// Its name, e.g. `Homebrew`.
  final String name;

  /// The executables that must all be on `PATH` (without `.exe`).
  final List<String> executables;

  /// Where to get it, when it is missing.
  final String? homepage;
}

/// A hash a managed download is checked against.
@immutable
final class TomDownloadHashCheck {
  /// A hash check from its parts.
  const TomDownloadHashCheck({
    required this.urlTemplate,
    this.algorithm = 'sha256',
    this.format = '<hex digest>  <file name>',
  });

  /// The hash algorithm, `sha256`.
  final String algorithm;

  /// Where the published hash is, with `{version}` (e.g. `26.8.3`).
  final String urlTemplate;

  /// What the file holds: the first word is the hex digest.
  final String format;

  /// The hash file's URL for [version].
  String url(String version) => urlTemplate.replaceAll('{version}', version);

  /// The hex digest in a hash file's [text] (its first word, lower case);
  /// `null` when there is none.
  static String? digestIn(String text) {
    final m = RegExp(r'\b([0-9a-fA-F]{64})\b').firstMatch(text);
    return m?.group(1)!.toLowerCase();
  }
}

/// TDF's archive a [TomInstallRouteKind.managedDownload] route installs:
/// the host downloads [url], checks it against [hash], unpacks it into a
/// scratch folder, collects the files matching [packageGlob] (relative to
/// the scratch folder) and runs the route's commands with `{packages}`
/// replaced by them (one argument each).
@immutable
final class TomManagedDownload {
  /// A download from its parts.
  const TomManagedDownload({
    required this.urlTemplate,
    required this.hash,
    required this.packageGlob,
    required this.version,
    this.signatureUrlTemplate,
  });

  /// The archive, with `{version}`.
  final String urlTemplate;

  /// The hash it is checked against before anything is unpacked.
  final TomDownloadHashCheck hash;

  /// The release folder's version the templates are filled with (`26.8.3`).
  final String version;

  /// The packages in the unpacked archive, e.g.
  /// `LibreOffice_*_Linux_x86-64_deb/DEBS/*.deb`.
  final String packageGlob;

  /// TDF's detached GPG signature, with `{version}` (optional to check).
  final String? signatureUrlTemplate;

  /// The archive's URL for [version] (default [TomManagedDownload.version]).
  String url([String? version]) =>
      urlTemplate.replaceAll('{version}', version ?? this.version);

  /// The archive's file name.
  String fileName([String? version]) => url(version).split('/').last;

  /// The hash file's URL.
  String hashUrl([String? version]) => hash.url(version ?? this.version);

  /// The signature's URL, when there is one.
  String? signatureUrl([String? version]) =>
      signatureUrlTemplate?.replaceAll('{version}', version ?? this.version);
}

/// The placeholder in a managed download's commands that stands for the
/// unpacked packages (one argument each).
const kInstallPackagesPlaceholder = '{packages}';

/// One way to install the tool on one platform.
@immutable
final class TomInstallRoute {
  /// A route from its parts.
  const TomInstallRoute({
    required this.id,
    required this.label,
    required this.platform,
    required this.kind,
    this.commands = const [],
    this.elevation = TomInstallElevation.none,
    this.steps = const [],
    this.packageManager,
    this.versionOffered,
    this.download,
    this.url,
  });

  /// Its id, e.g. `macos-brew-cask`.
  final String id;

  /// What the user reads, e.g. `Homebrew`.
  final String label;

  /// The platform it is for.
  final TomToolPlatform platform;

  /// What it is.
  final TomInstallRouteKind kind;

  /// The commands it runs, in order, each as its argument list; the next
  /// only when the one before exited 0. A managed download's carry
  /// [kInstallPackagesPlaceholder].
  final List<List<String>> commands;

  /// How it gets its rights.
  final TomInstallElevation elevation;

  /// The few things the user does or sees, in order.
  final List<String> steps;

  /// The package manager it needs (none for a by-hand route).
  final TomPackageManager? packageManager;

  /// The LibreOffice version it delivers (DPLD-3's table, 2026-11-19; the
  /// PPA's checked on an Ubuntu 24.04 install, 2026-11-24).
  final String? versionOffered;

  /// The archive a managed download installs.
  final TomManagedDownload? download;

  /// The page a by-hand route opens.
  final String? url;

  /// Whether the host runs it ([commands] or [download]).
  bool get runnable => kind != TomInstallRouteKind.byHand;

  /// The commands as one would type them, one per line.
  List<String> get commandLines => [
    for (final argv in commands) argv.map(_quote).join(' '),
  ];

  static String _quote(String arg) =>
      arg.isEmpty || arg.contains(RegExp(r'\s')) ? '"$arg"' : arg;

  /// [commands] with [kInstallPackagesPlaceholder] replaced by [packages].
  List<List<String>> commandsWith(List<String> packages) => [
    for (final argv in commands)
      [
        for (final arg in argv)
          if (arg == kInstallPackagesPlaceholder) ...packages else arg,
      ],
  ];

  @override
  String toString() => 'TomInstallRoute($id)';
}

/// What the tool is on one platform.
@immutable
final class TomToolPlatformSpec {
  /// A platform's description from its parts.
  const TomToolPlatformSpec({
    required this.platform,
    required this.minimumVersion,
    required this.searchLocations,
    required this.programFiles,
    required this.programFolder,
    this.routes = const [],
    this.warnings = const [],
    this.registryKeys = const [],
  });

  /// The platform.
  final TomToolPlatform platform;

  /// The lowest version that counts as `found`.
  final String minimumVersion;

  /// Where a copy is looked for, by detection's `source` name, in order;
  /// `~` is the home folder and a `*` in a segment matches within it.
  /// macOS: installation folders holding `LibreOffice.app`; Linux and
  /// Windows: program folders.
  final Map<String, List<String>> searchLocations;

  /// The files a program folder (macOS: a bundle) must hold to count as a
  /// LibreOffice: the leftover folder seen on Windows does not.
  final List<String> programFiles;

  /// Where the program folder of the official build is, e.g.
  /// `/opt/libreoffice<x.y>/program`.
  final String programFolder;

  /// The install routes, in the order offered (the by-hand route last).
  final List<TomInstallRoute> routes;

  /// What the user should know on this platform.
  final List<String> warnings;

  /// Registry keys whose string values name a program folder (Windows):
  /// TDF's installer writes `UNO\InstallPath` (its default value and
  /// `LibreOffice <x.y>`, e.g. `C:\Program Files\LibreOffice\program`) and
  /// removes it on uninstall, so a leftover folder leaves no entry. The
  /// detector reads them with `reg query` and checks each folder as it
  /// checks [searchLocations].
  final List<String> registryKeys;

  /// Every folder pattern of [searchLocations], in order.
  List<String> get allSearchLocations => [
    for (final folders in searchLocations.values) ...folders,
  ];
}

/// A tool descriptor: its name, the download page, the licence notice and
/// each platform's [TomToolPlatformSpec]. [TomLibreOfficeTool.standard] is
/// LibreOffice's.
@immutable
final class TomLibreOfficeTool {
  /// A descriptor from its parts.
  const TomLibreOfficeTool({
    required this.name,
    required this.downloadPage,
    required this.licenceNotice,
    required this.platforms,
  });

  /// The tool's name.
  final String name;

  /// The official download page: the by-hand route.
  final String downloadPage;

  /// What the user is told about the licence.
  final String licenceNotice;

  /// Each platform's description.
  final Map<TomToolPlatform, TomToolPlatformSpec> platforms;

  /// [platform]'s description.
  TomToolPlatformSpec spec(TomToolPlatform platform) => platforms[platform]!;

  /// [platform]'s minimum version.
  String minimumVersion(TomToolPlatform platform) =>
      spec(platform).minimumVersion;

  /// Whether [version] reaches [platform]'s minimum.
  bool meetsMinimum(String version, TomToolPlatform platform) =>
      compareLibreOfficeVersions(version, minimumVersion(platform)) >= 0;

  /// [platform]'s install routes.
  List<TomInstallRoute> routes(TomToolPlatform platform) =>
      spec(platform).routes;

  /// The route [id], on any platform; `null` when there is none.
  TomInstallRoute? route(String id) {
    for (final s in platforms.values) {
      for (final r in s.routes) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  /// LibreOffice (DPLD-1, DPLD-3, DPLD-4; versions checked 2026-11-19).
  static const standard = TomLibreOfficeTool(
    name: 'LibreOffice',
    downloadPage: kLibreOfficeDownloadPage,
    licenceNotice:
        'LibreOffice is free software of The Document Foundation (MPL-2.0). '
        'It is not bundled with this app: you install it.',
    platforms: {
      TomToolPlatform.macos: TomToolPlatformSpec(
        platform: TomToolPlatform.macos,
        minimumVersion: kLibreOfficeMinimumVersion,
        searchLocations: {
          'applications': ['/Applications'],
          'home': ['~/Applications'],
          'homebrew': [
            '/opt/homebrew/Caskroom/libreoffice',
            '/usr/local/Caskroom/libreoffice',
          ],
          'macports': ['/opt/local/Applications', '/Applications/MacPorts'],
        },
        programFiles: [
          'Contents/Frameworks/libmergedlo.dylib',
          'Contents/MacOS/soffice',
          'Contents/Resources',
        ],
        programFolder: '/Applications/LibreOffice.app/Contents/Frameworks',
        routes: [
          TomInstallRoute(
            id: 'macos-brew-cask',
            label: 'Homebrew',
            platform: TomToolPlatform.macos,
            kind: TomInstallRouteKind.packageManager,
            commands: [
              ['brew', 'install', '--cask', 'libreoffice'],
            ],
            elevation: TomInstallElevation.none,
            packageManager: _homebrew,
            versionOffered: '26.8.3',
            steps: [
              'Homebrew downloads TDF\'s LibreOffice disk image and copies '
                  'LibreOffice.app into /Applications.',
              'Open LibreOffice once from Finder, so that macOS confirms it.',
              'Then choose Check again.',
            ],
          ),
          _byHandMacos,
        ],
      ),
      TomToolPlatform.linux: TomToolPlatformSpec(
        platform: TomToolPlatform.linux,
        minimumVersion: kLibreOfficeMinimumVersionLinux,
        searchLocations: {
          'tdf': ['/opt/libreoffice*/program'],
          'distribution': [
            '/usr/lib/libreoffice/program',
            '/usr/lib64/libreoffice/program',
          ],
        },
        programFiles: ['soffice', 'libmergedlo.so'],
        programFolder: '/opt/libreoffice<x.y>/program',
        warnings: [
          'The Snap and Flatpak packages of LibreOffice do not work: they '
              'are sandboxed, so the editor cannot load LibreOffice from '
              'them.',
          'The editor expects LibreOffice\'s program folder at '
              '/opt/libreoffice<x.y>/program, where TDF\'s packages install '
              'it (the distribution\'s packages use '
              '/usr/lib/libreoffice/program).',
          'The distribution\'s own LibreOffice (Ubuntu 24.04: 24.2, '
              'Fedora 43: 25.8) is too old.',
        ],
        routes: [
          TomInstallRoute(
            id: 'linux-tdf-deb',
            label: 'TDF\'s .deb packages (Debian, Ubuntu)',
            platform: TomToolPlatform.linux,
            kind: TomInstallRouteKind.managedDownload,
            commands: [
              ['pkexec', 'dpkg', '-i', kInstallPackagesPlaceholder],
            ],
            elevation: TomInstallElevation.pkexec,
            packageManager: _dpkg,
            versionOffered: '26.8.3.1',
            download: TomManagedDownload(
              version: '26.8.3',
              urlTemplate:
                  '$kTdfStableDownloads/{version}/deb/x86_64/'
                  'LibreOffice_{version}_Linux_x86-64_deb.tar.gz',
              hash: TomDownloadHashCheck(
                urlTemplate:
                    '$kTdfStableDownloads/{version}/deb/x86_64/'
                    'LibreOffice_{version}_Linux_x86-64_deb.tar.gz.sha256',
              ),
              signatureUrlTemplate:
                  '$kTdfStableDownloads/{version}/deb/x86_64/'
                  'LibreOffice_{version}_Linux_x86-64_deb.tar.gz.asc',
              packageGlob: 'LibreOffice_*_Linux_x86-64_deb/DEBS/*.deb',
            ),
            steps: [
              'The app downloads LibreOffice\'s .deb archive from '
                  'download.documentfoundation.org and checks its SHA-256.',
              'It unpacks the archive and installs its packages with dpkg; '
                  'the system asks for your password.',
              'LibreOffice lands in /opt/libreoffice<x.y>.',
            ],
          ),
          TomInstallRoute(
            id: 'linux-tdf-rpm',
            label: 'TDF\'s .rpm packages (Fedora, openSUSE)',
            platform: TomToolPlatform.linux,
            kind: TomInstallRouteKind.managedDownload,
            commands: [
              ['pkexec', 'rpm', '-Uvh', kInstallPackagesPlaceholder],
            ],
            elevation: TomInstallElevation.pkexec,
            packageManager: _rpm,
            versionOffered: '26.8.3.1',
            download: TomManagedDownload(
              version: '26.8.3',
              urlTemplate:
                  '$kTdfStableDownloads/{version}/rpm/x86_64/'
                  'LibreOffice_{version}_Linux_x86-64_rpm.tar.gz',
              hash: TomDownloadHashCheck(
                urlTemplate:
                    '$kTdfStableDownloads/{version}/rpm/x86_64/'
                    'LibreOffice_{version}_Linux_x86-64_rpm.tar.gz.sha256',
              ),
              signatureUrlTemplate:
                  '$kTdfStableDownloads/{version}/rpm/x86_64/'
                  'LibreOffice_{version}_Linux_x86-64_rpm.tar.gz.asc',
              packageGlob: 'LibreOffice_*_Linux_x86-64_rpm/RPMS/*.rpm',
            ),
            steps: [
              'The app downloads LibreOffice\'s .rpm archive from '
                  'download.documentfoundation.org and checks its SHA-256.',
              'It unpacks the archive and installs its packages with rpm; '
                  'the system asks for your password.',
              'LibreOffice lands in /opt/libreoffice<x.y>.',
            ],
          ),
          TomInstallRoute(
            id: 'linux-apt-ppa',
            label: 'apt with the LibreOffice PPA (Ubuntu)',
            platform: TomToolPlatform.linux,
            kind: TomInstallRouteKind.packageManager,
            commands: [
              ['pkexec', 'add-apt-repository', '-y', 'ppa:libreoffice/ppa'],
              ['pkexec', 'apt-get', 'update'],
              ['pkexec', 'apt-get', 'install', '-y', 'libreoffice'],
            ],
            elevation: TomInstallElevation.pkexec,
            packageManager: _aptPpa,
            versionOffered: '26.8.3.1',
            steps: [
              'Adds the LibreOffice team\'s stable PPA '
                  '(ppa:libreoffice/ppa) to apt\'s sources.',
              'Updates apt\'s package lists and installs libreoffice; the '
                  'system asks for your password.',
              'LibreOffice lands in /usr/lib/libreoffice and is updated '
                  'with the system from then on.',
            ],
          ),
          _byHandLinux,
        ],
      ),
      TomToolPlatform.windows: TomToolPlatformSpec(
        platform: TomToolPlatform.windows,
        minimumVersion: kLibreOfficeMinimumVersion,
        searchLocations: {
          'programFiles': [r'C:\Program Files\LibreOffice\program'],
        },
        programFiles: ['soffice.exe', 'mergedlo.dll'],
        programFolder: r'C:\Program Files\LibreOffice\program',
        registryKeys: [
          r'HKLM\SOFTWARE\LibreOffice\UNO\InstallPath',
          r'HKLM\SOFTWARE\WOW6432Node\LibreOffice\UNO\InstallPath',
          r'HKCU\SOFTWARE\LibreOffice\UNO\InstallPath',
        ],
        routes: [
          TomInstallRoute(
            id: 'windows-winget',
            label: 'winget',
            platform: TomToolPlatform.windows,
            kind: TomInstallRouteKind.packageManager,
            commands: [
              [
                'winget',
                'install',
                '--id',
                'TheDocumentFoundation.LibreOffice',
                '-e',
                '--accept-package-agreements',
                '--accept-source-agreements',
              ],
            ],
            elevation: TomInstallElevation.installerRaises,
            packageManager: _winget,
            versionOffered: '26.8.3.1',
            steps: [
              'winget downloads TDF\'s LibreOffice installer (.msi).',
              'Windows asks for administrator rights: confirm the prompt.',
              'LibreOffice lands in C:\\Program Files\\LibreOffice.',
            ],
          ),
          TomInstallRoute(
            id: 'windows-choco',
            label: 'Chocolatey',
            platform: TomToolPlatform.windows,
            kind: TomInstallRouteKind.packageManager,
            commands: [
              ['choco', 'install', 'libreoffice-fresh', '-y'],
            ],
            elevation: TomInstallElevation.elevatedShell,
            packageManager: _choco,
            versionOffered: '26.8.3',
            steps: [
              'Chocolatey needs an elevated shell: the command runs in a '
                  'PowerShell started as administrator.',
              'It installs the libreoffice-fresh package into '
                  'C:\\Program Files\\LibreOffice.',
            ],
          ),
          _byHandWindows,
        ],
      ),
    },
  );
}

/// LibreOffice's official download page: the by-hand route.
const kLibreOfficeDownloadPage =
    'https://www.libreoffice.org/download/download-libreoffice/';

/// The minimum version on Linux (DPLD-4): any 26.8 counts, so the stable
/// PPA's build counts while it is a bugfix release behind TDF's.
const kLibreOfficeMinimumVersionLinux = '26.8.0';

/// TDF's stable release folders (mirrored by MirrorBrain: appending
/// `.sha256` to a file's URL answers its SHA-256, `.mirrorlist` its
/// mirrors and hashes; `.asc` is TDF's GPG signature).
const kTdfStableDownloads =
    'https://download.documentfoundation.org/libreoffice/stable';

const _homebrew = TomPackageManager(
  id: 'brew',
  name: 'Homebrew',
  executables: ['brew'],
  homepage: 'https://brew.sh',
);

const _winget = TomPackageManager(
  id: 'winget',
  name: 'winget (App Installer)',
  executables: ['winget'],
  homepage: 'https://learn.microsoft.com/windows/package-manager/winget/',
);

const _choco = TomPackageManager(
  id: 'choco',
  name: 'Chocolatey',
  executables: ['choco'],
  homepage: 'https://chocolatey.org/install',
);

const _dpkg = TomPackageManager(
  id: 'dpkg',
  name: 'dpkg',
  executables: ['dpkg', 'pkexec'],
);

const _rpm = TomPackageManager(
  id: 'rpm',
  name: 'rpm',
  executables: ['rpm', 'pkexec'],
);

const _aptPpa = TomPackageManager(
  id: 'apt',
  name: 'apt with add-apt-repository',
  executables: ['apt-get', 'add-apt-repository', 'pkexec'],
);

const _byHandSteps = [
  'Open LibreOffice\'s download page and download the installer for this '
      'computer.',
  'Install it as the page says.',
  'Then choose Check again.',
];

const _byHandMacos = TomInstallRoute(
  id: 'macos-download',
  label: 'Download from libreoffice.org',
  platform: TomToolPlatform.macos,
  kind: TomInstallRouteKind.byHand,
  url: kLibreOfficeDownloadPage,
  versionOffered: '26.8.3.1',
  steps: _byHandSteps,
);

const _byHandLinux = TomInstallRoute(
  id: 'linux-download',
  label: 'Download from libreoffice.org',
  platform: TomToolPlatform.linux,
  kind: TomInstallRouteKind.byHand,
  url: kLibreOfficeDownloadPage,
  versionOffered: '26.8.3.1',
  steps: _byHandSteps,
);

const _byHandWindows = TomInstallRoute(
  id: 'windows-download',
  label: 'Download from libreoffice.org',
  platform: TomToolPlatform.windows,
  kind: TomInstallRouteKind.byHand,
  url: kLibreOfficeDownloadPage,
  versionOffered: '26.8.3.1',
  steps: _byHandSteps,
);
