/// An AI run started from the host application, docked in its session's tab
/// of the trail view.
///
/// A run is not a dialog's state. It belongs to the trail controller, under
/// the session it runs in, so the rest of the application stays usable while it
/// streams, a second run in another session can be started beside it, and
/// switching tabs — or closing the panel — leaves it running. Its preview and
/// its decision (preview-then-apply) are shown in the tab, above the
/// session's trail. Discarding it — its own button, or closing the tab — is
/// the rejection: a request still streaming is cancelled and nothing is
/// written.
library;

import 'package:flutter/widgets.dart';

/// A run docked in a session tab.
abstract class TomDockedAiRun extends ChangeNotifier {
  TomDockedAiRun({required String sessionId}) : _sessionId = sessionId;

  String _sessionId;

  /// The session the run is traced in, and whose tab shows it.
  String get sessionId => _sessionId;

  /// Moves a run that has not started to another session. The controller
  /// calls it; nothing else should.
  void retarget(String sessionId) {
    _sessionId = sessionId;
    notifyListeners();
  }

  /// What the run is, as its tab shows it ("Summarize", "Ask the agent").
  String get title;

  /// Whether the run still holds its session: being set up, asking the model,
  /// or waiting for the user's decision. A session holds one such run at a
  /// time; a run that has ended no longer holds it.
  bool get isActive;

  /// Whether the run is asking the model now — its tab shows it as running.
  bool get isWorking;

  /// Whether the run is waiting for the user — its proposal is ready to keep
  /// or discard. The tab is marked so the user sees it from any other tab.
  bool get needsDecision;

  /// One line saying where the run is, for the **All** tab's overview.
  String get statusLine;

  /// Stops the run: cancels a request in flight and rejects a proposal still
  /// awaiting a decision, so nothing is written. Safe to call more than once.
  void discard();

  /// The run's view, drawn in its session's tab above the trail. It scrolls
  /// when the panel is short.
  Widget buildView(BuildContext context);

  /// The run's buttons — Keep, Discard, Cancel, Close — drawn under its view
  /// and never scrolled out of reach.
  Widget buildActions(BuildContext context);

  bool _disposed = false;

  /// Whether [dispose] has run; a run's request can end after its tab closed.
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
