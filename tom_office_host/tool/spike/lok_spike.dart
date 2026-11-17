// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The first LibreOfficeKit spike (spike code, see README.md).
///
///     dart build cli -t tool/spike/lok_spike.dart
///     build/cli/macos_arm64/bundle/bin/lok_spike <command> [options]
///
/// Commands: init, tiles, type, save, password, helpers, kill, child,
/// parent-sim, dialog, ribbon. Options: --program, --samples, --out.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lok.dart';

late final Map<String, String> opts;
String get program =>
    opts['program'] ?? '/Applications/LibreOffice.app/Contents/Frameworks';
String get samples => opts['samples']!;
String get out => opts['out'] ?? Directory.current.path;
int _profiles = 0;

void log(String line) => stdout.writeln(line);

/// A fresh private profile folder as LibreOfficeKit wants it: a file:// URL.
(String, String) newProfile() {
  final dir = Directory(
    '${Directory.systemTemp.path}/office-host-spike/$pid-${_profiles++}/profile',
  )..createSync(recursive: true);
  return (dir.path, Uri.directory(dir.path).toString());
}

Office initOffice({String? profileUrl}) {
  final url = profileUrl ?? newProfile().$2;
  final watch = Stopwatch()..start();
  final office = Office.init(program, url);
  if (office == null) {
    log('RESULT lok_init_2 FAILED program=$program profile=$url');
    exit(3);
  }
  log(
    'lok_init_2 ok in ${watch.elapsedMilliseconds} ms program=$program profile=$url',
  );
  // Password callbacks, and comments as callbacks instead of in tiles.
  office.setOptionalFeatures(int.parse(opts['features'] ?? '11'));
  return office;
}

Future<Document> open(Office office, String path, {int tag = 1}) async {
  final watch = Stopwatch()..start();
  final doc = office.load(path, tag: tag);
  if (doc == null) {
    log('RESULT load FAILED $path: ${office.error()}');
    exit(4);
  }
  doc.initializeForRendering(
    opts['init'] ?? '{".uno:Author":{"type":"string","value":"Spike"}}',
  );
  if (opts['newview'] == 'yes') {
    final id = doc.createView();
    doc.view = id;
    doc.registerAgain();
    doc.initializeForRendering('{}');
    log('created and selected view $id');
  }
  if (opts['regafter'] == 'yes') doc.registerAgain();
  final (w, h) = doc.size;
  if (opts['zoom'] != 'no') {
    // 256 px per 3840 twips: 100 % at 96 dpi.
    doc.setClientZoom(256, 256, 3840, 3840);
    doc.setClientVisibleArea(0, 0, 24000, 16000);
  }
  log(
    'loaded ${path.split('/').last} in ${watch.elapsedMilliseconds} ms: '
    'type=${doc.type} parts=${doc.parts} size=${w}x$h twips tileMode=${doc.tileMode}',
  );
  await settle();
  return doc;
}

const _modes = {0: 'RGBA', 1: 'BGRA'};

/// A copy of a sample in this run's work folder, so edits, saves and lock
/// files never touch samples/files/.
String work(String name) {
  final dir = Directory(
    '${Directory.systemTemp.path}/office-host-spike/work-$pid',
  )..createSync(recursive: true);
  return File('$samples/$name').copySync('${dir.path}/$name').path;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: lok_spike <command> [--key value ...]');
    exit(2);
  }
  final o = <String, String>{};
  final rest = <String>[];
  for (var i = 1; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      o[args[i].substring(2)] = args[++i];
    } else {
      rest.add(args[i]);
    }
  }
  opts = o;
  log('# lok_spike ${args.first} pid=$pid ${DateTime.now().toIso8601String()}');
  switch (args.first) {
    case 'init':
      await cmdInit();
    case 'tiles':
      await cmdTiles();
    case 'type':
      await cmdType();
    case 'probe':
      await cmdProbe();
    case 'save':
      await cmdSave();
    case 'child':
      await cmdChild();
    case 'parent-sim':
      await cmdParentSim();
    case 'helpers':
      await cmdHelpers();
    case 'kill':
      await cmdKill();
    case 'dialog':
      await cmdDialog();
    case 'ribbon':
      await cmdRibbon();
    case 'password':
      await cmdPassword();
    default:
      stderr.writeln('unknown command ${args.first}');
      exit(2);
  }
  log(
    'callbacks: trampoline saw ${tomCallbackCount()}, Dart received '
    '$receivedCount, payloads not intact $corruptCount',
  );
  await stdout.flush();
  // The NativeCallable.listener keeps the isolate alive: leave explicitly.
  exit(0);
}

// --------------------------------------------------------------- item 1

Future<void> cmdInit() async {
  final running = Process.runSync('pgrep', [
    '-x',
    'soffice',
  ]).stdout.toString().trim();
  log(
    'user LibreOffice (soffice) running: ${running.isEmpty ? 'no' : 'yes, pid $running'}',
  );
  final given = opts['profile'];
  final (dir, url) = given != null
      ? (Uri.parse(given).toFilePath(), given)
      : newProfile();
  final office = initOffice(profileUrl: url);
  log('versionInfo ${office.versionInfo()}');
  final files = Directory(dir).listSync(recursive: true).length;
  log('profile $dir holds $files entries after init');
  office.destroy();
  final (_, url2) = (dir, url);
  log(
    'RESULT init ok (second init in the same process is not possible; '
    'profile reuse is measured by a second run with --profile $url2)',
  );
}

// --------------------------------------------------------------- item 2

Future<void> cmdTiles() async {
  final office = initOffice(profileUrl: opts['profile']);
  for (final name in ['report.docx', 'sheet.xlsx', 'deck.pptx']) {
    final doc = await open(office, '$samples/$name');
    final mode = doc.tileMode;
    final (w, h) = doc.size;
    final parts = doc.parts;
    final names = [for (var p = 0; p < parts && p < 5; p++) doc.partName(p)];
    log('  parts=$parts names(first 5)=$names');
    // 1024 px over 15360 twips: the top left of the first part at 100 %.
    final px = doc.paintTile(0, 1024, 1024, 0, 0, 15360, 15360);
    final ink = inkShare(px);
    final png = '$out/tile_${name.replaceAll('.', '_')}.png';
    writePng(png, px, 1024, 1024, bgra: mode == 1);
    log(
      '  tile 1024x1024 mode=${_modes[mode]} ink=${(ink * 100).toStringAsFixed(1)} % '
      'blank=${ink == 0} -> $png (document ${w}x$h twips)',
    );
    if (name == 'sheet.xlsx') await colourProbe(doc, mode);
    doc.destroy();
    await settle();
  }
  office.destroy();
  log('RESULT tiles done');
}

/// Paints A1 pure red (0xFF0000) and reads the bytes of a pixel inside it:
/// BGRA gives 00 00 FF FF, RGBA FF 00 00 FF.
Future<void> colourProbe(Document doc, int mode) async {
  doc.uno('.uno:GoToCell', '{"ToPoint":{"type":"string","value":"\$A\$1"}}');
  await settle();
  doc.uno(
    '.uno:BackgroundColor',
    '{"BackgroundColor":{"type":"long","value":16711680}}',
  );
  await waitEvent((e) => e.type == 0, timeout: const Duration(seconds: 5));
  await settle();
  final px = doc.paintTile(0, 256, 256, 0, 0, 3840, 3840);
  final i = (6 * 256 + 6) * 4;
  final bytes = px
      .sublist(i, i + 4)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  final expected = mode == 1 ? '00 00 ff ff' : 'ff 00 00 ff';
  writePng('$out/tile_colour_probe_A1_red.png', px, 256, 256, bgra: mode == 1);
  log(
    '  colour probe: A1 set to red, pixel (6,6) bytes = $bytes; reported '
    '${_modes[mode]} expects $expected -> ${bytes == expected ? 'MATCH' : 'NO MATCH'}',
  );
  doc.uno('.uno:Undo');
  await settle();
}

// --------------------------------------------------------------- items 3, 4

/// The cursor rectangle (twips) from the last INVALIDATE_VISIBLE_CURSOR.
List<int>? cursorRect() {
  for (final e in eventLog.reversed) {
    if (e.type != 1) continue;
    var text = e.payload;
    if (text.startsWith('{')) {
      text = (jsonDecode(text) as Map)['rectangle'] as String;
    }
    final v = text.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    if (v.length >= 4) return v;
  }
  return null;
}

double percentile(List<double> values, double p) {
  if (values.isEmpty) return double.nan;
  final s = [...values]..sort();
  return s[((s.length - 1) * p).round()];
}

Future<void> cmdType() async {
  final office = initOffice(profileUrl: opts['profile']);
  final plugins = Process.runSync('sh', [
    '-c',
    'lsof -p $pid | grep -o "libvclplug[a-z_]*lo.dylib" | sort -u',
  ]).stdout.toString().trim();
  log(
    'VCL plugins loaded in this process: ${plugins.isEmpty ? 'none (headless svp is built in)' : plugins}',
  );
  final doc = await open(office, work('report.docx'));
  // Into the "1975" cell of the first table, then to the end of its text.
  doc.click(2100, 4000);
  doc.press(key: Keys.end);
  await settle(const Duration(seconds: 1));
  var c = cursorRect();
  log('cursor after the click: $c');
  final x0 = ((c?[0] ?? 0) - 1500).clamp(0, 1 << 30);
  final y0 = ((c?[1] ?? 0) - 1000).clamp(0, 1 << 30);
  const tw = 9000, th = 3000, pw = 600, ph = 200;
  final before = doc.paintTile(0, pw, ph, x0, y0, tw, th);
  writePng('$out/item4_before.png', before, pw, ph);

  // Item 4: typed text in the tile painted after the following callbacks.
  final mark = clock.elapsed;
  doc.typeText(' SPIKE TYPED');
  final cur = await waitEvent((e) => e.type == 1 && e.at > mark);
  final inv = await waitEvent(
    (e) => e.type == 0 && e.at > mark,
    timeout: const Duration(seconds: 3),
  );
  await settle();
  final after = doc.paintTile(0, pw, ph, x0, y0, tw, th);
  writePng('$out/item4_after.png', after, pw, ph);
  final seen = <String, int>{};
  for (final e in eventLog.where((e) => e.at > mark)) {
    seen[e.name] = (seen[e.name] ?? 0) + 1;
  }
  log('item 4: callbacks after typing: $seen');
  log(
    'item 4: INVALIDATE_VISIBLE_CURSOR ${cur == null ? 'not received' : 'after ${(cur.at - mark).inMilliseconds} ms'}; '
    'INVALIDATE_TILES ${inv == null ? 'NOT received (3 s)' : 'received'}; '
    'pixels changed in the repainted tile: ${diffPixels(before, after)} of ${pw * ph}',
  );

  // Key-to-tile latency. INVALIDATE_TILES never comes, so: (a) key to the
  // cursor callback, (b) key to the first repainted 256x256 tile that
  // differs from the one before the key (painted in a loop).
  final toCursor = <double>[], toTile = <double>[], paintMs = <double>[];
  for (var i = 0; i < 100; i++) {
    c = cursorRect() ?? c;
    final tx = ((c?[0] ?? 0) - 1920).clamp(0, 1 << 30);
    final ty = ((c?[1] ?? 0) - 1920).clamp(0, 1 << 30);
    final base = doc.paintTile(0, 256, 256, tx, ty, 3840, 3840);
    final t0 = clock.elapsed;
    doc.press(char: 'x'.codeUnitAt(0));
    final cursorWait = waitEvent(
      (e) => e.type == 1 && e.at > t0,
      timeout: const Duration(seconds: 3),
    );
    Duration? changed;
    while (clock.elapsed - t0 < const Duration(seconds: 3)) {
      final p0 = clock.elapsed;
      final now = doc.paintTile(0, 256, 256, tx, ty, 3840, 3840);
      paintMs.add((clock.elapsed - p0).inMicroseconds / 1000);
      if (diffPixels(base, now) > 0) {
        changed = clock.elapsed;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final e = await cursorWait;
    if (e != null) toCursor.add((e.at - t0).inMicroseconds / 1000);
    if (changed != null) toTile.add((changed - t0).inMicroseconds / 1000);
    await settle(const Duration(milliseconds: 30));
  }
  String stats(List<double> v) =>
      '${v.length} samples, median '
      '${percentile(v, .5).toStringAsFixed(1)} p95 ${percentile(v, .95).toStringAsFixed(1)} '
      'max ${percentile(v, 1).toStringAsFixed(1)}';
  log('latency (ms) key -> INVALIDATE_VISIBLE_CURSOR: ${stats(toCursor)}');
  log('latency (ms) key -> repainted tile shows the key: ${stats(toTile)}');
  log('paintPartTile 256x256 (ms): ${stats(paintMs)}');

  // Item 3 under load: 5000 characters at the end of the 52-page document,
  // posted in bursts of 25 with a 2 ms pause, so callbacks flush meanwhile.
  doc.uno('.uno:GoToEndOfDoc');
  await settle();
  final startCount = receivedCount;
  final loadStart = clock.elapsed;
  for (var i = 0; i < 5000; i++) {
    doc.press(char: 'abcdefghij '.codeUnitAt(i % 11));
    if (i % 300 == 299) doc.press(key: Keys.enter);
    if (i % 25 == 24) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }
  log('posted 5000 keys in ${(clock.elapsed - loadStart).inMilliseconds} ms');
  var last = -1, quiet = 0;
  for (var i = 0; i < 180 && quiet < 3; i++) {
    await settle(const Duration(seconds: 1));
    quiet = receivedCount == last && tomCallbackCount() == receivedCount
        ? quiet + 1
        : 0;
    last = receivedCount;
  }
  final byType = <String, int>{};
  var longest = 0, bytes = 0;
  for (final e in eventLog.skip(startCount)) {
    byType[e.name] = (byType[e.name] ?? 0) + 1;
    bytes += e.payload.length;
    if (e.payload.length > longest) longest = e.payload.length;
  }
  log('  payload bytes in total $bytes');
  log(
    'item 3 under load: ${receivedCount - startCount} callbacks until quiet after '
    '${(clock.elapsed - loadStart).inMilliseconds} ms, longest payload $longest bytes, '
    'not intact $corruptCount, trampoline ${tomCallbackCount()} = Dart $receivedCount: '
    '${tomCallbackCount() == receivedCount}',
  );
  log('  by type: $byType');
  for (final e in eventLog.where((e) => e.type == 0)) {
    log('  INVALIDATE_TILES at ${e.at.inMilliseconds} ms: "${e.payload}"');
  }
  final p = cursorRect();
  final end = doc.paintTile(
    0,
    pw,
    ph,
    ((p?[0] ?? 0) - 7000).clamp(0, 1 << 30),
    ((p?[1] ?? 0) - 2000).clamp(0, 1 << 30),
    tw,
    th,
  );
  writePng('$out/item3_after_load.png', end, pw, ph);
  doc.destroy();
  await settle();
  office.destroy();
  log('RESULT destroy of document and office returned without a crash');
}

/// Watches whether posted keys are processed: polls tiles and callbacks.
Future<void> cmdProbe() async {
  final office = initOffice(profileUrl: opts['profile']);
  final doc = await open(office, work(opts['doc'] ?? 'letter.odt'));
  final threads = Process.runSync('sh', [
    '-c',
    'ps -M $pid | wc -l',
  ]).stdout.toString().trim();
  log('threads in process: $threads');
  doc.click(1440 * 2, 1440 * 3);
  await settle();
  final base = doc.paintTile(0, 512, 512, 0, 0, 7680, 7680);
  final count0 = receivedCount;
  final mark = clock.elapsed;
  final how = opts['how'] ?? 'key';
  if (how == 'key') doc.typeText('PROBE');
  if (how == 'uno') {
    doc.uno('.uno:InsertText', '{"Text":{"type":"string","value":"PROBE"}}');
  }
  for (var i = 0; i < 20; i++) {
    await settle(const Duration(milliseconds: 500));
    final now = doc.paintTile(0, 512, 512, 0, 0, 7680, 7680);
    log(
      '+${(clock.elapsed - mark).inMilliseconds} ms: callbacks +${receivedCount - count0} '
      '(C ${tomCallbackCount()}), pixels changed ${diffPixels(base, now)}',
    );
  }
  final seen = <String, int>{};
  for (final e in eventLog.where((e) => e.at > mark)) {
    seen[e.name] = (seen[e.name] ?? 0) + 1;
  }
  log('callbacks after input: $seen');
  final all = <String, int>{};
  for (final e in eventLog) {
    all[e.name] = (all[e.name] ?? 0) + 1;
  }
  log('all callbacks of the run: $all');
  for (final e in eventLog.where(
    (e) =>
        e.type == 8 &&
        RegExp(
          r'EditDoc|ReadOnly|ModifiedStatus|Protect|BrowseView|InsertMode',
        ).hasMatch(e.payload),
  )) {
    log('   state: ${e.payload}');
  }
  for (final e in eventLog.where(
    (e) => const {70, 40, 44, 60, 22}.contains(e.type),
  )) {
    log('   $e');
  }
  writePng(
    '$out/probe.png',
    doc.paintTile(0, 512, 512, 0, 0, 7680, 7680),
    512,
    512,
  );
  doc.destroy();
  office.destroy();
}

// --------------------------------------------------------------- item 5

String modifiedLog(Duration since) => eventLog
    .where(
      (e) =>
          e.at >= since &&
          e.type == 8 &&
          e.payload.startsWith('.uno:ModifiedStatus='),
    )
    .map((e) => e.payload.substring('.uno:ModifiedStatus='.length))
    .join(' -> ');

String workDir() => '${Directory.systemTemp.path}/office-host-spike/work-$pid';

Future<String> plainText(Document doc) async {
  doc.uno('.uno:SelectAll', '', false);
  await settle(const Duration(milliseconds: 500));
  return doc.textSelection() ?? '';
}

Future<void> cmdSave() async {
  final office = initOffice(profileUrl: opts['profile']);
  final path = work('letter.docx');
  final doc = await open(office, path);
  var since = clock.elapsed;
  doc.uno('.uno:GoToEndOfDoc');
  await settle();
  log('after load: ModifiedStatus ${modifiedLog(Duration.zero)}');
  since = clock.elapsed;
  doc.typeText('SPIKE SAVED TEXT');
  await waitEvent(
    (e) => e.payload == '.uno:ModifiedStatus=true',
    timeout: const Duration(seconds: 5),
  );
  log('after typing: ModifiedStatus ${modifiedLog(since)}');

  for (final (label, format, filter) in [
    ('saveAs docx, no options', 'docx', ''),
    ('saveAs odt, no options', 'odt', ''),
    ('saveAs docx, TakeOwnership', 'docx', 'TakeOwnership'),
  ]) {
    since = clock.elapsed;
    final target =
        '${workDir()}/saved_${label.replaceAll(RegExp('[^a-z]+'), '_')}.$format';
    final watch = Stopwatch()..start();
    final ok = doc.saveAs(target, format: format, filterOptions: filter);
    await settle(const Duration(seconds: 1));
    final size = File(target).existsSync() ? File(target).lengthSync() : -1;
    log(
      '$label: returned $ok in ${watch.elapsedMilliseconds} ms, file ${size >= 0 ? '$size bytes' : 'missing'}; '
      'ModifiedStatus ${modifiedLog(since).isEmpty ? '(no change reported)' : modifiedLog(since)}',
    );
  }
  since = clock.elapsed;
  doc.typeText(' AGAIN');
  await settle(const Duration(seconds: 1));
  log('typed again: ModifiedStatus ${modifiedLog(since)}');
  since = clock.elapsed;
  doc.uno('.uno:Save', '', true);
  final result = await waitEvent(
    (e) => e.type == 16,
    timeout: const Duration(seconds: 15),
  );
  await settle(const Duration(seconds: 1));
  log(
    '.uno:Save (to the URL the document now has): result ${result?.payload}; '
    'ModifiedStatus ${modifiedLog(since)}',
  );
  doc.destroy();
  await settle();

  // The saved files open again, with the typed text.
  for (final name in Directory(
    workDir(),
  ).listSync().map((f) => f.path).where((p) => p.contains('saved_'))) {
    final again = await open(office, name, tag: 2);
    final text = await plainText(again);
    log(
      'reopened ${name.split('/').last}: contains "SPIKE SAVED TEXT": ${text.contains('SPIKE SAVED TEXT')}',
    );
    again.destroy();
    await settle();
  }
  office.destroy();
  log('RESULT save done');
}

// --------------------------------------------------------------- password

bool encryptedFile(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.length > 4 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0) {
    return true; // OOXML encrypted: an OLE compound file, not a zip
  }
  final text = latin1.decode(bytes, allowInvalid: true);
  if (text.startsWith('%PDF')) return text.contains('/Encrypt');
  // ODF: the manifest names encryption-data when parts are encrypted.
  return text.contains('manifest:encryption-data') ||
      Process.runSync('sh', [
            '-c',
            'unzip -p "$path" META-INF/manifest.xml | grep -c encryption-data',
          ]).stdout.toString().trim() !=
          '0';
}

Future<void> cmdPassword() async {
  final office = initOffice(profileUrl: opts['profile']);
  const password = 'spike';
  // Make password-protected copies with LibreOffice's own Save As.
  final src = await open(office, work('letter.docx'));
  for (final (name, filter) in [
    ('protected.docx', 'MS Word 2007 XML'),
    ('protected.odt', 'writer8'),
  ]) {
    final target = '${workDir()}/$name';
    final since = clock.elapsed;
    src.uno(
      '.uno:SaveAs',
      jsonEncode({
        'URL': {'type': 'string', 'value': Uri.file(target).toString()},
        'FilterName': {'type': 'string', 'value': filter},
        'Password': {'type': 'string', 'value': password},
      }),
      true,
    );
    final r = await waitEvent(
      (e) => e.type == 16 && e.at > since,
      timeout: const Duration(seconds: 20),
    );
    log(
      'made $name with .uno:SaveAs + Password: ${r?.payload}; exists ${File(target).existsSync()}, '
      'encrypted ${File(target).existsSync() && encryptedFile(target)}',
    );
  }
  src.destroy();
  await settle();
  File('$samples/pdf-encrypted.pdf').copySync('${workDir()}/protected.pdf');

  for (final (name, pw, ext) in [
    ('protected.docx', password, 'docx'),
    ('protected.odt', password, 'odt'),
    ('protected.pdf', 'ELXRTQWS', 'pdf'),
  ]) {
    final path = '${workDir()}/$name';
    if (!File(path).existsSync()) continue;
    if (opts['only'] != null && !name.endsWith(opts['only']!)) continue;
    // --preset yes: setDocumentPassword from Dart before the load (crashes
    // LibreOffice 26.8.3.1, see the log); default: the trampoline answers
    // the DOCUMENT_PASSWORD callback from LibreOffice's thread.
    final since = clock.elapsed;
    Document? doc;
    if (opts['preset'] == 'yes') {
      log('$name: calling setDocumentPassword before the load ...');
      office.setDocumentPassword(path, pw);
      doc = office.load(path, tag: 3);
    } else {
      office.answerPasswords(pw);
      doc = office.load(path, tag: 3);
      office.answerPasswords(null);
    }
    await settle();
    final asked = eventLog
        .where((e) => e.at >= since && (e.type == 20 || e.type == 21))
        .map((e) => e.name)
        .toList();
    log(
      '$name: load ${doc != null ? 'ok' : 'failed (${office.error()})'}; password callbacks seen: $asked',
    );
    if (doc == null) continue;
    doc.initializeForRendering('{}');
    final out1 = '${workDir()}/resaved_$name';
    final ok = doc.saveAs(out1, format: ext);
    await settle(const Duration(seconds: 1));
    log(
      '$name: saveAs $ext returned $ok -> encrypted after saveAs: '
      '${File(out1).existsSync() ? encryptedFile(out1) : 'no file'}',
    );
    final out2 = '${workDir()}/resaved_owned_$name';
    final ok2 = doc.saveAs(out2, format: ext, filterOptions: 'TakeOwnership');
    await settle(const Duration(seconds: 1));
    log(
      '$name: saveAs $ext TakeOwnership returned $ok2 -> encrypted: '
      '${File(out2).existsSync() ? encryptedFile(out2) : 'no file'}',
    );
    doc.destroy();
    await settle();
    if (ext != 'pdf') {
      // .uno:Save writes to the document's own URL with its media
      // descriptor (which carries the encryption data).
      final copy = File(
        path,
      ).copySync('${workDir()}/saved_in_place_$name').path;
      office.answerPasswords(pw);
      final d2 = office.load(copy, tag: 4);
      office.answerPasswords(null);
      if (d2 != null) {
        d2.initializeForRendering('{}');
        d2.uno('.uno:GoToEndOfDoc');
        d2.typeText('X');
        await settle();
        final mark = clock.elapsed;
        d2.uno('.uno:Save', '', true);
        final r = await waitEvent(
          (e) => e.type == 16 && e.at > mark,
          timeout: const Duration(seconds: 15),
        );
        log(
          '$name: .uno:Save in place: ${r?.payload}; still encrypted: ${encryptedFile(copy)}',
        );
        d2.destroy();
        await settle();
      }
    }
  }
  office.destroy();
  log('RESULT password done');
}

// --------------------------------------------------------------- items 6, 7

/// A helper: its own profile, one document; ends on end of stdin.
Future<void> cmdChild() async {
  final (dir, url) = newProfile();
  final office = initOffice(profileUrl: url);
  final doc = await open(office, work(opts['doc']!));
  final px = doc.paintTile(0, 512, 512, 0, 0, 7680, 7680);
  log(
    'READY pid=$pid doc=${opts['doc']} profile=$dir ink=${(inkShare(px) * 100).toStringAsFixed(1)} %',
  );
  await stdout.flush();
  final done = Completer<void>();
  stdin.listen((_) {}, onDone: done.complete);
  await done.future;
  doc.destroy();
  office.destroy();
  Directory(dir).parent.deleteSync(recursive: true);
  log(
    'CLOSED pid=$pid: end of stdin, document and office destroyed, profile deleted',
  );
}

/// Stands in for Forge: starts a helper and waits; killed by the test.
Future<void> cmdParentSim() async {
  final child = await Process.start(Platform.resolvedExecutable, [
    'child',
    '--doc',
    opts['doc']!,
    '--samples',
    samples,
    '--out',
    out,
  ]);
  log('CHILD ${child.pid}');
  child.stdout.transform(utf8.decoder).listen(stdout.write);
  child.stderr.drain<void>();
  await child.exitCode;
}

Future<Process> startHelper(String doc) => Process.start(
  Platform.resolvedExecutable,
  ['child', '--doc', doc, '--samples', samples, '--out', out],
);

Future<String?> waitLine(
  Stream<String> lines,
  String prefix,
  Duration timeout,
) => lines
    .firstWhere((l) => l.startsWith(prefix))
    .then<String?>((l) => l)
    .timeout(timeout, onTimeout: () => null);

bool alive(int p) => Process.runSync('kill', ['-0', '$p']).exitCode == 0;

Future<void> cmdHelpers() async {
  final a = await startHelper('report.docx');
  final b = await startHelper('sheet.xlsx');
  final la = a.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  final lb = b.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  a.stderr.drain<void>();
  b.stderr.drain<void>();
  final closedA = waitLine(la, 'CLOSED', const Duration(minutes: 3));
  final closedB = waitLine(lb, 'CLOSED', const Duration(minutes: 3));
  final ra = waitLine(la, 'READY', const Duration(minutes: 2));
  final rb = waitLine(lb, 'READY', const Duration(minutes: 2));
  final readyA = await ra, readyB = await rb;
  log('helper A: $readyA');
  log('helper B: $readyB');
  log('both alive at the same time: A ${alive(a.pid)}, B ${alive(b.pid)}');
  final profiles = [
    readyA,
    readyB,
  ].map((r) => RegExp(r'profile=(\S+)').firstMatch(r ?? '')?.group(1)).toList();
  await a.stdin.close();
  await b.stdin.close();
  log('closed both stdins: A -> ${await closedA}, B -> ${await closedB}');
  log('exit codes: A ${await a.exitCode}, B ${await b.exitCode}');
  log(
    'profiles deleted: ${profiles.map((p) => p != null && !Directory(p).existsSync()).toList()}',
  );
  log('RESULT helpers done');
}

Future<void> cmdKill() async {
  // 7a: kill -9 of a helper is seen by its parent.
  final h = await startHelper('letter.docx');
  final lines = h.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  h.stderr.drain<void>();
  final ready = await waitLine(lines, 'READY', const Duration(minutes: 2));
  log('helper: $ready');
  final stdoutDone = Completer<void>();
  lines.listen((_) {}, onDone: stdoutDone.complete);
  final t0 = clock.elapsed;
  Process.killPid(h.pid, ProcessSignal.sigkill);
  final code = await h.exitCode;
  await stdoutDone.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  log(
    '7a: kill -9 ${h.pid}: parent saw exit code $code after '
    '${(clock.elapsed - t0).inMilliseconds} ms, end of its stdout: ${stdoutDone.isCompleted}',
  );
  final work = '${Directory.systemTemp.path}/office-host-spike/work-${h.pid}';
  final locks = Directory(work).existsSync()
      ? Directory(work)
            .listSync()
            .map((f) => f.path.split('/').last)
            .where((n) => n.startsWith('.~lock'))
            .toList()
      : [];
  final profile = RegExp(r'profile=(\S+)').firstMatch(ready ?? '')?.group(1);
  log(
    '7a: left behind: lock files $locks, profile folder ${profile != null && Directory(profile).existsSync()}',
  );

  // 7b: the parent dies (kill -9); the helper sees end of stdin and exits.
  final parent = await Process.start(Platform.resolvedExecutable, [
    'parent-sim',
    '--doc',
    'letter.docx',
    '--samples',
    samples,
    '--out',
    out,
  ]);
  final pl = parent.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  parent.stderr.drain<void>();
  final childLine = await waitLine(pl, 'CHILD', const Duration(seconds: 30));
  final childPid = int.parse(childLine!.split(' ').last);
  log(
    '7b: parent-sim ${parent.pid} started helper $childPid: ${await waitLine(pl, 'READY', const Duration(minutes: 2))}',
  );
  Process.killPid(parent.pid, ProcessSignal.sigkill);
  log('7b: parent-sim exit code ${await parent.exitCode}');
  final t1 = clock.elapsed;
  var gone = false;
  for (var i = 0; i < 300 && !gone; i++) {
    await settle(const Duration(milliseconds: 100));
    gone = !alive(childPid);
  }
  log(
    '7b: helper $childPid ${gone ? 'exited ${(clock.elapsed - t1).inMilliseconds} ms after its parent died' : 'STILL RUNNING after 30 s (orphan)'}',
  );
  final left = Process.runSync('sh', [
    '-c',
    'pgrep -fl "lok_spike (child|parent-sim)" || true',
  ]).stdout.toString().trim();
  log('7b: helper processes left: ${left.isEmpty ? 'none' : left}');
  log('RESULT kill done');
}

// --------------------------------------------------------------- item 8

Map<String, dynamic> windowPayload(LokEvent e) =>
    jsonDecode(e.payload) as Map<String, dynamic>;

/// Opens a dialog with --cmd in --doc, paints it, and replays --steps
/// (`click:x,y`, `key:tab|enter|escape|down|up|right|left`, `text:abc`,
/// `child`: paint the newest child window), painting after each step.
Future<void> cmdDialog() async {
  final office = initOffice(profileUrl: opts['profile']);
  final doc = await open(office, work(opts['doc'] ?? 'sheet.xlsx'));
  final name = opts['name'] ?? opts['cmd']!.replaceAll('.uno:', '');
  final mark = clock.elapsed;
  doc.uno(opts['cmd']!, opts['args'] ?? '', true);
  final created = await waitEvent(
    (e) =>
        e.type == 36 && e.at > mark && windowPayload(e)['action'] == 'created',
    timeout: const Duration(seconds: 20),
  );
  if (created == null) {
    log(
      'RESULT no WINDOW created for ${opts['cmd']} (20 s); callbacks: '
      '${eventLog.where((e) => e.at > mark).map((e) => e.name).toSet()}',
    );
    exit(5);
  }
  var w = windowPayload(created);
  log('WINDOW created: ${created.payload}');
  final id = int.parse('${w['id']}');
  final size = '${w['size']}'
      .split(',')
      .map((v) => int.parse(v.trim()))
      .toList();
  var px = doc.paintWindow(id, 0, 0, size[0], size[1]);
  writePng('$out/dialog_${name}_0.png', px, size[0], size[1]);
  log(
    'paintWindow ${size[0]}x${size[1]}: ink ${(inkShare(px) * 100).toStringAsFixed(1)} % -> dialog_${name}_0.png',
  );
  var step = 0;
  var active = id;
  var activeSize = size;
  for (final s in (opts['steps'] ?? '').split(';').where((s) => s.isNotEmpty)) {
    step++;
    final t = clock.elapsed;
    var target = active;
    var tsize = activeSize;
    final (kind, arg) = (
      s.split(':').first,
      s.contains(':') ? s.substring(s.indexOf(':') + 1) : '',
    );
    switch (kind) {
      case 'click':
        final xy = arg.split(',').map(int.parse).toList();
        doc.windowClick(active, xy[0], xy[1]);
      case 'key':
        doc.windowKey(
          active,
          key: const {
            'tab': Keys.tab,
            'enter': Keys.enter,
            'escape': Keys.escape,
            'down': Keys.down,
            'up': Keys.up,
            'right': Keys.right,
            'left': Keys.left,
            'end': Keys.end,
            'home': Keys.home,
            'backspace': Keys.backspace,
          }[arg]!,
        );
      case 'text':
        for (final r in arg.runes) {
          doc.windowKey(active, char: r);
        }
      case 'wait':
        break;
    }
    await settle(const Duration(milliseconds: 1500));
    final events = eventLog.where((e) => e.at > t).toList();
    final windows = events
        .where((e) => e.type == 36)
        .map(windowPayload)
        .toList();
    final newer = windows.where((p) => p['action'] == 'created').toList();
    log(
      'step $step $s: WINDOW actions ${windows.map((p) => '${p['id']}:${p['action']}${p['type'] != null ? '(${p['type']})' : ''}').toList()}',
    );
    if (newer.isNotEmpty) {
      final n = newer.last;
      target = int.parse('${n['id']}');
      tsize = '${n['size']}'
          .split(',')
          .map((v) => int.parse(v.trim()))
          .toList();
      log('   new window: ${jsonEncode(n)}');
    }
    final before = px;
    final sameWindow =
        target == active &&
        tsize[0] == activeSize[0] &&
        tsize[1] == activeSize[1];
    px = doc.paintWindow(target, 0, 0, tsize[0], tsize[1]);
    writePng('$out/dialog_${name}_$step.png', px, tsize[0], tsize[1]);
    log(
      '   painted window $target ${tsize[0]}x${tsize[1]}: pixels changed ${sameWindow ? diffPixels(before, px) : 'n/a (new window)'} -> dialog_${name}_$step.png',
    );
    if (newer.isNotEmpty && newer.last['type'] == 'dialog') {
      // Follow the new dialog from here on.
      w = newer.last;
      active = target;
      activeSize = tsize;
    }
  }
  final closeMark = clock.elapsed;
  for (final win
      in eventLog
          .where((e) => e.type == 36 && windowPayload(e)['action'] == 'created')
          .map(windowPayload)
          .toList()
          .reversed) {
    doc.postWindow(int.parse('${win['id']}'), 0);
  }
  await settle(const Duration(seconds: 2));
  log(
    'closed with postWindow(CLOSE): WINDOW actions ${eventLog.where((e) => e.at > closeMark && e.type == 36).map((e) => '${windowPayload(e)['id']}:${windowPayload(e)['action']}').toList()}; '
    'UNO_COMMAND_RESULT ${eventLog.where((e) => e.type == 16).map((e) => e.payload).toList()}',
  );
  log(
    'JSDIALOG callbacks (46) in this run: ${eventLog.where((e) => e.type == 46).length}',
  );
  doc.destroy();
  office.destroy();
  log('RESULT dialog done');
}

// --------------------------------------------------------------- item 9

String _a(Map<String, List<Object>> args) => jsonEncode({
  for (final e in args.entries)
    e.key: {'type': e.value[0], 'value': e.value[1]},
});

/// (command, arguments, opens a dialog) per document type, from WD
/// part-office-editor § The ribbon. Names the WD leaves open (margins,
/// orientation, columns, line spacing, zoom, header / footer, rows and
/// columns, sheets, alignment, decimals) are LibreOffice's names for them.
List<(String, String, bool)> ribbon(int type, String image) {
  const d = true, n = false;
  final font = [
    ('.uno:Copy', '', n),
    ('.uno:Cut', '', n),
    ('.uno:Paste', '', n),
    ('.uno:FormatPaintbrush', '', n),
    (
      '.uno:CharFontName',
      _a({
        'CharFontName.FamilyName': ['string', 'Liberation Sans'],
      }),
      n,
    ),
    (
      '.uno:FontHeight',
      _a({
        'FontHeight.Height': ['float', 14],
      }),
      n,
    ),
    ('.uno:Bold', '', n),
    ('.uno:Italic', '', n),
    ('.uno:Underline', '', n),
    ('.uno:Strikeout', '', n),
    ('.uno:SuperScript', '', n),
    ('.uno:SubScript', '', n),
    (
      '.uno:FontColor',
      _a({
        'FontColor': ['long', 255],
      }),
      n,
    ),
  ];
  final para = [
    ('.uno:LeftPara', '', n),
    ('.uno:CenterPara', '', n),
    ('.uno:RightPara', '', n),
    ('.uno:JustifyPara', '', n),
    ('.uno:DefaultBullet', '', n),
    ('.uno:DefaultNumbering', '', n),
    ('.uno:ParagraphDialog', '', d),
  ];
  final graphic = (
    '.uno:InsertGraphic',
    _a({
      'FileName': ['string', Uri.file(image).toString()],
    }),
    n,
  );
  switch (type) {
    case 0:
      return [
        ...font,
        (
          '.uno:CharBackColor',
          _a({
            'CharBackColor': ['long', 16776960],
          }),
          n,
        ),
        ('.uno:ResetAttributes', '', n),
        ('.uno:FontDialog', '', d),
        ...para,
        ('.uno:IncrementIndent', '', n),
        ('.uno:DecrementIndent', '', n),
        ('.uno:SpacePara15', '', n),
        (
          '.uno:StyleApply',
          _a({
            'Style': ['string', 'Heading 1'],
            'FamilyName': ['string', 'ParagraphStyles'],
          }),
          n,
        ),
        ('.uno:SearchDialog', '', d),
        ('.uno:InsertTable', '', d),
        graphic,
        ('.uno:InsertObjectChart', '', n),
        ('.uno:HyperlinkDialog', '', d),
        ('.uno:InsertPagebreak', '', n),
        ('.uno:CharmapControl', '', d),
        ('.uno:InsertAnnotation', '', n),
        (
          '.uno:InsertPageHeader',
          _a({
            'PageStyle': ['string', 'Default Page Style'],
            'On': ['boolean', true],
          }),
          n,
        ),
        (
          '.uno:InsertPageFooter',
          _a({
            'PageStyle': ['string', 'Default Page Style'],
            'On': ['boolean', true],
          }),
          n,
        ),
        ('.uno:InsertPageNumberField', '', n),
        ('.uno:PageDialog', '', d),
        ('.uno:PageMargin', '', n),
        ('.uno:Orientation', '', n),
        ('.uno:PageColumnType', '', n),
        ('.uno:SpellingAndGrammarDialog', '', d),
        ('.uno:WordCountDialog', '', d),
        ('.uno:TrackChanges', '', n),
        ('.uno:AcceptTrackedChange', '', n),
        ('.uno:RejectTrackedChange', '', n),
        ('.uno:ShowAnnotations', '', n),
        ('.uno:ZoomPlus', '', n),
        ('.uno:ControlCodes', '', n),
        ('.uno:BrowseView', '', n),
        ('.uno:PrintLayout', '', n),
      ];
    case 1:
      return [
        ...font,
        (
          '.uno:BackgroundColor',
          _a({
            'BackgroundColor': ['long', 16776960],
          }),
          n,
        ),
        ('.uno:SetBorderStyle', '', n),
        ('.uno:AlignLeft', '', n),
        ('.uno:AlignHorizontalCenter', '', n),
        ('.uno:AlignRight', '', n),
        ('.uno:AlignTop', '', n),
        ('.uno:AlignVCenter', '', n),
        ('.uno:AlignBottom', '', n),
        ('.uno:WrapText', '', n),
        ('.uno:ToggleMergeCells', '', n),
        ('.uno:NumberFormatStandard', '', n),
        ('.uno:NumberFormatCurrency', '', n),
        ('.uno:NumberFormatPercent', '', n),
        ('.uno:NumberFormatIncDecimals', '', n),
        ('.uno:NumberFormatDecDecimals', '', n),
        ('.uno:FormatCellDialog', '', d),
        ('.uno:InsertRowsAfter', '', n),
        ('.uno:InsertColumnsAfter', '', n),
        ('.uno:DeleteRows', '', n),
        ('.uno:DeleteColumns', '', n),
        ('.uno:SearchDialog', '', d),
        ('.uno:FunctionDialog', '', d),
        ('.uno:AutoSum', '', n),
        ('.uno:InsertObjectChart', '', n),
        graphic,
        ('.uno:InsertAnnotation', '', n),
        ('.uno:HyperlinkDialog', '', d),
        ('.uno:FreezePanes', '', n),
        ('.uno:RowHeight', '', d),
        ('.uno:ColumnWidth', '', d),
        ('.uno:Insert', '', d),
        ('.uno:RenameTable', '', d),
        ('.uno:Remove', '', d),
        ('.uno:SortAscending', '', n),
        ('.uno:SortDescending', '', n),
        ('.uno:DataSort', '', d),
        ('.uno:DataFilterAutoFilter', '', n),
        ('.uno:Validation', '', d),
        ('.uno:SpellingAndGrammarDialog', '', d),
        ('.uno:SpellDialog', '', d),
        ('.uno:ZoomPlus', '', n),
        ('.uno:ToggleSheetGrid', '', n),
        ('.uno:ViewRowColumnHeaders', '', n),
      ];
    default:
      return [
        ...font,
        ...para,
        ('.uno:InsertPage', '', n),
        ('.uno:DuplicatePage', '', n),
        ('.uno:DeletePage', '', n),
        (
          '.uno:AssignLayout',
          _a({
            'WhatLayout': ['long', 1],
          }),
          n,
        ),
        ('.uno:Text', '', n),
        graphic,
        ('.uno:InsertTable', '', d),
        ('.uno:InsertObjectChart', '', n),
        ('.uno:BasicShapes.rectangle', '', n),
        ('.uno:HyperlinkDialog', '', d),
        ('.uno:SlideSetup', '', d),
        ('.uno:SpellingAndGrammarDialog', '', d),
        ('.uno:SpellDialog', '', d),
        ('.uno:InsertAnnotation', '', n),
        ('.uno:ZoomPlus', '', n),
        ('.uno:NotesMode', '', n),
        ('.uno:NormalViewMode', '', n),
      ];
  }
}

Future<void> cmdRibbon() async {
  final office = initOffice(profileUrl: opts['profile']);
  final docName = opts['doc']!;
  final doc = await open(office, work(docName));
  final image = '${workDir()}/insert.png';
  File('$out/tile_colour_probe_A1_red.png').copySync(image);
  // A selection the formatting commands can work on, made again before each
  // command (an inserted image or shape would otherwise stay selected).
  Future<void> select() async {
    // Escape is a key event, processed asynchronously: let it land before
    // the selection is made again.
    doc.press(key: Keys.escape);
    await settle(const Duration(milliseconds: 300));
    if (doc.type == 0) {
      doc.uno('.uno:GoToStartOfDoc', '', false);
      doc.uno('.uno:EndOfParaSel', '', false);
    } else if (doc.type == 1) {
      doc.uno(
        '.uno:GoToCell',
        '{"ToPoint":{"type":"string","value":"\$B\$3"}}',
        false,
      );
    } else {
      doc.part = 0;
      // The slide's objects, which the paragraph and font commands act on.
      doc.uno('.uno:SelectAll', '', false);
    }
    await settle(const Duration(milliseconds: 300));
  }

  final skip = (opts['skip'] ?? '').split(',').toSet();
  final only = opts['only']?.split(',').toSet();
  final results = <Map<String, Object?>>[];
  for (final (cmd, args, dialog) in ribbon(doc.type, image)) {
    if (only != null && !only.contains(cmd)) continue;
    if (skip.contains(cmd)) {
      log('SKIP $cmd');
      continue;
    }
    await select();
    stdout.write('posting $cmd ... ');
    await stdout.flush();
    final mark = clock.elapsed;
    Future<void>? posting;
    if (opts['isolate'] == 'yes') {
      posting = doc.unoInIsolate(cmd, args);
    } else {
      doc.uno(cmd, args, true);
    }
    final done = await waitEvent(
      (e) =>
          e.at > mark &&
          ((e.type == 16 && e.payload.contains('"$cmd"')) ||
              (e.type == 36 && e.payload.contains('"created"'))),
      timeout: const Duration(seconds: 8),
    );
    await settle(const Duration(milliseconds: 400));
    final windows = eventLog
        .where(
          (e) => e.at > mark && e.type == 36 && e.payload.contains('"created"'),
        )
        .map(windowPayload)
        .toList();
    for (final w in windows.reversed) {
      doc.postWindow(int.parse('${w['id']}'), 0);
    }
    if (windows.isNotEmpty) await settle(const Duration(seconds: 1));
    var returned = true;
    if (posting != null) {
      returned = await posting
          .then((_) => true)
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!returned) {
        log('  (the posting isolate is still blocked in postUnoCommand)');
      }
    }
    final result = eventLog
        .where(
          (e) => e.at > mark && e.type == 16 && e.payload.contains('"$cmd"'),
        )
        .map((e) => jsonDecode(e.payload) as Map<String, dynamic>)
        .firstOrNull;
    final state = eventLog
        .where((e) => e.type == 8 && e.payload.startsWith('$cmd='))
        .map((e) => e.payload.substring(cmd.length + 1))
        .toList();
    final asked = args.isEmpty
        ? null
        : (jsonDecode(args) as Map).values.first['value'].toString();
    final appliedByState =
        !dialog &&
        result?['success'] != true &&
        asked != null &&
        state.isNotEmpty &&
        state.last.contains(asked.replaceAll('.0', ''));
    final ok = dialog
        ? windows.isNotEmpty
        : (result?['success'] == true || appliedByState);
    final entry = {
      'command': cmd,
      'dialog': dialog,
      'ok': ok,
      'unoCommandResult': result?['success'],
      'windowOpened': windows.isEmpty
          ? null
          : '${windows.first['unique_id']} "${windows.first['title']}"',
      'stateChanged': state.isEmpty ? null : state.last,
      'stateChangedCount': state.length,
      'appliedButResultFalse': appliedByState,
      if (posting != null) 'postedFromIsolate': true,
      if (posting != null) 'postReturned': returned,
    };
    results.add(entry);
    log(
      '${ok ? 'OK  ' : 'FAIL'} $cmd${dialog ? ' (dialog)' : ''}: result ${result?['success']}${appliedByState ? ' (applied: the state shows the value)' : ''}'
      '${windows.isEmpty ? '' : ', window ${entry['windowOpened']}'}'
      ', STATE_CHANGED ${state.isEmpty ? 'none' : '${state.length}x, last "${state.last}"'}'
      '${done == null ? ' (no answer within 8 s)' : ''}',
    );
  }
  File(
    '$out/item9_ribbon_${docName.replaceAll('.', '_')}${opts['tag'] ?? ''}.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  final failed = results
      .where((r) => r['ok'] != true)
      .map((r) => r['command'])
      .toList();
  final noState = results
      .where((r) => r['stateChanged'] == null)
      .map((r) => r['command'])
      .toList();
  log(
    'SUMMARY ${results.length} commands, ${results.length - failed.length} ok; failed: $failed',
  );
  log('SUMMARY no STATE_CHANGED for: $noState');
  doc.destroy();
  office.destroy();
  log('RESULT ribbon done');
}

// ignore: unused_element
String _json(Object o) => jsonEncode(o);
