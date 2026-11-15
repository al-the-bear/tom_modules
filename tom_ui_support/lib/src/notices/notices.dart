/// The one way an application's surface shows a notice.
///
/// A notice says something and goes away. Two Flutter defaults work against
/// that: a snack bar that carries an action stays until it is pressed, and
/// snack bars queue — so a burst of five section creations showed the first
/// "Created …" for its whole duration and the other four after it, one by one,
/// long after anyone cared, and with an action they never left at all.
///
/// So every notice here:
///
/// - **times out**, action or not (`persist: false`), after a duration that
///   fits its text ([tomNoticeDuration]) unless the caller states one;
/// - has a **kind**, and a notice **replaces** an earlier one of its kind,
///   whether that one is on screen or still waiting: a burst of creations
///   shows the latest. Notices of different kinds still queue, since each
///   says something the other does not.
///
/// Replacing a waiting notice needs to know the queue, which a
/// `ScaffoldMessenger` does not expose; this keeps a mirror of it per
/// messenger. The mirror is exact when every notice goes through here — a
/// snack bar shown some other way is invisible to it, and is the one case in
/// which a same-kind replacement also removes it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// How long a notice saying [message] stays: four seconds for a sentence,
/// one more for every further ten words, at most ten.
Duration tomNoticeDuration(String message) {
  final words = message.trim().split(RegExp(r'\s+')).length;
  final extra = words <= 12 ? 0 : ((words - 12) / 10).ceil();
  final seconds = 4 + extra;
  return Duration(seconds: seconds > 10 ? 10 : seconds);
}

/// Shows [message] as a notice of [kind] on [messenger], replacing one of the
/// same kind that is still showing or waiting. Does nothing without a
/// messenger (a host with no scaffold).
///
/// [key] is the snack bar's, [textKey] the text's — the two places tests and
/// hosts find a notice by. [action] is offered beside the text and the notice
/// still times out. [duration] overrides [tomNoticeDuration].
void tomShowNotice(
  ScaffoldMessengerState? messenger, {
  required String kind,
  required String message,
  Key? key,
  Key? textKey,
  SnackBarAction? action,
  Duration? duration,
}) {
  if (messenger == null) return;
  final queue = _queues[messenger] ??= _NoticeQueue();
  final bar = SnackBar(
    key: key,
    content: Text(message, key: textKey),
    duration: duration ?? tomNoticeDuration(message),
    persist: false,
    action: action,
  );
  queue.show(messenger, kind, bar);
}

final Expando<_NoticeQueue> _queues = Expando('tom notices');

class _Shown {
  _Shown(this.kind, this.bar);

  final String kind;
  final SnackBar bar;
}

/// The notices a messenger is showing or holding, in its order.
class _NoticeQueue {
  final List<_Shown> _entries = [];

  void show(ScaffoldMessengerState messenger, String kind, SnackBar bar) {
    if (_entries.any((e) => e.kind == kind)) {
      // A messenger can only take away the notice on screen, so the queue
      // is rebuilt: the notices of other kinds in their order, then this one.
      final kept = [
        for (final e in _entries)
          if (e.kind != kind) e,
      ];
      _entries.clear();
      messenger.clearSnackBars();
      // New entries: each cleared one's `closed` still completes, and must
      // not take its successor out of the mirror.
      for (final e in kept) {
        _add(messenger, _Shown(e.kind, e.bar));
      }
    }
    _add(messenger, _Shown(kind, bar));
  }

  void _add(ScaffoldMessengerState messenger, _Shown entry) {
    _entries.add(entry);
    unawaited(messenger
        .showSnackBar(entry.bar)
        .closed
        .then((_) => _entries.remove(entry)));
  }
}
