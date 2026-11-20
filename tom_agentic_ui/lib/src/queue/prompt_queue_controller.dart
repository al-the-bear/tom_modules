import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';

import '../chat/chat_send_coordinator.dart';

/// Observable owner of the prompt queue (§11.2): a list of [QueuedPrompt]s
/// persisted as YAML in the spec workspace via [PromptQueueStore], with
/// add/remove/reorder and send-next/retry dispatch through the
/// [ChatSendCoordinator].
///
/// Dispatch transitions an item `pending → sending → sent | error` and records
/// the exchange in the trail (via the coordinator). Items are immutable, so a
/// transition rebuilds the item through its YAML codec — which cleanly both
/// *sets* (`sentAt`) and *clears* (`error` on retry) optional fields without a
/// hand-written, easy-to-miss copy of all 35 fields.
///
/// The id/timestamp seams are injectable for deterministic tests.
class PromptQueueController extends ChangeNotifier {
  PromptQueueController({
    required this.coordinator,
    required PromptQueueStore store,
    String Function()? newId,
    String Function()? now,
  })  : _store = store,
        _newId = newId ?? _defaultId,
        _now = now ?? _defaultNow;

  /// Dispatches a prompt through the bridge and records it in the trail.
  final ChatSendCoordinator coordinator;

  final PromptQueueStore _store;
  final String Function() _newId;
  final String Function() _now;

  final List<QueuedPrompt> _items = [];
  bool _dispatching = false;

  /// The queued prompts in dispatch order (head first).
  List<QueuedPrompt> get items => List.unmodifiable(_items);

  /// Whether a send-next / retry is currently in flight.
  bool get isDispatching => _dispatching;

  /// Completes when every persisted write of the queue has landed.
  Future<void> get saved => _store.settled;

  /// Restores the persisted queue, replacing any in-memory state.
  Future<void> load() async {
    final items = await _store.load();
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  /// Appends a new pending prompt for [text], returning it.
  QueuedPrompt addPrompt(String text) {
    final id = _newId();
    final item = QueuedPrompt(
      id: id,
      originalText: text,
      expandedText: text,
      createdAt: _now(),
    );
    _items.add(item);
    _persistAndNotify();
    return item;
  }

  /// Removes the item with [id]. A no-op for an unknown id.
  void removeById(String id) {
    final before = _items.length;
    _items.removeWhere((p) => p.id == id);
    if (_items.length != before) _persistAndNotify();
  }

  /// Moves the item at [index] one place earlier in the queue.
  void moveUp(int index) {
    if (index <= 0 || index >= _items.length) return;
    final item = _items.removeAt(index);
    _items.insert(index - 1, item);
    _persistAndNotify();
  }

  /// Moves the item at [index] one place later in the queue.
  void moveDown(int index) {
    if (index < 0 || index >= _items.length - 1) return;
    final item = _items.removeAt(index);
    _items.insert(index + 1, item);
    _persistAndNotify();
  }

  /// Dispatches the first pending item through the coordinator. A no-op while
  /// another dispatch is in flight or when nothing is pending.
  Future<void> sendNext() async {
    if (_dispatching) return;
    final index = _items.indexWhere(
      (p) => p.status == QueuedPromptStatus.pending,
    );
    if (index < 0) return;
    await _dispatch(index);
  }

  /// Re-dispatches the item with [id] (typically after an error), resetting it
  /// to pending first. A no-op for an unknown id or while another dispatch is
  /// in flight.
  Future<void> retry(String id) async {
    if (_dispatching) return;
    final index = _items.indexWhere((p) => p.id == id);
    if (index < 0) return;
    await _dispatch(index);
  }

  /// Drives one item through `sending → sent | error`, recording the exchange
  /// in the trail via the coordinator.
  Future<void> _dispatch(int index) async {
    _dispatching = true;
    _items[index] = _transition(_items[index], QueuedPromptStatus.sending);
    _persistAndNotify();

    try {
      await coordinator.sendNow(_items[index].expandedText);
      final error = coordinator.send.error;
      _items[index] = error != null
          ? _transition(_items[index], QueuedPromptStatus.error,
              error: '$error')
          : _transition(_items[index], QueuedPromptStatus.sent, sentAt: _now());
    } catch (e) {
      _items[index] = _transition(_items[index], QueuedPromptStatus.error,
          error: '$e');
    } finally {
      _dispatching = false;
      _persistAndNotify();
    }
  }

  /// Rebuilds [item] with a new [status], optionally setting [sentAt] and
  /// either setting or clearing [error]. Uses the YAML codec so a retry can
  /// clear a previously-set error.
  QueuedPrompt _transition(
    QueuedPrompt item,
    QueuedPromptStatus status, {
    String? sentAt,
    String? error,
  }) {
    final map = item.toYaml();
    map['status'] = status.value;
    if (sentAt != null) {
      map['sentAt'] = sentAt;
    }
    if (error != null) {
      map['error'] = error;
    } else {
      map.remove('error');
    }
    return QueuedPrompt.fromYaml(map);
  }

  void _persistAndNotify() {
    unawaited(_store.save(List.of(_items)));
    notifyListeners();
  }

  static int _seq = 0;
  static String _defaultId() =>
      'queue-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
  static String _defaultNow() => DateTime.now().toUtc().toIso8601String();
}
