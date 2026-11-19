// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The editor against the real helper from the binaries layer
/// (`$TOM_BINARY_PATH/<platform>/tom_office_host`) and the installed
/// LibreOffice. Tagged `libreoffice`; skipped where either or the sample set
/// is missing.
///
/// `TOM_OFFICE_SAMPLES`: the sample set's `files/` (default: the tom_forge
/// quest's `office_and_pdf_integration_prototype/samples/files`).
@Tags(['libreoffice'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_office_editor/io.dart';
import 'package:tom_office_editor/tom_office_editor.dart';

final _samples =
    Platform.environment['TOM_OFFICE_SAMPLES'] ??
    p.normalize(
      '${Directory.current.path}/../../../_ai/quests/tom_forge/ideas/'
      'office_and_pdf_integration_prototype/samples/files',
    );

class _Host implements TomOfficeEditorHost {
  _Host(this.filePath, this.helper);

  @override
  final String filePath;

  @override
  String get name => p.basename(filePath);

  @override
  final TomBinaryFiles files = TomBinaryFileAccess();

  @override
  final TomOfficeHelperLauncher helper;

  final notices = <String>[];

  @override
  void notice(BuildContext context, String message, {required String kind}) =>
      notices.add('$kind: $message');

  @override
  void openLink(String url) {}

  @override
  void historyChanged() {}
}

/// Waits (in real time) until [done] holds.
Future<void> _until(
  bool Function() done,
  String what, {
  int seconds = 90,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('no $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// What the saved file holds, from its XML parts.
String _contents(String path) {
  final ext = p.extension(path);
  final part = switch (ext) {
    '.docx' => 'word/document.xml',
    '.xlsx' => 'xl/sharedStrings.xml',
    '.pptx' => 'ppt/slides/slide1.xml',
    _ => throw ArgumentError(ext),
  };
  return Process.runSync('unzip', ['-p', path, part]).stdout as String;
}

void main() {
  final helper = TomOfficeProcessLauncher.findHelper();
  late LibreOfficeInstallation installation;
  late Directory scratch;

  setUpAll(() async {
    installation = await TomLibreOfficeDetector(useSpotlight: false).detect();
  });

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('office-editor-it-');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  String? skip() {
    if (helper == null) return 'no tom_office_host in \$TOM_BINARY_PATH';
    if (!File('$_samples/report.docx').existsSync()) {
      return 'the sample set is not at $_samples';
    }
    return null;
  }

  for (final (sample, marker) in [
    ('letter.docx', 'OEDOCX'),
    ('sheet.xlsx', 'OEXLSX'),
    ('deck.pptx', 'OEPPTX'),
  ]) {
    testWidgets('OE-IT-${p.extension(sample).substring(1).toUpperCase()}: '
        '$sample opens, renders, takes typing, saves and reopens', (
      tester,
    ) async {
      final reason = skip();
      if (reason != null) {
        markTestSkipped(reason);
        return;
      }
      if (!installation.isUsable) {
        markTestSkipped('LibreOffice: $installation');
        return;
      }
      await tester.runAsync(() async {
        final path = File(
          '$_samples/$sample',
        ).copySync(p.join(scratch.path, sample)).path;
        final launcher = TomOfficeProcessLauncher(
          installation: installation,
          helperExecutable: helper!,
          workRoot: p.join(scratch.path, 'office-host'),
        );
        final host = _Host(path, launcher);
        final c = TomOfficeEditorController(host: host);
        await c.open();
        await _until(
          () => c.state == TomOfficeEditorState.open,
          'open (${c.state} ${c.error})',
          seconds: 120,
        );
        // The first tiles.
        final visible = {
          for (var col = 0; col < 3; col++)
            for (var row = 0; row < 3; row++)
              TileKey(c.tilePart, 100, col, row),
        };
        c.showTiles(visible, zoom: 100, devicePixelRatio: 1);
        await _until(
          () => visible.every((k) => c.tiles.peek(k) != null),
          'tiles',
        );
        // Into editable text.
        switch (c.docType) {
          case OfficeDocType.spreadsheet:
            c.mouse(OfficeMouseEventType.down, 500, 4500);
            c.mouse(OfficeMouseEventType.up, 500, 4500);
          case OfficeDocType.presentation:
            c.key(VclKey.tab); // the first shape
            c.key(VclKey.enter); // its text
          default:
            break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        c.typeText('$marker ');
        if (c.docType == OfficeDocType.spreadsheet) c.key(VclKey.enter);
        if (c.docType == OfficeDocType.presentation) c.key(VclKey.escape);
        await _until(() => c.isDirty, 'ModifiedStatus=true');
        // The visible tiles were asked for again after the input.
        await _until(
          () => visible.every((k) => !(c.tiles.peek(k)?.stale ?? true)),
          'repainted tiles',
        );
        expect(await c.save(), TomOfficeSaveOutcome.saved);
        expect(c.isDirty, isFalse);
        expect(_contents(path), contains(marker));
        expect(
          scratch.listSync().map((e) => p.basename(e.path)),
          isNot(contains(startsWith('.$sample.tom-save'))),
        );
        await c.close();
        // Reopened: the saved file loads.
        final again = TomOfficeEditorController(host: host);
        await again.open();
        await _until(
          () => again.state == TomOfficeEditorState.open,
          'reopen (${again.state} ${again.error})',
          seconds: 120,
        );
        expect(again.isReadOnly, isFalse);
        await again.close();
        expect(host.notices, isEmpty);
        c.dispose();
        again.dispose();
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
