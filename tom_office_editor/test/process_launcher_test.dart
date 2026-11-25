/// The helper's place in the binaries layer: the folder names are those of
/// `tom_binaries` (`darwin-arm64`, `linux-x64`, `win32-x64`).
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
    expect(TomOfficeProcessLauncher.findHelper(binaryPath: root.path), isNull);
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
}
