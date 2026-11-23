// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The helper against a real LibreOffice: `dart run bin/tom_office_host.dart`
/// serving protocol 1. Tagged `libreoffice`; skipped where LibreOffice or the
/// sample set is missing.
///
/// - `TOM_LIBREOFFICE_PROGRAM`: the program folder (default
///   `/Applications/LibreOffice.app/Contents/Frameworks`).
/// - `TOM_OFFICE_SAMPLES`: the sample set's `files/` (default: the tom_forge
///   quest's `office_and_pdf_integration_prototype/samples/files`).
@Tags(['libreoffice'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

final _program =
    Platform.environment['TOM_LIBREOFFICE_PROGRAM'] ??
    '/Applications/LibreOffice.app/Contents/Frameworks';
final _samples =
    Platform.environment['TOM_OFFICE_SAMPLES'] ??
    '${Directory.current.path}/../../../_ai/quests/tom_forge/ideas/'
        'office_and_pdf_integration_prototype/samples/files';

String? get _skip {
  if (!File('$_program/libmergedlo.dylib').existsSync() &&
      !File('$_program/libmergedlo.so').existsSync()) {
    return 'LibreOffice is not installed at $_program';
  }
  if (!File('$_samples/letter.docx').existsSync()) {
    return 'the sample set is not at $_samples';
  }
  return null;
}

const _codec = OfficeProtocolCodec();

/// One helper process and what it sent.
class Helper {
  Helper._(this.process, this.profile) {
    process.stdout.listen((chunk) {
      for (final m in reader.add(chunk)) {
        received.add(m);
        _arrived.add(m);
      }
    });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(log.add);
  }

  static Future<Helper> start(Directory scratch) async {
    final profile = scratch.createTempSync('profile-');
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/tom_office_host.dart',
      '--program',
      _program,
      '--profile',
      profile.uri.toString(),
      '--protocol',
      '$kOfficeProtocolVersion',
    ]);
    return Helper._(process, profile);
  }

  final Process process;
  final Directory profile;
  final reader = OfficeFrameReader(_codec);
  final received = <OfficeMessage>[];
  final _arrived = StreamController<OfficeMessage>.broadcast(sync: true);
  final log = <String>[];
  var _ids = 100;

  int get nextId => _ids++;

  void send(OfficeHelperCommand m) => process.stdin.add(_codec.encode(m));

  Future<T> next<T extends OfficeMessage>({
    bool Function(T m)? where,
    Duration timeout = const Duration(seconds: 60),
  }) {
    bool ok(OfficeMessage m) => m is T && (where == null || where(m));
    final seen = received.where(ok);
    if (seen.isNotEmpty) {
      final m = seen.first;
      received.remove(m);
      return Future.value(m as T);
    }
    return _arrived.stream
        .firstWhere(ok)
        .then((m) {
          received.remove(m);
          return m as T;
        })
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'no ${T.toString()} in $timeout; stderr:\n${log.join('\n')}',
          ),
        );
  }

  Future<OfficeOpened> open(String path) async {
    final hello = await next<OfficeHello>(timeout: const Duration(minutes: 2));
    OfficeProtocolCodec.checkHello(hello);
    send(OfficeOpen(path: path, language: 'en-US'));
    return next<OfficeOpened>();
  }

  Future<OfficeTile> tile() async {
    final id = nextId;
    send(
      OfficeRenderTile(
        id: id,
        part: 0,
        x: 0,
        y: 0,
        w: 7680,
        h: 7680,
        pxW: 512,
        pxH: 512,
      ),
    );
    return next<OfficeTile>(where: (t) => t.id == id);
  }

  /// Types [text] and waits until LibreOffice reports the document
  /// modified. (`INVALIDATE_TILES` does not follow edits: first spike,
  /// item 4.)
  Future<void> typeText(String text) async {
    received.removeWhere((m) => m is OfficeCallback);
    for (final rune in text.runes) {
      send(
        OfficeKey(type: OfficeKeyEventType.down, charCode: rune, keyCode: 0),
      );
      send(OfficeKey(type: OfficeKeyEventType.up, charCode: rune, keyCode: 0));
    }
    await next<OfficeCallback>(
      where: (c) => c.payload == '.uno:ModifiedStatus=true',
    );
  }

  Future<OfficeSaved> save(
    String target, {
    String format = '',
    bool keepPassword = true,
  }) async {
    final id = nextId;
    send(
      OfficeSave(
        id: id,
        targetPath: target,
        format: format,
        keepPassword: keepPassword,
      ),
    );
    return next<OfficeSaved>(where: (s) => s.id == id);
  }

  Future<int> close() async {
    send(const OfficeClose());
    await next<OfficeClosed>();
    return process.exitCode.timeout(const Duration(seconds: 30));
  }
}

/// The share of pixels that differ from the tile's most common one.
double _ink(List<int> px) {
  final counts = <int, int>{};
  for (var i = 0; i + 3 < px.length; i += 4) {
    final v = px[i] | px[i + 1] << 8 | px[i + 2] << 16;
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final n = px.length ~/ 4;
  final top = counts.values.fold(0, (a, b) => a > b ? a : b);
  return n == 0 ? 0 : (n - top) / n;
}

int _diff(List<int> a, List<int> b) {
  var d = 0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) d++;
  }
  return d;
}

/// The text of a DOCX's body (`unzip -p`).
String _docxText(String path) =>
    Process.runSync('unzip', ['-p', path, 'word/document.xml']).stdout
        as String;

/// Whether [path] is an OLE compound file (an encrypted OOXML document).
bool _encrypted(String path) {
  final head = File(path).openSync()..setPositionSync(0);
  final bytes = head.readSync(4);
  head.closeSync();
  return bytes.length == 4 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0;
}

void main() {
  late Directory scratch;
  final helpers = <Helper>[];

  setUp(() {
    scratch = Directory('.dart_tool/test_scratch').absolute
      ..createSync(recursive: true);
    scratch = scratch.createTempSync('integration-');
  });

  tearDown(() async {
    for (final h in helpers) {
      h.process.kill(ProcessSignal.sigkill);
    }
    helpers.clear();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  Future<Helper> start() async {
    final h = await Helper.start(scratch);
    helpers.add(h);
    return h;
  }

  String copy(String name) =>
      File('$_samples/$name').copySync('${scratch.path}/$name').path;

  test(
    'OFFICE-HOST-LO-1: a DOCX opens, renders, takes typing and saves',
    () async {
      final h = await start();
      final path = copy('letter.docx');
      final opened = await h.open(path);
      expect(opened.docType, OfficeDocType.text);
      expect(opened.readOnly, isFalse);
      expect(opened.width, greaterThan(0));

      final before = await h.tile();
      expect(before.pixels.length, 512 * 512 * 4);
      expect(_ink(before.pixels), greaterThan(0.005), reason: 'a blank tile');

      await h.typeText('TOMHOSTTYPED ');
      final after = await h.tile();
      expect(_diff(before.pixels, after.pixels), greaterThan(0));

      final target = '${scratch.path}/.letter.docx.tom-save-1';
      h.received.removeWhere((m) => m is OfficeCallback);
      final saved = await h.save(target);
      expect(saved.ok, isTrue, reason: '${saved.error}');
      expect(_docxText(target), contains('TOMHOSTTYPED'));
      await h.next<OfficeCallback>(
        where: (c) => c.payload == '.uno:ModifiedStatus=false',
      );

      h.send(OfficePing(id: 7));
      expect((await h.next<OfficePong>()).id, 7);
      expect(await h.close(), 0);
      expect(h.profile.existsSync(), isFalse, reason: 'profile not deleted');
    },
    skip: _skip,
  );

  test('OFFICE-HOST-LO-2: a dialog opens as a window that paints, takes '
      'input and closes', () async {
    final h = await start();
    await h.open(copy('sheet.xlsx'));
    h.send(OfficeUno(id: h.nextId, command: '.uno:FormatCellDialog', args: ''));
    final w = await h.next<OfficeWindowOpened>(
      where: (w) => w.kind == 'dialog',
    );
    expect(w.width, greaterThan(100));
    expect(w.height, greaterThan(100));

    // The loop stays free while LibreOffice runs the dialog.
    h.send(OfficePing(id: 8));
    await h.next<OfficePong>();

    final id = h.nextId;
    h.send(
      OfficePaintWindow(
        id: id,
        windowId: w.windowId,
        x: 0,
        y: 0,
        w: w.width,
        h: w.height,
      ),
    );
    final px = await h.next<OfficeWindowPixels>(where: (p) => p.id == id);
    expect(px.pixels.length, w.width * w.height * 4);
    expect(_ink(px.pixels), greaterThan(0.01), reason: 'a blank dialog');

    h.send(
      OfficeWindowKey(
        windowId: w.windowId,
        type: OfficeKeyEventType.down,
        charCode: 0,
        keyCode: 1282, // KEY_TAB
      ),
    );
    h.send(
      OfficeWindowKey(
        windowId: w.windowId,
        type: OfficeKeyEventType.up,
        charCode: 0,
        keyCode: 1282,
      ),
    );
    h.send(OfficeWindowClose(windowId: w.windowId));
    await h.next<OfficeWindowChanged>(
      where: (c) => c.windowId == w.windowId && c.action == 'close',
    );
    expect(await h.close(), 0);
  }, skip: _skip);

  test('OFFICE-HOST-LO-3: a password-protected DOCX asks, refuses a wrong '
      'password, opens with the right one and stays encrypted on save; '
      'keepPassword false writes it unencrypted', () async {
    // Make the protected copy with LibreOffice's own Save As.
    final maker = await start();
    await maker.open(copy('letter.docx'));
    final protected = '${scratch.path}/protected.docx';
    maker.send(
      OfficeUno(
        id: maker.nextId,
        command: '.uno:SaveAs',
        args: jsonEncode({
          'URL': {'type': 'string', 'value': Uri.file(protected).toString()},
          'FilterName': {'type': 'string', 'value': 'MS Word 2007 XML'},
          'Password': {'type': 'string', 'value': 'tomsecret'},
        }),
      ),
    );
    await maker.next<OfficeCallback>(
      where: (c) =>
          c.type == 'UNO_COMMAND_RESULT' && c.payload.contains('.uno:SaveAs'),
    );
    expect(await maker.close(), 0);
    expect(_encrypted(protected), isTrue, reason: 'the copy is not encrypted');

    final h = await start();
    await h.next<OfficeHello>(timeout: const Duration(minutes: 2));
    h.send(OfficeOpen(path: protected, language: 'en-US'));
    expect((await h.next<OfficePasswordNeeded>()).toModify, isFalse);
    h.send(const OfficePassword(password: 'wrong'));
    expect((await h.next<OfficePasswordNeeded>()).toModify, isFalse);
    h.send(const OfficePassword(password: 'tomsecret'));
    expect((await h.next<OfficeOpened>()).docType, OfficeDocType.text);

    await h.typeText('ENCRYPTEDEDIT ');
    final target = '${scratch.path}/.protected.docx.tom-save-1';
    final saved = await h.save(target);
    expect(saved.ok, isTrue, reason: '${saved.error}');
    expect(_encrypted(target), isTrue, reason: 'the save dropped encryption');
    // The unencrypted copy the user may choose instead.
    final plain = '${scratch.path}/.protected.docx.tom-save-2';
    final copied = await h.save(plain, keepPassword: false);
    expect(copied.ok, isTrue, reason: '${copied.error}');
    expect(_encrypted(plain), isFalse, reason: 'the copy is still encrypted');
    expect(h.log.join('\n'), isNot(contains('tomsecret')));
    expect(await h.close(), 0);
  }, skip: _skip);

  test('OFFICE-HOST-LO-4: a CSV file opens with its filter options and saves '
      'with others', () async {
    final csv = File('${scratch.path}/data.csv')
      ..writeAsStringSync('name;amount\nAnna;1,5\nBob;2\n');
    final h = await Helper.start(scratch);
    final hello = await h.next<OfficeHello>(
      timeout: const Duration(minutes: 2),
    );
    OfficeProtocolCodec.checkHello(hello);
    h.send(
      OfficeOpen(
        path: csv.path,
        language: 'en-US',
        filterOptions: '59,34,76,1',
      ),
    );
    final opened = await h.next<OfficeOpened>();
    expect(opened.docType, OfficeDocType.spreadsheet);
    final target = '${scratch.path}/.data.csv.tom-save-1';
    final id = h.nextId;
    h.send(
      OfficeSave(
        id: id,
        targetPath: target,
        format: 'csv',
        filterOptions: '44,34,76,1,,0,false',
      ),
    );
    final saved = await h.next<OfficeSaved>(where: (s) => s.id == id);
    expect(saved.ok, isTrue, reason: '${saved.error}');
    expect(
      File(target).readAsStringSync(),
      'name,amount\nAnna,"1,5"\nBob,2\n',
      reason: 'the semicolons were read as separators, the commas written',
    );
    expect(await h.close(), 0);
  }, skip: _skip);
}
