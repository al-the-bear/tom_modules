/// The package links everywhere, executed rather than asserted: nothing
/// reachable from `tom_file_session.dart` imports `dart:io`, `dart:ffi` or
/// Flutter, and a program over it compiles under dart2js. Each guard has a
/// negative control, so a guard that stopped looking fails rather than
/// passes.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_file_session/tom_file_session.dart';

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// Where the libraries the walk follows live: this package's, and those of
/// the workspace packages it builds on.
final _followed = {
  'tom_file_session': '${Directory.current.absolute.path}/lib/',
  'tom_file_system':
      '${Directory.current.parent.parent.path}/basics/tom_file_system/lib/',
  'tom_undo': '${Directory.current.parent.parent.path}/basics/tom_undo/lib/',
};

/// The external URIs imported by the libraries reachable from [entry],
/// following the libraries of the packages in [_followed].
Set<String> _reached(String entry) {
  final seen = <String>{};
  final external = <String>{};
  final queue = [File(entry).absolute.path];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      final uri = _directive.firstMatch(line)?.group(1);
      if (uri == null) continue;
      final package = uri.startsWith('package:')
          ? uri.substring('package:'.length, uri.indexOf('/'))
          : null;
      if (package != null && _followed.containsKey(package)) {
        queue.add(
          '${_followed[package]}'
          '${uri.substring('package:$package/'.length)}',
        );
      } else if (uri.contains(':')) {
        external.add(uri);
      } else {
        queue.add(File('${file.parent.path}/$uri').absolute.path);
      }
    }
  }
  return external;
}

/// Compiles [program]; the result, and the size of the JavaScript written.
Future<(ProcessResult, int)> _compileJs(String name, String program) async {
  final dart = Platform.resolvedExecutable;
  expect(
    dart.endsWith('dart') || dart.endsWith('dart.exe'),
    isTrue,
    reason:
        'run this suite with `dart test`; under another runner there '
        'is no Dart CLI to compile with',
  );
  final dir = (Directory(
    '.dart_tool/entry_points',
  )..createSync(recursive: true)).createTempSync('$name-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final entry = File('${dir.path}/main.dart')..writeAsStringSync(program);
  final result = await Process.run(dart, [
    'compile',
    'js',
    '--no-source-maps',
    '--packages=${Directory.current.absolute.path}/.dart_tool/package_config.json',
    '-o',
    '${dir.path}/out.js',
    entry.path,
  ]);
  final out = File('${dir.path}/out.js');
  return (result, out.existsSync() ? out.lengthSync() : 0);
}

void main() {
  group('FORGE-FILES-WEB the package links everywhere', () {
    test('FORGE-FILES-WEB-1: no dart:io, dart:ffi or Flutter is reachable', () {
      final uris = _reached('lib/tom_file_session.dart');
      expect(
        uris,
        contains('package:tom_basics/utilities.dart'),
        reason: 'the walk found almost nothing, so it proved nothing',
      );
      expect(uris, isNot(contains('dart:io')));
      expect(uris, isNot(contains('dart:ffi')));
      expect(uris.where((u) => u.startsWith('package:flutter/')), isEmpty);
    });

    test('FORGE-FILES-WEB-2: the walk does see dart:io where it is', () {
      expect(
        _reached('../../basics/tom_file_system/lib/io.dart'),
        contains('dart:io'),
      );
    });

    test('FORGE-FILES-WEB-3: a program over the package compiles under '
        'dart2js', () async {
      final (result, size) = await _compileJs('files', '''
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_file_system/tom_file_system.dart';

Future<void> main() async {
  final fs = TomMemoryFileSystem(seed: {'/a.env': 'KEY=secret\\n'});
  final session = ForgeFileSession(fileSystem: fs, path: 'a.env');
  await session.load();
  session.edit('KEY=other\\n', 'Edit');
  print(await session.save());
  print(ForgeEnvFile.parse(session.text).masked());
  print(ForgeBuiltInPresets.allFiles.filter.evaluate(
      const ForgeFilterSubject(path: '.git', name: '.git', isDirectory: true)));
}
''');
      expect(
        result.exitCode,
        0,
        reason: 'dart2js rejected it:\n${result.stdout}\n${result.stderr}',
      );
      expect(size, greaterThan(10000), reason: 'no program was written');
    });

    test('FORGE-FILES-WEB-4: dart2js refuses a program that does not '
        'compile', () async {
      final (result, size) = await _compileJs('broken', '''
import 'package:tom_file_session/tom_file_session.dart';

void main() => ForgeEnvFile.noSuchMember();
''');
      expect(result.exitCode, isNot(0));
      expect(size, 0);
    });
  });

  test('FORGE-FILES-REDACT-1: the masked .env text carries no value', () {
    final env = ForgeEnvFile.parse('A=hunter2\nexport B="two words"\n');
    final masked = env.masked();
    expect(masked, isNot(contains('hunter2')));
    expect(masked, isNot(contains('two words')));
    expect(masked, contains('A='));
  });
}
