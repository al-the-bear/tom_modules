/// The store side of the item model (Webwork D2 §2.4): every item has one
/// home — a store and, inside it, the container holding its record — and
/// every store answers the same interface, [TomItemStore], with the
/// declaration of the fields it can hold ([TomFieldSet]).
///
/// The views gather items from the loaded stores through one index; its
/// entry is [TomItemIndexEntry]. Moving an item between stores keeps its id
/// and names the fields the target cannot hold before they are dropped
/// ([TomItemMove]).
library;

import 'item.dart';
import 'todo.dart';

/// The four extensions of an item and the flat keys each one takes.
enum TomItemExtension {
  container(['children']),
  people(['people']),
  mail(['mail']),
  workflow(TomItemWorkflow.fields);

  const TomItemExtension(this.keys);

  /// The flat keys ([TomItem.fields]) the extension's fields are written
  /// under.
  final List<String> keys;
}

/// The fields a store can hold, as flat keys of [TomItem.fields].
class TomFieldSet {
  TomFieldSet(Iterable<String> fields) : fields = Set.unmodifiable(fields) {
    final unknown = this.fields.difference(TomItem.fields);
    if (unknown.isNotEmpty) {
      throw ArgumentError.value(unknown, 'fields', 'not item fields');
    }
    final missing = _identity.difference(this.fields);
    if (missing.isNotEmpty) {
      throw ArgumentError.value(
        missing,
        'fields',
        'every store holds an item\'s identity',
      );
    }
  }

  /// Every field and extension.
  static final TomFieldSet all = TomFieldSet(TomItem.fields);

  /// The base fields and the planning, dependency and link fields: every
  /// field outside the four extensions.
  static final TomFieldSet base = TomFieldSet(
    TomItem.fields.difference({
      for (final e in TomItemExtension.values) ...e.keys,
    }),
  );

  /// `id`, `title` and `status`: what every store holds.
  static const Set<String> _identity = {'id', 'title', 'status'};

  final Set<String> fields;

  bool holds(String field) => fields.contains(field);

  /// Whether every key of [extension] is held.
  bool holdsExtension(TomItemExtension extension) =>
      extension.keys.every(fields.contains);

  /// This set and [extensions].
  TomFieldSet withExtensions(Iterable<TomItemExtension> extensions) =>
      TomFieldSet({...fields, for (final e in extensions) ...e.keys});

  /// The fields [item] holds — the keys of its flat form, which carries
  /// only what is set — that this set lacks, in [TomItem.fields] order.
  List<String> lacking(TomItem item) => [
    for (final key in item.toMap().keys)
      if (!fields.contains(key)) key,
  ];

  @override
  bool operator ==(Object other) =>
      other is TomFieldSet &&
      other.fields.length == fields.length &&
      other.fields.containsAll(fields);

  @override
  int get hashCode => Object.hashAllUnordered(fields);

  @override
  String toString() => 'TomFieldSet(${fields.length} fields)';
}

/// Where an item's record lives: its store and the container inside it.
class TomItemHome {
  const TomItemHome({required this.store, this.container});

  /// The store's [TomItemStore.storeId].
  final String store;

  /// The container holding the record (a list, a section, a mailbox); null
  /// when the store itself is the container (a todo file).
  final String? container;

  @override
  bool operator ==(Object other) =>
      other is TomItemHome &&
      other.store == store &&
      other.container == container;

  @override
  int get hashCode => Object.hash(store, container);

  @override
  String toString() => container == null ? store : '$store#$container';
}

/// An item as a store answers it: the record and its home.
class TomStoredItem {
  const TomStoredItem(this.item, this.home);

  final TomItem item;
  final TomItemHome home;
}

/// What happened to an item in a store.
enum TomItemChangeKind { added, changed, removed }

/// One change [TomItemStore.watch] reports, by id.
class TomItemChange {
  const TomItemChange(this.kind, this.id, {required this.store});

  final TomItemChangeKind kind;
  final String id;

  /// The store's [TomItemStore.storeId].
  final String store;

  @override
  bool operator ==(Object other) =>
      other is TomItemChange &&
      other.kind == kind &&
      other.id == id &&
      other.store == store;

  @override
  int get hashCode => Object.hash(kind, id, store);

  @override
  String toString() => 'TomItemChange(${kind.name} $id in $store)';
}

/// A write a store refused; nothing was written.
sealed class TomItemStoreRefusal implements Exception {
  const TomItemStoreRefusal(this.store, this.message);

  final String store;
  final String message;

  @override
  String toString() => message;
}

/// The item holds fields the store cannot hold ([fields], flat keys).
class TomFieldsNotHeldException extends TomItemStoreRefusal {
  TomFieldsNotHeldException(String store, this.id, this.fields)
    : super(
        store,
        'The store $store cannot hold ${fields.join(', ')} of item $id',
      );

  final String id;
  final List<String> fields;
}

/// The store is read-only (a document opened read-only, a locked KDBX).
class TomStoreReadOnlyException extends TomItemStoreRefusal {
  TomStoreReadOnlyException(String store)
    : super(store, 'The store $store is read-only');
}

/// One store of items (D2 §2.4): read, write, delete, watch, and the
/// declaration of the fields it can hold.
abstract interface class TomItemStore {
  /// The store's identity: a path, a locator, an account.
  String get storeId;

  /// The fields and extensions the store can hold. A view shows a field
  /// outside it disabled, with the reason.
  TomFieldSet get heldFields;

  /// True when every write is refused ([TomStoreReadOnlyException]).
  bool get readOnly;

  /// The item [id] with its home, or null when the store has none.
  Future<TomStoredItem?> read(String id);

  /// Every item of the store, in its order.
  Stream<TomItem> readAll();

  /// Stores [item] — adding it, or replacing the record of the same id —
  /// in [container] when the store has containers, and answers it as
  /// stored. Refused, with nothing written, when the store is [readOnly] or
  /// the item holds a field outside [heldFields]
  /// ([TomFieldsNotHeldException] naming them).
  Future<TomStoredItem> write(TomItem item, {String? container});

  /// Removes the item [id]; false when the store has none. Refused when the
  /// store is [readOnly].
  Future<bool> delete(String id);

  /// The changes, by id, as they happen: added, changed, removed.
  Stream<TomItemChange> watch();
}

/// What the views gather from the stores: one entry per item, the item's
/// identity and home, its types and the fields the todo, reminder and
/// journal views filter, sort and show by (D2 §6a, the item index).
class TomItemIndexEntry {
  TomItemIndexEntry({
    required this.id,
    required this.store,
    required this.home,
    required Set<TomItemType> types,
    required this.headline,
    this.description,
    required this.status,
    this.priority,
    this.flag = false,
    this.start,
    this.due,
    this.estimate,
    List<TomItemReminder> reminders = const [],
    List<String> tags = const [],
    List<String> dependencies = const [],
    List<String> blockedBy = const [],
    List<TomItemMembership> memberships = const [],
  }) : types = Set.unmodifiable(types),
       reminders = List.unmodifiable(reminders),
       tags = List.unmodifiable(tags),
       dependencies = List.unmodifiable(dependencies),
       blockedBy = List.unmodifiable(blockedBy),
       memberships = List.unmodifiable(memberships);

  /// The entry of [stored], its computed types answered from [context].
  factory TomItemIndexEntry.of(
    TomStoredItem stored, {
    TomItemTypeContext context = const TomItemTypeContext(),
  }) {
    final item = stored.item;
    return TomItemIndexEntry(
      id: item.id,
      store: stored.home.store,
      home: stored.home,
      types: item.types(context),
      headline: item.headline,
      description: item.description,
      status: item.status,
      priority: item.priority,
      flag: item.flag,
      start: item.start,
      due: item.due,
      estimate: item.estimate,
      reminders: item.reminders,
      tags: item.tags,
      dependencies: item.dependencies,
      blockedBy: item.blockedBy,
      memberships: item.memberships,
    );
  }

  final String id;

  /// The store's [TomItemStore.storeId], and the item's home in it.
  final String store;
  final TomItemHome home;

  /// Stored and computed.
  final Set<TomItemType> types;

  final String headline;
  final String? description;
  final TomTodoStatus status;
  final TomTodoPriority? priority;
  final bool flag;
  final DateTime? start;
  final DateTime? due;
  final String? estimate;
  final List<TomItemReminder> reminders;
  final List<String> tags;
  final List<String> dependencies;
  final List<String> blockedBy;
  final List<TomItemMembership> memberships;

  /// The facet names [valueOf] answers.
  static const List<String> facets = [
    'id',
    'store',
    'home',
    'types',
    'headline',
    'description',
    'status',
    'priority',
    'flag',
    'start',
    'due',
    'estimate',
    'reminders',
    'tags',
    'dependencies',
    'blocked_by',
    'memberships',
  ];

  /// The value of [facet] in wire form, for a condition evaluator: the
  /// types as their wire names, the status and priority as theirs, dates as
  /// `yyyy-MM-dd`. Null for a facet the entry does not have.
  Object? valueOf(String facet) => switch (facet) {
    'id' => id,
    'store' => store,
    'home' => home.toString(),
    'types' => [for (final t in types) t.wire],
    'headline' => headline,
    'description' => description,
    'status' => status.wire,
    'priority' => priority?.wire,
    'flag' => flag,
    'start' => start == null ? null : TomItem.encodeDate(start!),
    'due' => due == null ? null : TomItem.encodeDate(due!),
    'estimate' => estimate,
    'reminders' => [for (final r in reminders) r.toMap()],
    'tags' => tags,
    'dependencies' => dependencies,
    'blocked_by' => blockedBy,
    'memberships' => [for (final m in memberships) m.ref],
    _ => null,
  };

  @override
  String toString() => 'TomItemIndexEntry($id in $home)';
}

/// A move refused before anything was written.
class TomItemMoveRefused implements Exception {
  const TomItemMoveRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Moving an item from one store to another, its id kept (D2 §2.3
/// `moveItem`, §2.4).
///
/// [lostFields] names the item's fields the target cannot hold; [run]
/// refuses unless the caller confirms exactly those, so the user has been
/// shown what is lost before it is dropped. An item with a body cannot move
/// into a store without one — that move is refused, not narrowed. The item
/// is written to the target first and deleted from the source after, so a
/// failure leaves it where it was.
class TomItemMove {
  TomItemMove({
    required this.source,
    required this.target,
    required this.id,
    this.container,
  });

  final TomItemStore source;
  final TomItemStore target;
  final String id;

  /// The container in [target] the item goes to.
  final String? container;

  Future<TomItem> _item() async {
    final stored = await source.read(id);
    if (stored == null) {
      throw TomItemMoveRefused('${source.storeId} has no item $id');
    }
    return stored.item;
  }

  /// The fields of the item the target cannot hold, as flat keys; empty
  /// when it can hold everything.
  Future<List<String>> lostFields() async =>
      target.heldFields.lacking(await _item());

  /// Moves the item. [confirmLost] must name exactly [lostFields]; the
  /// moved item is the item without them.
  Future<TomStoredItem> run({Iterable<String> confirmLost = const []}) async {
    if (source.storeId == target.storeId) {
      throw const TomItemMoveRefused(
        'A move within one store is a move between its containers',
      );
    }
    if (source.readOnly) throw TomStoreReadOnlyException(source.storeId);
    if (target.readOnly) throw TomStoreReadOnlyException(target.storeId);
    final item = await _item();
    final lost = target.heldFields.lacking(item);
    if (lost.contains('body') || lost.contains('body_type')) {
      throw TomItemMoveRefused(
        'Item $id has a body, which ${target.storeId} cannot hold',
      );
    }
    final confirmed = confirmLost.toSet();
    if (confirmed.length != lost.length || !confirmed.containsAll(lost)) {
      throw TomItemMoveRefused(
        lost.isEmpty
            ? 'Nothing is lost moving item $id; confirm no fields'
            : 'Moving item $id to ${target.storeId} drops '
                  '${lost.join(', ')}; confirm exactly those',
      );
    }
    if (await target.read(id) != null) {
      throw TomItemMoveRefused('${target.storeId} already holds an item $id');
    }
    final map = item.toMap()..removeWhere((key, _) => lost.contains(key));
    final moved = await target.write(
      TomItem.fromMap(map),
      container: container,
    );
    await source.delete(id);
    return moved;
  }
}
