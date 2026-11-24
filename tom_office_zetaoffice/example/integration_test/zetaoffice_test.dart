// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// ZetaOffice in the webview on mbp: a DOCX, an XLSX and a PPTX open in
/// `TomZetaOfficeView`, are edited, saved and reopened with the change; the
/// second open reuses the cached files. The first run downloads ZetaOffice
/// (52.5 MB) into the cache after tapping the prompt's button.
///
/// ```sh
/// cd tom_ai/modules/tom_office_zetaoffice/example
/// flutter test integration_test/zetaoffice_test.dart -d macos
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tom_office_zetaoffice/tom_office_zetaoffice.dart';
import 'package:tom_office_zetaoffice_example/main.dart';

void _step(String what) => debugPrint('[ZETA-IT] $what');

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what, {
  int seconds = 30,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('no $what');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs [future] to its end while pumping.
Future<T> _drive<T>(
  WidgetTester tester,
  Future<T> future,
  String what, {
  int seconds = 120,
}) async {
  var done = false;
  late T value;
  Object? error;
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  await _until(tester, () => done, what, seconds: seconds);
  if (error != null) throw error!;
  return value;
}

/// The text of every part of the zip at [path].
Future<String> _zipText(WidgetTester tester, String path) async {
  final result = await tester.runAsync(
    () => Process.run('unzip', ['-p', path], stdoutEncoding: latin1),
  );
  return result!.stdout as String;
}

/// Opens [sample] in ZetaOffice and waits until the document shows.
Future<TomZetaOfficeController> _open(
  WidgetTester tester,
  ZetaOfficeExamplePageState page,
  Future<void> Function() open,
) async {
  unawaited(open());
  await _until(tester, () => page.zeta != null, 'controller');
  final z = page.zeta!;
  z.notices.listen((n) => _step('notice ${n.kind}: ${n.message}'));
  await _until(
    tester,
    () => z.state != TomZetaOfficeState.checking,
    'cache check',
  );
  if (z.state == TomZetaOfficeState.needsDownload) {
    _step('download prompt: ${z.downloadSize} bytes');
    await tester.tap(find.byKey(const ValueKey('zeta-download')));
    await _until(
      tester,
      () =>
          z.state != TomZetaOfficeState.downloading &&
          z.state != TomZetaOfficeState.needsDownload,
      'download',
      seconds: 900,
    );
  }
  await _until(
    tester,
    () =>
        z.state == TomZetaOfficeState.open ||
        z.state == TomZetaOfficeState.failed,
    'document (status ${z.statusText})',
    seconds: 240,
  );
  if (z.state == TomZetaOfficeState.failed) {
    fail('ZetaOffice failed: ${z.error}');
  }
  _step('open: ${z.kind} ${z.product}, cache reused ${z.cacheReused}');
  return z;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The [ZO] trail in the log.
  kZetaOfficeDebug = true;
  // `--dart-define=ZETA_SAMPLES=deck.pptx` runs one sample.
  const only = String.fromEnvironment('ZETA_SAMPLES');
  final samples = only.isEmpty
      ? ['report.docx', 'sheet.xlsx', 'deck.pptx']
      : only.split(',');

  testWidgets('ZO-IT: DOCX, XLSX and PPTX edited, saved and reopened in '
      'ZetaOffice', (tester) async {
    await tester.pumpWidget(const ZetaOfficeExampleApp());
    final page = tester.state<ZetaOfficeExamplePageState>(
      find.byType(ZetaOfficeExamplePage),
    );

    var first = true;
    for (final sample in samples) {
      _step('--- $sample');
      final marker = 'ZETA${sample.split('.').first.toUpperCase()}MARK';
      var z = await _open(tester, page, () => page.openSample(sample));
      if (!first) expect(z.cacheReused, isTrue, reason: '$sample: cache');
      first = false;
      final path = page.filePath!;
      expect(await _zipText(tester, path), isNot(contains(marker)));

      await _drive(tester, z.editForTest(marker), 'edit');
      await _until(tester, () => z.isDirty, 'dirty', seconds: 60);
      final outcome = await _drive(tester, z.save(), 'save', seconds: 180);
      _step('save: $outcome');
      expect(outcome.name, 'saved', reason: '$sample: save');
      await _until(tester, () => !z.isDirty, 'clean after save');
      expect(
        await _zipText(tester, path),
        contains(marker),
        reason: '$sample: the file holds the change',
      );

      z = await _open(tester, page, page.reopen);
      expect(z.cacheReused, isTrue, reason: '$sample: reopen uses the cache');
      final text = await _drive(tester, z.readForTest(), 'read');
      expect(text, contains(marker), reason: '$sample: reopened with it');
      _step('$sample ok');
    }
    await _drive(tester, page.zeta!.close(), 'close');
  }, timeout: const Timeout(Duration(minutes: 40)));

  testWidgets('ZO-IT-2: a save ZetaOffice cannot do (letter.docx as DOCX) is '
      'reported and leaves the document dirty and the file as it was', (
    tester,
  ) async {
    if (only.isNotEmpty && !only.contains('letter.docx')) return;
    await tester.pumpWidget(const ZetaOfficeExampleApp());
    final page = tester.state<ZetaOfficeExamplePageState>(
      find.byType(ZetaOfficeExamplePage),
    );
    final z = await _open(tester, page, () => page.openSample('letter.docx'));
    final path = page.filePath!;
    final before = File(path).readAsBytesSync();
    await _drive(tester, z.editForTest('ZETALETTERMARK'), 'edit');
    await _until(tester, () => z.isDirty, 'dirty', seconds: 60);
    final outcome = await _drive(tester, z.save(), 'save', seconds: 180);
    _step('letter save: $outcome');
    expect(outcome.name, 'failed');
    await tester.pump();
    expect(z.isDirty, isTrue, reason: 'still dirty');
    expect(File(path).readAsBytesSync(), before, reason: 'file untouched');
    await _drive(tester, z.close(), 'close');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
