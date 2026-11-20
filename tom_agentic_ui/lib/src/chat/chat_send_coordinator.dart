import '../send/agent_send_controller.dart';
import '../trail/prompt_trail_controller.dart';
import 'placeholder_preview.dart';

/// Sends a prompt through the bridge and records the exchange in the trail.
///
/// The composer's "Send now" (§11.1) and the queue's send-next (§11.2) both
/// need the same two-step behaviour: open a trail pair for the request, stream
/// the answer through the [AgentSendController], then close the pair with the
/// streamed answer (or the failure). Factoring it here keeps that single
/// responsibility in one place rather than duplicated across the composer and
/// the queue controller.
///
/// Stateless: it holds no mutable state of its own — the send state lives on
/// [send] and the pairs on [trail].
class ChatSendCoordinator {
  ChatSendCoordinator({
    required this.send,
    required this.trail,
    PromptCompose? compose,
    void Function(String turnId)? onTurnBegin,
    void Function()? onTurnEnd,
  })  : _compose = compose ?? _identity,
        _onTurnBegin = onTurnBegin,
        _onTurnEnd = onTurnEnd;

  /// The transport that streams the answer (§7).
  final AgentSendController send;

  /// The trail the request/answer pair is recorded into (§11.3).
  final PromptTrailController trail;

  /// Expands the raw prompt's placeholders just before send (§11.5). Supplied
  /// by the host (the TomSpecs editor wires its `SpecPromptComposer.compose`);
  /// defaults to identity so a host without a placeholder context sends the
  /// prompt verbatim. A `${{ … }}` expression form makes this throw, which
  /// [sendNow] surfaces as a failed trail pair rather than a crash.
  final PromptCompose _compose;

  /// Opens the agent-turn boundary just before the send (§9/§10, step 15). The
  /// host (the TomSpecs editor) wires its `SpecDocumentController.beginTurn` so
  /// every document mutation the agent makes mid-stream — via the §8 tools —
  /// collapses into a single undo group and one change-log turn. The turn id is
  /// the trail pair id, so the change-log turn and the trail exchange share an
  /// identifier. Optional: a host without a live document leaves it null and the
  /// send is unbracketed.
  final void Function(String turnId)? _onTurnBegin;

  /// Closes the agent-turn boundary after the send settles ([_onTurnBegin]'s
  /// partner). Always called when a turn was opened, even if the send throws or
  /// fails, so the host's undo group is never left open.
  final void Function()? _onTurnEnd;

  static Future<String> _identity(String raw) async => raw;

  /// Composes [prompt] (placeholder expansion, §11.5), streams the result
  /// through the bound bridge, and records the request/answer pair. Resolves
  /// after the turn completes; the trail pair reflects the final streamed
  /// answer, or the failure (a send error, or a placeholder-resolution error
  /// such as the disabled `${{ … }}` form).
  Future<void> sendNow(String prompt) async {
    final String composed;
    try {
      composed = await _compose(prompt);
    } catch (error) {
      // A placeholder-resolution failure (e.g. the disabled `${{ … }}` form):
      // record the raw prompt with the error instead of sending anything.
      final pairId = trail.recordRequest(prompt);
      trail.failAnswer(pairId, '$error');
      return;
    }

    final pairId = trail.recordRequest(composed);
    // Bracket the send — and only the send, where the §8 tools mutate the
    // document mid-stream — as one agent turn so the host collapses every edit
    // into a single undo group. `endTurn` runs in a `finally` so a thrown or
    // failed send never leaves the host's undo group open.
    _onTurnBegin?.call(pairId);
    try {
      await send.send(composed);
    } finally {
      _onTurnEnd?.call();
    }
    final error = send.error;
    if (error != null) {
      trail.failAnswer(pairId, '$error');
    } else {
      trail.completeAnswer(pairId, send.output);
    }
  }
}
