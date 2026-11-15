/// The fonts a golden is drawn with.
///
/// Flutter's test binding draws every glyph as an Ahem box unless a font is
/// loaded, so a shot of text would show grey bars whatever it held.
/// [loadTomGoldenFonts] loads Roboto and the Material icon font from the
/// Flutter SDK the test runs on and registers Roboto under the system and
/// monospace family names a theme or an editor asks for, so text, code and
/// formulas are readable; it loads the macOS symbol face a theme falls back
/// to for the glyphs Roboto lacks, and an emoji face for emoji.
///
/// The emoji face is Google's monochrome Noto Emoji (SIL Open Font License
/// 1.1, `fonts/OFL.txt` beside it), in this package's `fonts/` folder —
/// outside `lib/` and declared as no asset, so it travels with the package
/// and never into an application — so every machine draws an emoji the same
/// way: as an outline glyph standing in for the colour face, as Roboto stands
/// in for the system text faces.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Why a golden case does not run here, or null where it does: goldens are
/// compared on macOS only, because font rasterisation differs per platform
/// and a baseline that passes on one host and fails on the next is a baseline
/// nobody trusts.
final String? tomGoldenSkipReason = Platform.isMacOS
    ? null
    : 'goldens are baselined on macOS only (font rasterisation differs per '
        'platform)';

/// The family names [loadTomGoldenFonts] registers Roboto under.
const List<String> tomGoldenTextFamilies = [
  // The test engine's default family: what a TextStyle with no family
  // resolves to under `flutter test`.
  'FlutterTest',
  'Ahem',
  '.SF UI Text',
  '.SF UI Display',
  '.AppleSystemUIFont',
  // What Material resolves to under the iOS target platform, which a phone
  // shot is drawn as.
  'CupertinoSystemText',
  'CupertinoSystemDisplay',
  '.SF Pro Text',
  '.SF Pro Display',
  'monospace',
  'Courier',
  'Menlo',
  'RobotoMono',
  'Roboto Mono',
  // What Forge's Markdown and YAML editors ask for (`tom_md_editor`,
  // `tom_yaml_editor`), which a host shows in a tab.
  'Segoe UI',
  'Georgia',
  'Cascadia Code',
  'JetBrains Mono',
  '.SF Mono',
  'SF Mono',
];

/// The bundled Noto Emoji font file.
///
/// Resolved through the package configuration of the package whose test is
/// running (the nearest `.dart_tool/package_config.json` at or above the
/// working directory), since the Flutter test runner cannot resolve a package
/// URI; the running package must reach `tom_ui_testing`.
File tomGoldenEmojiFontFile() => _packageFile('fonts/NotoEmoji.ttf');

/// Loads the fonts every golden is drawn with. Call once, in `setUpAll`.
///
/// [symbolFace] is the face a theme falls back to for symbols Roboto lacks —
/// the macOS system face by default; goldens run on macOS only.
Future<void> loadTomGoldenFonts({
  String symbolFace = '/System/Library/Fonts/Apple Symbols.ttf',
}) async {
  const roboto = [
    'Roboto-Regular.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
    'Roboto-BoldItalic.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Light.ttf',
  ];
  await _loadSdk('Roboto', roboto);
  for (final family in tomGoldenTextFamilies) {
    await _loadSdk(family, roboto);
  }
  await _loadSdk('MaterialIcons', const ['MaterialIcons-Regular.otf']);
  final symbols = File(symbolFace);
  if (!symbols.existsSync()) {
    throw StateError('the symbol face $symbolFace is missing; the goldens '
        'draw the glyphs Roboto lacks with it');
  }
  await _loadFile('Apple Symbols', symbols);
  // Under the name macOS draws emoji with, which a theme's fallback names.
  await _loadFile('Apple Color Emoji', tomGoldenEmojiFontFile());
}

Future<void> _loadFile(String family, File file) => (FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
    .load();

Future<void> _loadSdk(String family, List<String> files) async {
  final dir =
      p.join(_flutterRoot(), 'bin', 'cache', 'artifacts', 'material_fonts');
  final loader = FontLoader(family);
  for (final name in files) {
    final bytes = File(p.join(dir, name)).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // `flutter test` runs the test inside the SDK's own engine; the executable
  // sits under <root>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (File(p.join(dir.path, 'bin', 'flutter')).existsSync()) return dir.path;
    dir = dir.parent;
  }
  throw StateError(
      'the Flutter SDK root could not be located; set FLUTTER_ROOT');
}

const String _package = 'tom_ui_testing';

File _packageFile(String path) {
  final config = _packageConfig();
  final packages = (jsonDecode(config.readAsStringSync())
      as Map<String, Object?>)['packages'] as List<Object?>;
  for (final entry in packages.cast<Map<String, Object?>>()) {
    if (entry['name'] != _package) continue;
    // rootUri is relative to the config file's folder, and a folder.
    final root =
        config.parent.uri.resolve(_asFolder(entry['rootUri']! as String));
    final file = File.fromUri(root.resolve(path));
    if (!file.existsSync()) {
      throw StateError('${file.path} is missing from $_package');
    }
    return file;
  }
  throw StateError('${config.path} names no $_package; the running package '
      'must depend on it');
}

String _asFolder(String uri) => uri.endsWith('/') ? uri : '$uri/';

File _packageConfig() {
  var dir = Directory.current.absolute;
  while (true) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) return config;
    if (dir.parent.path == dir.path) {
      throw StateError('no .dart_tool/package_config.json at or above '
          '${Directory.current.path}; run `pub get` first');
    }
    dir = dir.parent;
  }
}
