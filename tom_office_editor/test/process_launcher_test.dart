/// Where the helper is looked for: the running application's bundle first,
/// then the binaries layer, whose folder names are those of `tom_binaries`
/// (`darwin-arm64`, `linux-x64`, `win32-x64`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_office_editor/io.dart';

void main() {
  test('OE-LAUNCH-1: the binaries layer folder of each platform', () {
    String folder(String os, String arch) =>
        TomOfficeProcessLauncher.binariesPlatformFolder(
          operatingSystem: os,
          arch: arch,
        );
    expect(folder('macos', 'arm64'), 'darwin-arm64');
    expect(folder('linux', 'x64'), 'linux-x64');
    expect(folder('windows', 'x64'), 'win32-x64');
  });

  test('OE-LAUNCH-2: findHelper finds the helper in this platform\'s folder '
      'of a binaries layer, and nothing without one', () {
    final root = Directory.systemTemp.createTempSync('oe_launch_');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(
      TomOfficeProcessLauncher.findHelper(
        binaryPath: root.path,
        bundleFolders: const [],
      ),
      isNull,
    );
    final folder = TomOfficeProcessLauncher.binariesPlatformFolder(
      operatingSystem: Platform.operatingSystem,
      arch: Platform.version.contains('arm64') ? 'arm64' : 'x64',
    );
    final name = Platform.isWindows ? 'tom_office_host.exe' : 'tom_office_host';
    final helper = File(p.join(root.path, folder, name))
      ..createSync(recursive: true);
    expect(
      TomOfficeProcessLauncher.findHelper(binaryPath: root.path),
      helper.path,
    );
  });

  group('OE-LAUNCH-B the bundle before the binaries layer', () {
    late Directory root;
    late String layerHelper;
    setUp(() {
      root = Directory.systemTemp.createTempSync('oe_bundle_');
      final folder = TomOfficeProcessLauncher.binariesPlatformFolder(
        operatingSystem: Platform.operatingSystem,
        arch: Platform.version.contains('arm64') ? 'arm64' : 'x64',
      );
      layerHelper = p.join(
        root.path,
        'layer',
        folder,
        TomOfficeProcessLauncher.helperFileName,
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    File touch(String path) => File(path)..createSync(recursive: true);

    test('OE-LAUNCH-3: a helper in the bundle wins over the binaries '
        'layer', () {
      final bundle = p.join(root.path, 'Forge.app', 'Contents', 'MacOS');
      final inBundle = touch(
        p.join(bundle, TomOfficeProcessLauncher.helperFileName),
      );
      touch(layerHelper);
      expect(
        TomOfficeProcessLauncher.findHelper(
          bundleFolders: [bundle],
          environment: {'TOM_BINARY_PATH': p.join(root.path, 'layer')},
        ),
        inBundle.path,
      );
    });

    test('OE-LAUNCH-4: no helper in the bundle — TOM_BINARY_PATH, or '
        'binaryPath over it', () {
      final bundle = p.join(root.path, 'bundle');
      Directory(bundle).createSync(recursive: true);
      touch(layerHelper);
      expect(
        TomOfficeProcessLauncher.findHelper(
          bundleFolders: [bundle],
          environment: {'TOM_BINARY_PATH': p.join(root.path, 'layer')},
        ),
        layerHelper,
      );
      expect(
        TomOfficeProcessLauncher.findHelper(
          bundleFolders: [bundle],
          binaryPath: p.join(root.path, 'layer'),
          environment: const {},
        ),
        layerHelper,
      );
    });

    test('OE-LAUNCH-5: neither — null', () {
      expect(
        TomOfficeProcessLauncher.findHelper(
          bundleFolders: [p.join(root.path, 'bundle')],
          environment: {'TOM_BINARY_PATH': p.join(root.path, 'layer')},
        ),
        isNull,
      );
      expect(
        TomOfficeProcessLauncher.findHelper(
          bundleFolders: const [],
          environment: const {},
        ),
        isNull,
      );
    });

    test('OE-LAUNCH-6: under flutter test there is no bundle, so the default '
        'lookup reaches the binaries layer', () {
      touch(layerHelper);
      expect(
        TomOfficeProcessLauncher.findHelper(
          environment: {'TOM_BINARY_PATH': p.join(root.path, 'layer')},
        ),
        layerHelper,
      );
    });
  });
}
