import 'package:flutter/foundation.dart';
import 'package:tom_basics/utilities.dart' show TomCancellationSource;
import 'package:tom_core_agentic/tom_core_agentic.dart';

import '../connection/agent_connection_controller.dart';

/// Where the §6.1 reconnect protocol stands for the current send.
enum ReconnectPhase {
  /// No reconnect in progress (the normal state).
  idle,

  /// The back-off probe is running (§6.1 steps 1–2) — drives the non-blocking
  /// informational popup.
  probing,

  /// The bound port came back serving a *different* workspace (§6.1 step 5);
  /// waiting for the user to [AgentSendController.confirmDifferentWorkspace] or
  /// dismiss.
  awaitingDifferentWorkspace,

  /// The bound port stayed silent after all retries (§6.1 step 4); waiting for
  /// the user's modal decision ([AgentSendController.abortReconnect] /
  /// [AgentSendController.resendPending]). The prompt is preserved.
  awaitingStillGone,
}

/// Drives a single prompt through the bridge-backed Agent SDK and exposes the
/// streamed answer as observable UI state (§7), with the §6.1 reconnect
/// protocol layered on top.
///
/// Thin Flutter wrapper over the pure-Dart [AgentSendEngine]: it resolves the
/// bound bridge from the shared [AgentConnectionController], builds an
/// `AgentSdkClient` for that host/port via the injectable [clientFactory]
/// (defaulting to [connectAgentSdkClient]), then folds the engine's
/// [AgentSendEvent] stream into [output] / [sending] / [error] / [sessionId].
///
/// When the bridge cannot be reached the transport is gone (N1); rather than
/// fail, the controller runs the [ReconnectCoordinator] back-off (§6.1) — the
/// [reconnectPhase] surfaces the informational/modal state — and:
///   * **same workspace returns** → rebind silently and **auto-resend** the
///     interrupted prompt prefixed with the active profile's
///     [interruptRetryPrefix] (N10, §6.1 step 3);
///   * **different workspace** → pause at [ReconnectPhase.awaitingDifferentWorkspace]
///     until [confirmDifferentWorkspace] (§6.1 step 5);
///   * **still gone** → pause at [ReconnectPhase.awaitingStillGone] with the
///     prompt preserved; [abortReconnect] fails, [resendPending] retries (step 4).
///
/// The factory + back-off seams keep this layer transport-agnostic (N7) and let
/// tests run the whole pipeline over a fake `AgentSdkTransport` with a
/// zero-duration back-off, without opening a socket or waiting 100 seconds.
class AgentSendController extends ChangeNotifier {
  AgentSendController({
    required this.connection,
    this.config = const AgentSendConfig(),
    this.interruptRetryPrefix = AgentProfile.defaultInterruptRetryPrefix,
    List<Duration> reconnectBackoff = defaultReconnectBackoff,
    required SpecSessionStore sessionStore,
    AgentSdkClientFactory? clientFactory,
  })  : _reconnectBackoff = reconnectBackoff,
        _sessionStore = sessionStore,
        _clientFactory = clientFactory ?? connectAgentSdkClient;

  /// The shared connection controller; its bound choice supplies the bridge
  /// host/port the send connects to, and its bound workspace lets the reconnect
  /// protocol detect a *different* workspace (§6.1 step 5).
  final AgentConnectionController connection;

  /// The assembled `Options` inputs (profile + global settings + MCP tools).
  final AgentSendConfig config;

  /// The active profile's interrupt-retry prefix (N10), prepended to an
  /// auto-resent interrupted prompt on reconnect (§6.1 step 3).
  final String interruptRetryPrefix;

  final List<Duration> _reconnectBackoff;
  final SpecSessionStore _sessionStore;
  final AgentSdkClientFactory _clientFactory;

  final StringBuffer _output = StringBuffer();
  bool _sending = false;
  Object? _error;
  String? _sessionId;
  bool _sessionRefreshed = false;
  Object? _connectError;
  ReconnectPhase _phase = ReconnectPhase.idle;
  String? _pendingPrompt;
  BridgeServer? _differentWorkspaceServer;

  /// Cancellation source for the turn in flight, or `null`. [cancel] signals it
  /// to abort: the engine interrupts the active query (`agentSdk.cancelVce`),
  /// closing its stream so the turn unwinds without a terminal event.
  TomCancellationSource? _cancelSource;

  /// Set by [cancel] so a turn aborted while the §6.1 reconnect back-off is
  /// probing is not resurrected when the probe resolves. Reset by [send].
  bool _cancelled = false;

  /// The accumulated assistant answer text streamed so far.
  String get output => _output.toString();

  /// Whether a send/reconnect is actively in flight (false while *paused* for a
  /// user decision — see [reconnectPhase]).
  bool get sending => _sending;

  /// The last failure (engine [AgentSendFailed] message, a connect error the
  /// user chose to fail on, or a "no bridge bound" guard), or `null`.
  Object? get error => _error;

  /// The Claude-Code session id of the last completed turn, or `null`.
  String? get sessionId => _sessionId;

  /// Whether the last send had to refresh a stale session id (§7.2).
  bool get sessionRefreshed => _sessionRefreshed;

  /// Where the reconnect protocol stands (§6.1).
  ReconnectPhase get reconnectPhase => _phase;

  /// The interrupted prompt preserved while reconnect awaits a user decision
  /// (§6.1 steps 4–5), or `null` when idle / recovered.
  String? get pendingPrompt => _pendingPrompt;

  /// The server found on the bound port serving a *different* workspace, set
  /// while [reconnectPhase] is [ReconnectPhase.awaitingDifferentWorkspace].
  BridgeServer? get differentWorkspaceServer => _differentWorkspaceServer;

  /// Whether a fresh prompt can be sent right now: nothing in flight, no
  /// reconnect pending, and a bridge is bound.
  bool get canSend =>
      !_sending &&
      _phase == ReconnectPhase.idle &&
      connection.boundChoice != null;

  /// Streams [prompt] through the bound bridge, accumulating the answer into
  /// [output]. On a transport failure it runs the §6.1 reconnect protocol and,
  /// on the same workspace returning, auto-resends the prefixed prompt. A second
  /// call while busy or mid-reconnect is a no-op.
  Future<void> send(String prompt) async {
    if (_sending || _phase != ReconnectPhase.idle) return;
    if (connection.boundChoice == null) {
      _error = StateError('No bridge bound — pick a connection first.');
      notifyListeners();
      return;
    }

    _sending = true;
    _cancelled = false;
    _error = null;
    _connectError = null;
    _sessionRefreshed = false;
    _pendingPrompt = null;
    _differentWorkspaceServer = null;
    _output.clear();
    notifyListeners();

    try {
      final connected = await _streamOnce(prompt);
      if (!connected && !_cancelled) {
        await _runReconnect(prompt);
      }
    } catch (e) {
      _error = e;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Aborts the turn in flight, stopping the underlying Agent SDK query
  /// (`agentSdk.cancelVce`) through the engine → `AgentSdkClient` → transport
  /// cancel path. A no-op when nothing is in flight.
  ///
  /// The text streamed so far is kept in [output] and the cancel is *not* an
  /// [error] — it is the user's deliberate stop. Any §6.1 reconnect awaiting the
  /// user's input is cleared, since stopping supersedes that decision.
  void cancel() {
    if (!_sending) return;
    _cancelled = true;
    // Signal the engine to interrupt the active query. The engine closes the
    // query stream and ends its event stream silently, which unwinds the
    // in-flight [_streamOnce] and lets [send] complete. Flip the UI state now
    // for immediate feedback; [send]'s `finally` re-asserts it harmlessly.
    _cancelSource?.cancel();
    _phase = ReconnectPhase.idle;
    _pendingPrompt = null;
    _differentWorkspaceServer = null;
    _sending = false;
    notifyListeners();
  }

  /// Binds the different-workspace server and auto-resends the preserved prompt
  /// (§6.1 step 5). No-op unless [reconnectPhase] is
  /// [ReconnectPhase.awaitingDifferentWorkspace].
  Future<void> confirmDifferentWorkspace() async {
    if (_phase != ReconnectPhase.awaitingDifferentWorkspace) return;
    final server = _differentWorkspaceServer;
    final prompt = _pendingPrompt;
    _phase = ReconnectPhase.idle;
    _differentWorkspaceServer = null;
    if (server == null || prompt == null) {
      _pendingPrompt = null;
      notifyListeners();
      return;
    }
    connection.bind(server);
    _sending = true;
    notifyListeners();
    try {
      await _resend(prompt);
    } catch (e) {
      _error = e;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Aborts a still-gone reconnect (§6.1 step 4): fails the send and drops the
  /// preserved prompt. No-op unless awaiting the still-gone modal.
  void abortReconnect() {
    if (_phase != ReconnectPhase.awaitingStillGone) return;
    _error = _connectError ?? StateError('Connection lost — send aborted.');
    _pendingPrompt = null;
    _differentWorkspaceServer = null;
    _phase = ReconnectPhase.idle;
    notifyListeners();
  }

  /// Re-attempts the preserved prompt from an awaiting state (the user-driven
  /// re-send of §6.1 step 4 / a declined step 5). No-op when idle.
  Future<void> resendPending() async {
    if (_phase == ReconnectPhase.idle) return;
    final prompt = _pendingPrompt;
    _phase = ReconnectPhase.idle;
    _pendingPrompt = null;
    _differentWorkspaceServer = null;
    notifyListeners();
    if (prompt != null) await send(prompt);
  }

  /// Performs one connect + stream. Returns `true` if the bridge was reached
  /// (whatever the agent outcome); `false` if the connection could not be
  /// established (N1: the transport is gone), which triggers reconnect.
  Future<bool> _streamOnce(String prompt) async {
    final bound = connection.boundChoice!;
    final AgentSendEngine engine;
    try {
      final client = await _clientFactory(host: bound.host, port: bound.port);
      engine = AgentSendEngine(
        client: client,
        sessionStore: _sessionStore,
        config: config,
      );
    } catch (e) {
      _connectError = e;
      return false;
    }

    // A per-turn cancellation source: [cancel] signals it, the engine
    // interrupts the active query (`agentSdk.cancelVce`) and ends its stream
    // silently, so the `await for` below unwinds without a terminal event.
    final cancelSource = TomCancellationSource();
    _cancelSource = cancelSource;
    try {
      await for (final event in engine.send(prompt, cancelToken: cancelSource.token)) {
        switch (event) {
          case AgentSendStarted():
            break;
          case AgentSendChunk(:final text):
            _output.write(text);
            notifyListeners();
          case AgentSendSessionRefreshed():
            _sessionRefreshed = true;
            notifyListeners();
          case AgentSendCompleted(:final sessionId):
            _sessionId = sessionId;
          case AgentSendFailed(:final message):
            _error = message;
        }
      }
      return true;
    } finally {
      if (identical(_cancelSource, cancelSource)) _cancelSource = null;
    }
  }

  /// Runs the §6.1 reconnect back-off for an [originalPrompt] interrupted by a
  /// lost connection, then resolves per the returned [ReconnectResolution].
  Future<void> _runReconnect(String originalPrompt) async {
    _phase = ReconnectPhase.probing; // informational popup (step 1)
    _error = null; // the connect failure is being handled, not surfaced yet
    notifyListeners();

    final coordinator = ReconnectCoordinator(
      service: connection.service,
      backoff: _reconnectBackoff,
    );
    final result = await coordinator.reconnect(
      bound: connection.boundChoice!,
      boundWorkspace: connection.boundWorkspace,
    );

    // The user pressed Stop while the back-off probe was running; honour that
    // rather than resurrecting the turn with the probe's late result.
    if (_cancelled) return;

    switch (result.resolution) {
      case ReconnectResolution.sameWorkspace:
        // Reconnect silently and auto-resend the prefixed prompt (step 3).
        if (result.server != null) connection.bind(result.server!);
        _phase = ReconnectPhase.idle;
        notifyListeners();
        await _resend(originalPrompt);
      case ReconnectResolution.differentWorkspace:
        // Pause for the user's confirmation (step 5) — nothing re-sent yet.
        _differentWorkspaceServer = result.server;
        _pendingPrompt = originalPrompt;
        _phase = ReconnectPhase.awaitingDifferentWorkspace;
        notifyListeners();
      case ReconnectResolution.stillGone:
        // Pause for the modal (step 4); the prompt stays re-sendable.
        _pendingPrompt = originalPrompt;
        _phase = ReconnectPhase.awaitingStillGone;
        notifyListeners();
    }
  }

  /// Auto-resends [originalPrompt] prefixed per the active profile (§6.1 step
  /// 3, N10). A second connect failure parks the prompt at the still-gone modal
  /// rather than looping the reconnect protocol again.
  Future<void> _resend(String originalPrompt) async {
    final connected = await _streamOnce(
      composeInterruptRetry(interruptRetryPrefix, originalPrompt),
    );
    if (connected) {
      _pendingPrompt = null;
    } else {
      _pendingPrompt = originalPrompt;
      _phase = ReconnectPhase.awaitingStillGone;
      notifyListeners();
    }
  }
}
