// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/testing.dart';
import 'package:tom_office_editor/tom_office_editor.dart';
import 'package:tom_office_editor/zetaoffice.dart';

import 'support.dart';

/// Runs [future] to its end, pumping meanwhile: with the view's timers
/// running, a continuation in this test zone waits for a pump.
Future<T> _drive<T>(WidgetTester tester, Future<T> future) async {
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
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (error != null) throw error!;
  if (!done) throw StateError('did not complete');
  return value;
}

class _Tab {
  _Tab({
    TomZetaOfficeCacheState cache = TomZetaOfficeCacheState.missing,
    Duration saveTimeout = const Duration(seconds: 5),
    Duration startTimeout = const Duration(minutes: 3),
  }) : files = FakeZetaOfficeFiles(state: cache) {
    controller = TomZetaOfficeController(
      host: host,
      files: files,
      serving: serving,
      saveTimeout: saveTimeout,
      startTimeout: startTimeout,
    );
  }

  final host = TestHost();
  final FakeZetaOfficeFiles files;
  final serving = FakeZetaOfficeServing();
  final channel = FakeZetaOfficeChannel();
  late final TomZetaOfficeController controller;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TomZetaOfficeView(
            controller: controller,
            channelForTesting: channel,
          ),
        ),
      ),
    );
    await _drive(tester, controller.prepare());
    await tester.pump();
  }

  /// The page says the document is open.
  Future<void> loaded(WidgetTester tester) async {
    channel
      ..emit({'type': 'ready'})
      ..emit({
        'type': 'loaded',
        'kind': 'text',
        'product': 'ZetaOffice 24.2.8.0.beta1',
      });
    await tester.pump();
  }

  /// The page answers `save` as ZetaOffice does: posts [bytes], says saved,
  /// clears the modified flag.
  void answerSaves(List<int> bytes, {bool ok = true}) {
    channel.onCall = (function, args) async {
      if (function != 'save') return;
      if (ok) await serving.postSave(bytes);
      channel
        ..emit({
          'type': 'saved',
          'ok': ok,
          'copy': false,
          'error': ok ? null : 'RangeError',
        })
        ..emit({'type': 'modified', 'value': false});
    };
  }

  Future<void> close(WidgetTester tester) async {
    await _drive(tester, controller.close());
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump(const Duration(seconds: 2));
  }
}

void main() {
  testWidgets('ZO-1: the download prompt names the size; confirming '
      'downloads once and starts', (tester) async {
    final tab = _Tab();
    await tab.pump(tester);
    expect(tab.controller.state, TomZetaOfficeState.needsDownload);
    expect(find.textContaining('52.5 MB'), findsWidgets);
    expect(find.textContaining('cdn.zetaoffice.net'), findsOneWidget);
    expect(tab.serving.starts, 0, reason: 'nothing served before the yes');
    await tester.tap(find.byKey(const ValueKey('zeta-download')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(tab.files.downloads, 1);
    expect(tab.controller.state, TomZetaOfficeState.starting);
    expect(tab.channel.loaded, [FakeZetaOfficeServing.page]);
    expect(find.byKey(const ValueKey('zeta-starting')), findsOneWidget);
    await tab.loaded(tester);
    expect(tab.controller.state, TomZetaOfficeState.open);
    expect(tab.files.product, 'ZetaOffice 24.2.8.0.beta1');
    await tab.close(tester);
  });

  testWidgets('ZO-2: a ready cache is reused; a damaged one is offered again', (
    tester,
  ) async {
    final ready = _Tab(cache: TomZetaOfficeCacheState.ready);
    await ready.pump(tester);
    expect(ready.controller.state, TomZetaOfficeState.starting);
    expect(ready.controller.cacheReused, isTrue);
    expect(ready.files.downloads, 0);
    expect(find.byKey(const ValueKey('zeta-download')), findsNothing);
    await ready.close(tester);

    final damaged = _Tab(cache: TomZetaOfficeCacheState.damaged);
    await damaged.pump(tester);
    expect(damaged.controller.state, TomZetaOfficeState.needsDownload);
    expect(find.byKey(const ValueKey('zeta-damaged')), findsOneWidget);
    await damaged.close(tester);
  });

  testWidgets('ZO-3: save posts the stored bytes into the file; dirty, undo '
      'and redo follow the page', (tester) async {
    final tab = _Tab(cache: TomZetaOfficeCacheState.ready);
    await tab.pump(tester);
    await tab.loaded(tester);
    tab.channel
      ..emit({'type': 'modified', 'value': true})
      ..emit({'type': 'history', 'canUndo': true, 'canRedo': false});
    await tester.pump();
    final c = tab.controller;
    expect((c.isDirty, c.canUndo, c.canRedo), (true, true, false));
    expect(tab.host.historyChanges, 2);
    await _drive(tester, c.undo());
    expect(tab.channel.calls.last, 'undo');
    tab.answerSaves(utf8.encode('stored by ZetaOffice'));
    expect(await _drive(tester, c.save()), TomOfficeSaveOutcome.saved);
    await tester.pump();
    expect(await _drive(tester, tab.host.text()), 'stored by ZetaOffice');
    expect(c.isDirty, isFalse);
    expect(tab.channel.calls, contains('save'));
    await tab.close(tester);
  });

  testWidgets('ZO-4: a failed save is reported and leaves the document dirty', (
    tester,
  ) async {
    final tab = _Tab(cache: TomZetaOfficeCacheState.ready);
    await tab.pump(tester);
    await tab.loaded(tester);
    tab.channel.emit({'type': 'modified', 'value': true});
    await tester.pump();
    tab.answerSaves(const [], ok: false);
    expect(
      await _drive(tester, tab.controller.save()),
      TomOfficeSaveOutcome.failed,
    );
    await tester.pump();
    expect(
      tab.controller.isDirty,
      isTrue,
      reason: 'even with the flag cleared',
    );
    expect(await tab.host.text(), 'original');
    expect(tab.host.notices.last.$1, 'error');
    await tab.close(tester);
  });

  testWidgets('ZO-5: a save without an answer times out, dirty', (
    tester,
  ) async {
    final tab = _Tab(
      cache: TomZetaOfficeCacheState.ready,
      saveTimeout: const Duration(seconds: 2),
    );
    await tab.pump(tester);
    await tab.loaded(tester);
    tab.channel.emit({'type': 'modified', 'value': true});
    await tester.pump();
    final outcome = tab.controller.save();
    await tester.pump(const Duration(seconds: 3));
    expect(await _drive(tester, outcome), TomOfficeSaveOutcome.failed);
    await tester.pump();
    expect(tab.controller.isDirty, isTrue);
    expect(tab.host.notices.last.$2, contains('did not answer'));
    await tab.close(tester);
  });

  testWidgets('ZO-6: a file changed on disk is not overwritten', (
    tester,
  ) async {
    final tab = _Tab(cache: TomZetaOfficeCacheState.ready);
    await tab.pump(tester);
    await tab.loaded(tester);
    tab.channel.emit({'type': 'modified', 'value': true});
    await tab.host.changeOnDisk('theirs');
    tab.answerSaves(utf8.encode('mine'));
    expect(
      await _drive(tester, tab.controller.save()),
      TomOfficeSaveOutcome.conflict,
    );
    await tester.pump();
    expect(await tab.host.text(), 'theirs');
    expect(tab.controller.conflict, isTrue);
    expect(tab.controller.isDirty, isTrue);
    expect(
      await _drive(tester, tab.controller.keepMine()),
      TomOfficeSaveOutcome.saved,
    );
    expect(await tab.host.text(), 'mine');
    await tab.close(tester);
  });

  testWidgets('ZO-7: Save as copy writes <name> (copy) beside the file', (
    tester,
  ) async {
    final tab = _Tab(cache: TomZetaOfficeCacheState.ready);
    await tab.pump(tester);
    await tab.loaded(tester);
    tab.channel.onCall = (function, args) async {
      if (function != 'saveCopy') return;
      await tab.serving.postCopy(utf8.encode('the copy'));
      tab.channel.emit({'type': 'saved', 'ok': true, 'copy': true});
    };
    final copy = await _drive(tester, tab.controller.saveAsCopy());
    expect(copy, '/docs/report (copy).docx');
    expect(await tab.host.fs.readText(tab.host.fs.uriOf(copy!)), 'the copy');
    expect(await tab.host.text(), 'original');
    await tab.close(tester);
  });

  testWidgets('ZO-8: one ZetaOffice tab at a time; a second one says so', (
    tester,
  ) async {
    final first = _Tab(cache: TomZetaOfficeCacheState.ready);
    await first.pump(tester);
    final second = _Tab(cache: TomZetaOfficeCacheState.ready);
    await second.pump(tester);
    expect(second.controller.state, TomZetaOfficeState.busy);
    expect(find.byKey(const ValueKey('zeta-busy')), findsOneWidget);
    await second.close(tester);
    await first.close(tester);
  });

  testWidgets('ZO-9: no isolation, a killed content process and a start that '
      'never ends are reported', (tester) async {
    var tab = _Tab(cache: TomZetaOfficeCacheState.ready);
    await tab.pump(tester);
    tab.channel.emit({
      'type': 'error',
      'code': 'notIsolated',
      'message': 'crossOriginIsolated is false',
    });
    await tester.pump();
    expect(tab.controller.state, TomZetaOfficeState.failed);
    expect(find.textContaining('cross-origin isolated'), findsOneWidget);
    await tab.close(tester);

    tab = _Tab(cache: TomZetaOfficeCacheState.ready);
    await tab.pump(tester);
    await tab.loaded(tester);
    tab.controller.contentProcessGone();
    await tester.pump();
    expect(find.byKey(const ValueKey('zeta-process-gone')), findsOneWidget);
    expect(tab.controller.isDirty, isFalse);
    await tab.close(tester);

    tab = _Tab(
      cache: TomZetaOfficeCacheState.ready,
      startTimeout: const Duration(seconds: 3),
    );
    await tab.pump(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(tab.controller.state, TomZetaOfficeState.failed);
    expect(tab.controller.error, contains('did not show the document'));
    await tab.close(tester);
  });
}
