/// Running a change outside a frame that is being built.
///
/// A notifier fired from inside a build, a layout or a tree finalization — a
/// state's `dispose` that cancels a run, an editor's own notifier reporting
/// its selection — would mark widgets dirty while the tree is locked, which
/// Flutter treats as an error and then leaves the dirty widget unbuilt.
library;

import 'package:flutter/scheduler.dart';

/// Runs [change] now, or after the frame when one is being built.
void tomRunAfterBuild(VoidCallback change) {
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks) {
    change();
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) => change());
}
