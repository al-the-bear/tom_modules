import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_core_sync/tom_core_sync.dart';
import 'package:tom_sync_ui/tom_sync_ui.dart';

TomSyncPresentation present({
  TomSyncState state = TomSyncState.clean,
  bool offline = false,
  int pending = 0,
  int conflicts = 0,
  int keys = 0,
  int unqueued = 0,
  DateTime? until,
  TomRateLimitKind? kind,
  TomCommitProgress? progress,
  int uploading = 0,
  List<TomOfflineLocation> locations = const [],
  int? unsynced,
}) => TomSyncPresentation.of(
  TomSyncSummary(
    scope: 'Here',
    state: state,
    offline: offline,
    pendingCount: pending,
    conflictCount: conflicts,
    keyRequiredCount: keys,
    unqueuedCount: unqueued,
    rateLimitedUntil: until,
    rateLimitKind: kind,
    commitProgress: progress,
    uploadingCount: uploading,
    offlineLocations: locations,
    unsyncedCount: unsynced,
    applicationName: 'App',
  ),
);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('SYNC-STATUS: one mapping from a sync state to a line', () {
    test('SYNC-STATUS-1: a locked container outranks everything and asks '
        'for the key', () {
      final p = present(
        keys: 2,
        state: TomSyncState.conflicted,
        conflicts: 3,
        offline: true,
      );
      expect(p.label, '2 files need a key');
      expect(p.opensKeyPrompt, isTrue);
      expect(p.opensMergeView, isFalse);
      expect(p.tone, TomSyncTone.problem);
      expect(present(keys: 1).label, 'Key required');
    });

    test('SYNC-STATUS-2: work held only in the window comes next, naming the '
        'application', () {
      final p = present(unqueued: 1, state: TomSyncState.conflicted);
      expect(p.label, 'Changes not saved on this device');
      expect(p.tooltip, contains('Keep App open'));
      expect(p.tooltip, contains('This document has'));
    });

    test('SYNC-STATUS-3: a conflict opens the merge view', () {
      final p = present(state: TomSyncState.conflicted, conflicts: 1);
      expect(p.label, '1 conflict');
      expect(p.opensMergeView, isTrue);
    });

    test('SYNC-STATUS-4: an upload in flight shows its object and a ring; '
        'several uploads are counted', () {
      const progress = TomCommitProgress(
        objectsCompleted: 0,
        objectsTotal: 1,
        bytesCompleted: 0,
        bytesTotal: 2000000,
        currentPath: 'a.png',
        currentBytes: 2000000,
      );
      final one = present(
        state: TomSyncState.syncing,
        progress: progress,
        uploading: 1,
      );
      expect(one.label, 'Saving — a.png (2.0 MB)');
      expect(one.progress, isNotNull);
      expect(present(uploading: 3).label, 'Saving 3 documents');
    });

    test('SYNC-STATUS-5: a running cycle hides the previous verdict', () {
      final p = present(state: TomSyncState.syncing, offline: true);
      expect(p.label, 'Syncing…');
      expect(p.tone, TomSyncTone.working);
    });

    test('SYNC-STATUS-6: offline counts what waits, and names two or more '
        'locations one by one', () {
      expect(
        present(offline: true, pending: 2, state: TomSyncState.dirty).label,
        'Offline — 2 pending changes',
      );
      final p = present(
        offline: true,
        locations: const [
          TomOfflineLocation(label: 'a/b', pendingCount: 1),
          TomOfflineLocation(label: 'c/d', pendingCount: 0),
        ],
      );
      expect(p.tooltip, contains('2 storage locations are unreachable'));
      expect(p.tooltip, contains('a/b: offline — 1 pending change'));
    });

    test('SYNC-STATUS-7: three rate limits read three ways', () {
      final at = DateTime(2026, 1, 1, 14, 20);
      expect(
        present(until: at, kind: TomRateLimitKind.throttle).label,
        'Throttled — retrying',
      );
      expect(
        present(until: at, kind: TomRateLimitKind.blocked).label,
        'Blocked until ~14:20',
      );
      expect(
        present(until: at, kind: TomRateLimitKind.quota).label,
        'Paused until 14:20',
      );
      expect(
        present(until: at).label,
        'Paused until 14:20',
        reason: 'a limit of no stated kind reads as a quota',
      );
    });

    test('SYNC-STATUS-8: dirty counts changes for one unit and units for a '
        'rollup; clean reads synced', () {
      expect(present(state: TomSyncState.dirty).label, 'Unsynced changes');
      expect(
        present(state: TomSyncState.dirty, pending: 1).label,
        '1 pending change',
      );
      expect(
        present(state: TomSyncState.dirty, unsynced: 2).label,
        '2 documents unsynced',
      );
      expect(present().label, 'Synced');
      expect(present().tone, TomSyncTone.idle);
    });

    test('SYNC-STATUS-9: a summary of one status carries its facts', () {
      final status = TomSyncStatus(
        locator: 'x',
        state: TomSyncState.dirty,
        pendingCount: 1,
        conflicts: const [],
        offline: true,
        lastSyncedAt: null,
        lastError: null,
      );
      final p = TomSyncPresentation.of(
        TomSyncSummary.ofStatus(status, scope: 'This document'),
      );
      expect(p.label, 'Offline — 1 pending change');
      expect(p.tooltip, startsWith('This document: the remote is unreachable'));
    });
  });

  group('SYNC-INDICATOR: the widget', () {
    testWidgets('SYNC-INDICATOR-1: activating runs the action the state asks '
        'for, and nothing else', (tester) async {
      var merges = 0;
      var keys = 0;
      Future<void> pump(TomSyncPresentation p) => tester.pumpWidget(
        host(
          TomSyncIndicator(
            presentation: p,
            tapKey: const Key('tap'),
            onOpenMergeView: () => merges++,
            onOpenKeyPrompt: () => keys++,
          ),
        ),
      );
      await pump(present(state: TomSyncState.conflicted, conflicts: 1));
      await tester.tap(find.byKey(const Key('tap')));
      await pump(present(keys: 1));
      await tester.tap(find.byKey(const Key('tap')));
      await pump(present());
      await tester.tap(find.byKey(const Key('tap')));
      expect((merges, keys), (1, 1));
    });

    testWidgets('SYNC-INDICATOR-2: an upload draws a ring in place of the '
        'icon, and icon-only drops the label', (tester) async {
      await tester.pumpWidget(
        host(
          TomSyncIndicator(
            presentation: present(
              progress: const TomCommitProgress(
                objectsCompleted: 0,
                objectsTotal: 2,
                bytesCompleted: 0,
                bytesTotal: 10,
                currentPath: 'x',
                currentBytes: 5,
              ),
              uploading: 1,
            ),
            iconOnly: true,
          ),
        ),
      );
      expect(find.byKey(const Key('tom-sync-progress')), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('SYNC-INDICATOR-3: a long label gives way in a bounded row', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 80,
            child: TomSyncIndicator(
              presentation: present(
                offline: true,
                pending: 12,
                state: TomSyncState.dirty,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Offline'), findsOneWidget);
    });
  });
}
