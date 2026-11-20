import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';

/// Observable owner of the prompt trail (§11.3): the request/answer pairs of
/// SDK exchanges, persisted as YAML in the spec workspace via
/// [PromptTrailStore].
///
/// A pair is opened by [recordRequest] (answer still streaming → `null`) and
/// closed by [completeAnswer] / [failAnswer]. The list is kept in chronological
/// order; the view renders it newest-first. Every mutation persists and
/// notifies, so the trail survives launches and the column repaints live.
///
/// The id/timestamp seams are injectable so tests get deterministic ids and
/// stable ordering without touching the clock.
class PromptTrailController extends ChangeNotifier {
  PromptTrailController({
    required PromptTrailStore store,
    String Function()? newId,
    String Function()? now,
  })  : _store = store,
        _newId = newId ?? _defaultId,
        _now = now ?? _defaultNow;

  final PromptTrailStore _store;
  final String Function() _newId;
  final String Function() _now;

  final List<TrailPair> _pairs = [];

  /// The trail pairs in chronological (oldest-first) order.
  List<TrailPair> get pairs => List.unmodifiable(_pairs);

  /// Completes when every persisted write of the trail has landed.
  Future<void> get saved => _store.settled;

  /// Restores the persisted trail, replacing any in-memory state.
  Future<void> load() async {
    final pairs = await _store.load();
    _pairs
      ..clear()
      ..addAll(pairs);
    notifyListeners();
  }

  /// Opens a new pair for [request] with no answer yet, returning its id so the
  /// caller can close it once the answer is in.
  String recordRequest(String request) {
    final id = _newId();
    final at = _now();
    _pairs.add(TrailPair(
      id: id,
      createdAt: at,
      request: ChatMessage(
        id: '$id-q',
        role: ChatRole.user,
        text: request,
        createdAt: at,
      ),
    ));
    _persistAndNotify();
    return id;
  }

  /// Closes the pair [pairId] with the assistant [answer]. A no-op for an
  /// unknown id.
  void completeAnswer(String pairId, String answer, {String? summaryMarkdown}) {
    _setAnswer(pairId, answer, ChatRole.assistant, summaryMarkdown);
  }

  /// Closes the pair [pairId] with an error message in place of the answer.
  void failAnswer(String pairId, String error) {
    _setAnswer(pairId, error, ChatRole.assistant, null);
  }

  void _setAnswer(
    String pairId,
    String text,
    ChatRole role,
    String? summaryMarkdown,
  ) {
    final index = _pairs.indexWhere((p) => p.id == pairId);
    if (index < 0) return;
    final existing = _pairs[index];
    _pairs[index] = TrailPair(
      id: existing.id,
      request: existing.request,
      createdAt: existing.createdAt,
      answer: ChatMessage(
        id: '$pairId-a',
        role: role,
        text: text,
        createdAt: _now(),
      ),
      summaryMarkdown: summaryMarkdown ?? existing.summaryMarkdown,
      providerId: existing.providerId,
      modelId: existing.modelId,
      tokensIn: existing.tokensIn,
      tokensOut: existing.tokensOut,
      costUsd: existing.costUsd,
    );
    _persistAndNotify();
  }

  void _persistAndNotify() {
    unawaited(_store.save(List.of(_pairs)));
    notifyListeners();
  }

  static int _seq = 0;
  static String _defaultId() => 'trail-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
  static String _defaultNow() => DateTime.now().toUtc().toIso8601String();
}
