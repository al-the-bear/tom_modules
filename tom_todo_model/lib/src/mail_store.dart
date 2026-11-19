/// The mail store of wave 1b1 (D2 §2.4): the interface's in-memory
/// implementation, for tests and for the views built before mail is fetched.
/// Nothing here reads real mail; fetching it is wave 3 (D17).
library;

import 'dart:async';

import 'item.dart';
import 'item_store.dart';

/// Emails in memory: the base fields and the mail and people extensions.
/// An item's home container is its mailbox — the `container` it was written
/// to, else its `mail.mailbox`.
class TomInMemoryMailStore implements TomItemStore {
  TomInMemoryMailStore({
    this.storeId = 'mail:memory',
    Iterable<TomItem> items = const [],
    this.readOnly = false,
  }) {
    for (final item in items) {
      _check(item);
      _items[item.id] = (item.copy(), item.mail?.mailbox);
    }
  }

  @override
  final String storeId;

  @override
  final bool readOnly;

  /// The base fields, `mail` and `people`.
  static final TomFieldSet held = TomFieldSet.base.withExtensions(const [
    TomItemExtension.mail,
    TomItemExtension.people,
  ]);

  @override
  TomFieldSet get heldFields => held;

  final _items = <String, (TomItem, String?)>{};
  final _changes = StreamController<TomItemChange>.broadcast();

  void _check(TomItem item) {
    final lacking = held.lacking(item);
    if (lacking.isNotEmpty) {
      throw TomFieldsNotHeldException(storeId, item.id, lacking);
    }
  }

  TomStoredItem _stored(TomItem item, String? mailbox) => TomStoredItem(
    item.copy(),
    TomItemHome(store: storeId, container: mailbox),
  );

  @override
  Future<TomStoredItem?> read(String id) async {
    final entry = _items[id];
    return entry == null ? null : _stored(entry.$1, entry.$2);
  }

  @override
  Stream<TomItem> readAll() async* {
    for (final entry in _items.values.toList()) {
      yield entry.$1.copy();
    }
  }

  @override
  Future<TomStoredItem> write(TomItem item, {String? container}) async {
    if (readOnly) throw TomStoreReadOnlyException(storeId);
    _check(item);
    final before = _items[item.id];
    final mailbox = container ?? item.mail?.mailbox ?? before?.$2;
    _items[item.id] = (item.copy(), mailbox);
    if (before == null) {
      _changes.add(
        TomItemChange(TomItemChangeKind.added, item.id, store: storeId),
      );
    } else if (before.$1 != item || before.$2 != mailbox) {
      _changes.add(
        TomItemChange(TomItemChangeKind.changed, item.id, store: storeId),
      );
    }
    return _stored(item, mailbox);
  }

  @override
  Future<bool> delete(String id) async {
    if (readOnly) throw TomStoreReadOnlyException(storeId);
    if (_items.remove(id) == null) return false;
    _changes.add(TomItemChange(TomItemChangeKind.removed, id, store: storeId));
    return true;
  }

  @override
  Stream<TomItemChange> watch() => _changes.stream;

  /// Closes [watch].
  Future<void> dispose() => _changes.close();
}
