/// How a sync state reads to a person.
///
/// A pure value, computed by a pure function, separate from the widget that
/// shows it. Every line here is a claim the user will act on — "offline",
/// "3 pending changes", "2 conflicts" — and a claim that can be wrong should be
/// testable without pumping a frame.
library;

import 'package:flutter/material.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_core_sync/tom_core_sync.dart';

/// How much a state wants from the user, which is what the colour encodes.
enum TomSyncTone {
  /// Nothing to do.
  idle,

  /// Something is moving on its own.
  working,

  /// Not converged, and it will not converge unaided.
  attention,

  /// Needs a person.
  problem,
}

/// One unreachable storage location and the work waiting for it, as a rollup
/// names it.
class TomOfflineLocation {
  /// The location as the user knows it, e.g. `owner/repo`.
  final String label;

  /// Commits queued for it.
  final int pendingCount;

  const TomOfflineLocation({required this.label, required this.pendingCount});
}

/// Everything the presentation needs to know about one scope — one unit, one
/// storage location, or a workspace — already reduced to counts.
class TomSyncSummary {
  /// What the scope is called in a tooltip: "This document", "3 documents".
  final String scope;

  final TomSyncState state;
  final bool offline;

  /// Commits journaled and awaiting delivery.
  final int pendingCount;

  final int conflictCount;

  /// Containers the configured keys do not open.
  final int keyRequiredCount;

  /// Units whose offline work this device could not queue.
  final int unqueuedCount;

  final DateTime? rateLimitedUntil;
  final TomRateLimitKind? rateLimitKind;
  final DateTime? lastSyncedAt;

  /// The in-flight commit, when exactly one unit is uploading.
  final TomCommitProgress? commitProgress;

  /// How many units are uploading.
  final int uploadingCount;

  /// The unreachable locations of a rollup; two or more are named one by one.
  final List<TomOfflineLocation> offlineLocations;

  /// For a rollup, how many units have unsynced changes; null for one unit.
  final int? unsyncedCount;

  /// What a unit is called, singular and plural: "document", "documents".
  final String noun;
  final String nounPlural;

  /// The application's name, for the one line that asks the user to keep it
  /// open.
  final String applicationName;

  const TomSyncSummary({
    required this.scope,
    required this.state,
    this.offline = false,
    this.pendingCount = 0,
    this.conflictCount = 0,
    this.keyRequiredCount = 0,
    this.unqueuedCount = 0,
    this.rateLimitedUntil,
    this.rateLimitKind,
    this.lastSyncedAt,
    this.commitProgress,
    this.uploadingCount = 0,
    this.offlineLocations = const [],
    this.unsyncedCount,
    this.noun = 'document',
    this.nounPlural = 'documents',
    this.applicationName = 'the application',
  });

  /// The summary of one unit's [status].
  factory TomSyncSummary.ofStatus(
    TomSyncStatus status, {
    required String scope,
    String noun = 'document',
    String nounPlural = 'documents',
    String applicationName = 'the application',
  }) => TomSyncSummary(
    scope: scope,
    state: status.state,
    offline: status.offline,
    pendingCount: status.pendingCount,
    conflictCount: status.conflicts.length,
    keyRequiredCount: status.needsKey ? 1 : 0,
    unqueuedCount: status.isUnqueued ? 1 : 0,
    rateLimitedUntil: status.rateLimitedUntil,
    rateLimitKind: status.rateLimitKind,
    lastSyncedAt: status.lastSyncedAt,
    commitProgress: status.commitProgress,
    uploadingCount: status.commitProgress == null ? 0 : 1,
    noun: noun,
    nounPlural: nounPlural,
    applicationName: applicationName,
  );

  /// "1 document", "3 documents".
  String count(int n) => n == 1 ? '1 $noun' : '$n $nounPlural';
}

/// The icon, label and tooltip for one sync state.
class TomSyncPresentation {
  final IconData icon;

  /// The short form for a status line.
  final String label;

  /// The long form, with the detail the short form had to drop.
  final String tooltip;

  final TomSyncTone tone;

  /// Whether activating the indicator should open the conflict review.
  final bool opensMergeView;

  /// Whether activating the indicator should open the key prompt.
  ///
  /// Mutually exclusive with [opensMergeView] by construction — the branch
  /// order picks exactly one.
  final bool opensKeyPrompt;

  /// How far the in-flight commit has got, in `[0, 1]`, or null when nothing
  /// is on the wire. Rendered as a ring in place of [icon].
  final double? progress;

  const TomSyncPresentation({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.tone,
    this.opensMergeView = false,
    this.opensKeyPrompt = false,
    this.progress,
  });

  /// The one mapping, for every scope.
  ///
  /// The order of the branches is the design. A key-blocked container comes
  /// first because it is the only state in which the loop has stopped, so
  /// every other claim would be stale. Work that exists only in the open
  /// window comes next, then a conflict — the remaining state that will not
  /// resolve itself. An upload in flight and a running cycle come before
  /// `offline`, whose flag on a running cycle is the previous cycle's verdict.
  /// `offline` precedes a rate limit: for one unit they cannot co-occur, and
  /// across a rollup an outage is something the user can act on and a wait is
  /// not.
  factory TomSyncPresentation.of(TomSyncSummary s) {
    final since = s.lastSyncedAt == null
        ? 'Never synced'
        : 'Last synced ${_stamp(s.lastSyncedAt!)}';
    final pending = s.pendingCount == 1
        ? '1 pending change'
        : '${s.pendingCount} pending changes';

    if (s.keyRequiredCount > 0) {
      final files = s.keyRequiredCount == 1
          ? '1 file'
          : '${s.keyRequiredCount} files';
      return TomSyncPresentation(
        icon: Icons.key_off_outlined,
        label: s.keyRequiredCount == 1 ? 'Key required' : '$files need a key',
        tooltip:
            '${s.scope}: $files cannot be opened with the configured keys, so '
            'syncing is paused before merge. Click to supply the key.',
        tone: TomSyncTone.problem,
        opensKeyPrompt: true,
      );
    }

    if (s.unqueuedCount > 0) {
      final units = s.unqueuedCount == 1
          ? 'This ${s.noun} has'
          : '${s.unqueuedCount} ${s.nounPlural} have';
      return TomSyncPresentation(
        icon: Icons.save_as_outlined,
        label: 'Changes not saved on this device',
        tooltip:
            '${s.scope}: offline, and this device could not store the changes '
            'for later. $units changes that exist only in the open window; '
            'they are sent when the remote can be reached. Keep '
            '${s.applicationName} open until then.',
        tone: TomSyncTone.problem,
      );
    }

    if (s.state == TomSyncState.conflicted) {
      final conflicts = s.conflictCount == 1
          ? '1 conflict'
          : '${s.conflictCount} conflicts';
      return TomSyncPresentation(
        icon: Icons.merge_type,
        label: conflicts,
        tooltip:
            '${s.scope}: $conflicts to resolve. Click to open the merge view.',
        tone: TomSyncTone.problem,
        opensMergeView: true,
      );
    }

    if (s.uploadingCount > 1) {
      return TomSyncPresentation(
        icon: Icons.cloud_upload,
        label: 'Saving ${s.count(s.uploadingCount)}',
        tooltip:
            '${s.scope}: ${s.count(s.uploadingCount)} are uploading. $since.',
        tone: TomSyncTone.working,
      );
    }

    final progress = s.commitProgress;
    if (progress != null) {
      final detail = _uploadDetail(progress);
      return TomSyncPresentation(
        icon: Icons.cloud_upload,
        label: 'Saving — $detail',
        tooltip:
            '${s.scope}: uploading $detail. Nothing is visible to anyone '
            'else until the whole save lands.',
        tone: TomSyncTone.working,
        progress: progress.fraction,
      );
    }

    if (s.state == TomSyncState.syncing) {
      return TomSyncPresentation(
        icon: Icons.sync,
        label: 'Syncing…',
        tooltip: '${s.scope}: sync in progress. $since.',
        tone: TomSyncTone.working,
      );
    }

    if (s.offline) {
      final several = s.offlineLocations.length >= 2;
      final where = several
          ? '${s.offlineLocations.map(_offlineLine).join('; ')}. '
          : '';
      final unreachable = several
          ? '${s.offlineLocations.length} storage locations are unreachable'
          : 'the remote is unreachable';
      return TomSyncPresentation(
        icon: Icons.cloud_off_outlined,
        label: s.pendingCount > 0 ? 'Offline — $pending' : 'Offline',
        tooltip:
            '${s.scope}: $unreachable. $where'
            '${s.pendingCount > 0 ? '$pending queued. ' : ''}$since.',
        tone: TomSyncTone.attention,
      );
    }

    final until = s.rateLimitedUntil;
    if (until != null) {
      return _rateLimited(
        until: until,
        kind: s.rateLimitKind,
        scope: s.scope,
        since: since,
      );
    }

    if (s.state == TomSyncState.dirty) {
      // A rollup counts units rather than changes: it sits beside the active
      // unit's own indicator, which already says how many changes it holds.
      final unsynced = s.unsyncedCount;
      if (unsynced != null) {
        final units = s.count(unsynced);
        final queued = s.pendingCount > 0 ? ' $pending in all.' : '';
        return TomSyncPresentation(
          icon: Icons.cloud_upload_outlined,
          label: '$units unsynced',
          tooltip:
              '${s.scope}: $units with changes waiting for the next '
              'cycle.$queued $since.',
          tone: TomSyncTone.idle,
        );
      }
      return TomSyncPresentation(
        icon: Icons.cloud_upload_outlined,
        label: s.pendingCount > 0 ? pending : 'Unsynced changes',
        tooltip: '${s.scope}: changes are waiting for the next cycle. $since.',
        tone: TomSyncTone.idle,
      );
    }

    return TomSyncPresentation(
      icon: Icons.cloud_done_outlined,
      label: 'Synced',
      tooltip: '${s.scope}: up to date. $since.',
      tone: TomSyncTone.idle,
    );
  }

  /// `owner/repo: offline — 2 pending changes`.
  static String _offlineLine(TomOfflineLocation location) {
    final n = location.pendingCount;
    final pending = n == 0
        ? ''
        : ' — ${n == 1 ? '1 pending change' : '$n pending changes'}';
    return '${location.label}: offline$pending';
  }

  /// The one line for a rate-limited remote, in three renderings because the
  /// three limits are three situations: a quota's reset is the backend's fact
  /// and is named; a throttle clears within about a minute at an instant this
  /// side chose, so no time is claimed; a block's time is an estimate, marked
  /// with `~`. A limit of no stated kind reads as a quota.
  static TomSyncPresentation _rateLimited({
    required DateTime until,
    required TomRateLimitKind? kind,
    required String scope,
    required String since,
  }) {
    switch (kind) {
      case TomRateLimitKind.throttle:
        return TomSyncPresentation(
          icon: Icons.hourglass_top,
          label: 'Throttled — retrying',
          tooltip:
              '$scope: the remote is throttling our request rate. '
              'Polling backs off and resumes on its own, shortly. $since.',
          tone: TomSyncTone.attention,
        );
      case TomRateLimitKind.blocked:
        return TomSyncPresentation(
          icon: Icons.hourglass_bottom,
          label: 'Blocked until ~${_stamp(until)}',
          tooltip:
              '$scope: the remote has blocked us for issuing too many '
              'requests at once. Polling resumes around ${_stamp(until)} — '
              'the time is our estimate, not the remote\'s. $since.',
          tone: TomSyncTone.attention,
        );
      case TomRateLimitKind.quota:
      case null:
        return TomSyncPresentation(
          icon: Icons.hourglass_bottom,
          label: 'Paused until ${_stamp(until)}',
          tooltip:
              '$scope: the remote is rate-limiting us; polling resumes at '
              '${_stamp(until)}. $since.',
          tone: TomSyncTone.attention,
        );
    }
  }

  /// What the line says about an upload: the object in flight and, for a
  /// multi-object commit, how far along; "finishing" once the objects are up.
  static String _uploadDetail(TomCommitProgress progress) {
    final path = progress.currentPath;
    if (path == null) return 'finishing';
    final size = '${(progress.currentBytes / 1000000).toStringAsFixed(1)} MB';
    if (progress.objectsTotal <= 1) return '$path ($size)';
    return '$path, '
        '${progress.objectsCompleted + 1} of ${progress.objectsTotal}';
  }

  /// Resolves [tone] against a theme.
  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      TomSyncTone.idle => scheme.onSurfaceVariant,
      TomSyncTone.working => scheme.primary,
      TomSyncTone.attention => scheme.tertiary,
      TomSyncTone.problem => scheme.error,
    };
  }

  static String _stamp(DateTime at) {
    final local = at.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
