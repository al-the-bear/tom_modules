// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/tom_office_editor.dart';

const _notFound = LibreOfficeInstallation(state: LibreOfficeState.missing);

const _tooOld = LibreOfficeInstallation(
  state: LibreOfficeState.tooOld,
  bundlePath: '/somewhere/LibreOffice',
  version: '24.2.7.2',
  source: 'applications',
);

const _unusable = LibreOfficeInstallation(
  state: LibreOfficeState.damaged,
  bundlePath: '/home/me/tools',
  reason: '/home/me/tools is not a LibreOffice program folder.',
  source: 'setting',
);

/// The ids of [platform]'s routes.
List<String> _routeIds(TomToolPlatform platform) => [
  for (final r in TomLibreOfficeTool.standard.routes(platform)) r.id,
];

Future<void> _pump(
  WidgetTester tester,
  LibreOfficeInstallation installation, {
  TomToolPlatform platform = TomToolPlatform.macos,
  TomLibreOfficeInstaller? onInstall,
  ValueChanged<String>? onOpenDownloadPage,
  VoidCallback? onCheckAgain,
  Map<String, bool>? routeAvailability,
}) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TomLibreOfficeInstallHelp(
          installation: installation,
          platform: platform,
          onInstall: onInstall,
          onOpenDownloadPage: onOpenDownloadPage,
          onCheckAgain: onCheckAgain,
          routeAvailability: routeAvailability,
        ),
      ),
    ),
  );
}

String _title(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('office-install-title')))
    .data!;

String _why(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('office-install-why')))
    .data!;

void main() {
  group('OE-INSTALL states per platform', () {
    for (final platform in TomToolPlatform.values) {
      final minimum = TomLibreOfficeTool.standard.minimumVersion(platform);
      final cases = <(String, LibreOfficeInstallation, String, String)>[
        ('not found', _notFound, 'LibreOffice is not installed.', 'None was'),
        (
          'too old',
          _tooOld,
          'LibreOffice 24.2.7.2 is older than $minimum.',
          'Install a newer one',
        ),
        (
          'unusable path',
          _unusable,
          'The LibreOffice path you set cannot be used.',
          'is not a LibreOffice program folder',
        ),
      ];
      for (final (name, installation, title, why) in cases) {
        testWidgets(
          'OE-INSTALL-1: $name on ${platform.name}: text and routes',
          (tester) async {
            await _pump(
              tester,
              installation,
              platform: platform,
              onInstall: (_) => TomLibreOfficeInstallRun.finished(
                const TomLibreOfficeInstallResult(0),
              ),
              onOpenDownloadPage: (_) {},
              onCheckAgain: () {},
            );
            expect(_title(tester), title);
            expect(_why(tester), contains(why));
            if (installation != _unusable) {
              expect(_why(tester), contains('LibreOffice $minimum or newer'));
            }
            for (final id in _routeIds(platform)) {
              expect(
                find.byKey(ValueKey('office-install-route-$id')),
                findsOneWidget,
                reason: id,
              );
            }
            // Only this platform's routes.
            for (final other in TomToolPlatform.values.where(
              (p) => p != platform,
            )) {
              for (final id in _routeIds(other)) {
                expect(
                  find.byKey(ValueKey('office-install-route-$id')),
                  findsNothing,
                );
              }
            }
            expect(
              find.byKey(const ValueKey('office-install-download')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('office-install-warnings')),
              platform == TomToolPlatform.linux ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('office-install-check-again')),
              findsOneWidget,
            );
          },
        );
      }
    }

    testWidgets('OE-INSTALL-2: the commands, elevation and Linux warnings', (
      tester,
    ) async {
      await _pump(tester, _notFound, platform: TomToolPlatform.linux);
      expect(find.textContaining('Snap and Flatpak'), findsOneWidget);
      expect(
        find.textContaining('/opt/libreoffice<x.y>/program'),
        findsWidgets,
      );
      expect(find.text('pkexec dpkg -i {packages}'), findsOneWidget);
      expect(
        find.text('pkexec add-apt-repository -y ppa:libreoffice/ppa'),
        findsOneWidget,
      );
      expect(
        find.text('pkexec apt-get install -y libreoffice'),
        findsOneWidget,
      );
      expect(
        find.text(
          'https://download.documentfoundation.org/libreoffice/stable/26.8.3/'
          'deb/x86_64/LibreOffice_26.8.3_Linux_x86-64_deb.tar.gz',
        ),
        findsOneWidget,
      );
      // No onInstall: the routes are shown, not runnable.
      final run = tester.widget<FilledButton>(
        find.byKey(const ValueKey('office-install-run-linux-apt-ppa')),
      );
      expect(run.onPressed, isNull);

      await _pump(tester, _notFound, platform: TomToolPlatform.windows);
      expect(
        find.text('winget install --id TheDocumentFoundation.LibreOffice -e'),
        findsOneWidget,
      );
      expect(find.text('choco install libreoffice-fresh -y'), findsOneWidget);
      expect(
        find.text(TomInstallElevation.elevatedShell.description),
        findsOneWidget,
      );

      await _pump(tester, _notFound);
      expect(find.text('brew install --cask libreoffice'), findsOneWidget);
    });

    testWidgets('OE-INSTALL-3: found and quarantined offer no routes', (
      tester,
    ) async {
      await _pump(
        tester,
        const LibreOfficeInstallation(
          state: LibreOfficeState.found,
          version: '26.8.3.1',
        ),
      );
      expect(_title(tester), 'LibreOffice 26.8.3.1 is ready.');
      expect(
        find.byKey(const ValueKey('office-install-download')),
        findsNothing,
      );
      await _pump(
        tester,
        const LibreOfficeInstallation(state: LibreOfficeState.quarantined),
      );
      expect(_title(tester), contains('has not been opened yet'));
      expect(
        find.byKey(const ValueKey('office-install-run-macos-brew-cask')),
        findsNothing,
      );
    });
  });

  group('OE-INSTALL running a route', () {
    testWidgets('OE-INSTALL-4: cancel runs nothing; confirm runs that route', (
      tester,
    ) async {
      final ran = <TomInstallRoute>[];
      await _pump(
        tester,
        _notFound,
        platform: TomToolPlatform.windows,
        onInstall: (route) {
          ran.add(route);
          return TomLibreOfficeInstallRun.finished(
            const TomLibreOfficeInstallResult(0),
          );
        },
      );
      await tester.tap(
        find.byKey(const ValueKey('office-install-run-windows-choco')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('office-install-confirm-dialog')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('office-install-confirm-dialog')),
          matching: find.text('choco install libreoffice-fresh -y'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('office-install-confirm-elevation')),
            )
            .data,
        TomInstallElevation.elevatedShell.description,
      );
      await tester.tap(find.byKey(const ValueKey('office-install-cancel')));
      await tester.pumpAndSettle();
      expect(ran, isEmpty);
      expect(find.byKey(const ValueKey('office-install-run')), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('office-install-run-windows-winget')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('office-install-confirm')));
      await tester.pumpAndSettle();
      expect(ran.map((r) => r.id), ['windows-winget']);
    });

    testWidgets('OE-INSTALL-5: the managed download names its hash check', (
      tester,
    ) async {
      await _pump(
        tester,
        _tooOld,
        platform: TomToolPlatform.linux,
        onInstall: (_) => TomLibreOfficeInstallRun.finished(
          const TomLibreOfficeInstallResult(0),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('office-install-run-linux-tdf-rpm')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'LibreOffice_26.8.3_Linux_x86-64_rpm.tar.gz.sha256',
        ),
        findsWidgets,
      );
      expect(find.text(TomInstallElevation.pkexec.description), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('office-install-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('OE-INSTALL-6: streamed output, the end, then Check again', (
      tester,
    ) async {
      final controller = TomLibreOfficeInstallRunController();
      var checks = 0;
      await _pump(
        tester,
        _notFound,
        onInstall: (_) {
          controller.add('==> Downloading LibreOffice\n');
          return controller.run;
        },
        onCheckAgain: () => checks++,
      );
      await tester.tap(
        find.byKey(const ValueKey('office-install-run-macos-brew-cask')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('office-install-confirm')));
      await tester.pump();
      await tester.pump();
      String output() => tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('office-install-output')),
          )
          .data!;
      String status() => tester
          .widget<Text>(find.byKey(const ValueKey('office-install-status')))
          .data!;
      expect(output(), contains('Downloading LibreOffice'));
      expect(status(), 'Installing with Homebrew…');
      // While it runs: no second run, no Check again.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('office-install-check-again')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('office-install-run-macos-brew-cask')),
            )
            .onPressed,
        isNull,
      );
      controller.add(
        '==> Moving App \'LibreOffice.app\' to '
        '\'/Applications/LibreOffice.app\'\n',
      );
      await tester.pump();
      expect(output(), contains('Moving App'));
      controller.finish(0);
      await tester.pump();
      await tester.pump();
      expect(status(), contains('finished. Choose Check again'));
      await tester.tap(
        find.byKey(const ValueKey('office-install-check-again')),
      );
      expect(checks, 1);
    });

    testWidgets('OE-INSTALL-7: a failed run shows its exit and message', (
      tester,
    ) async {
      await _pump(
        tester,
        _notFound,
        platform: TomToolPlatform.linux,
        onInstall: (_) => TomLibreOfficeInstallRun.finished(
          const TomLibreOfficeInstallResult(
            -1,
            message: 'The SHA-256 does not match',
          ),
          output: 'downloaded 312 MB\n',
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('office-install-run-linux-tdf-deb')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('office-install-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('office-install-status')))
            .data,
        contains('failed (exit -1): The SHA-256 does not match'),
      );
      expect(find.text('downloaded 312 MB\n'), findsOneWidget);
    });

    testWidgets('OE-INSTALL-8: a route whose package manager is missing', (
      tester,
    ) async {
      await _pump(
        tester,
        _notFound,
        platform: TomToolPlatform.windows,
        onInstall: (_) => throw StateError('not run'),
        routeAvailability: const {'windows-choco': false},
      );
      expect(
        find.byKey(const ValueKey('office-install-unavailable-windows-choco')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('office-install-run-windows-choco')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('office-install-run-windows-winget')),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  testWidgets('OE-INSTALL-9: the download link and Check again', (
    tester,
  ) async {
    final links = <String>[];
    var checks = 0;
    await _pump(
      tester,
      _tooOld,
      platform: TomToolPlatform.windows,
      onOpenDownloadPage: links.add,
      onCheckAgain: () => checks++,
    );
    await tester.tap(find.byKey(const ValueKey('office-install-download')));
    expect(links, [kLibreOfficeDownloadPage]);
    await tester.tap(find.byKey(const ValueKey('office-install-check-again')));
    expect(checks, 1);
  });

  testWidgets('OE-INSTALL-10: Linux\'s minimum: 26.8.2.2 is enough there', (
    tester,
  ) async {
    const old = LibreOfficeInstallation(
      state: LibreOfficeState.tooOld,
      version: '26.8.2.2',
      minimumVersion: kLibreOfficeMinimumVersion,
    );
    await _pump(tester, old);
    expect(_title(tester), 'LibreOffice 26.8.2.2 is older than 26.8.3.1.');
    expect(
      TomLibreOfficeTool.standard.meetsMinimum(
        '26.8.2.2',
        TomToolPlatform.linux,
      ),
      isTrue,
    );
    expect(
      TomLibreOfficeTool.standard.meetsMinimum(
        '26.8.2.2',
        TomToolPlatform.macos,
      ),
      isFalse,
    );
  });
}
