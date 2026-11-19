/// A `*.todo.yaml` file as an item store (D2 §2.4): the [TomTodoFile] splice
/// codec over the file's text, every item a `todo`, every field of
/// [TomItem] held.
library;

import 'dart:async';

import 'item.dart';
import 'item_store.dart';
import 'todo_file.dart';

/// The text of one todo file. Reading and writing the file is the
/// application's (this package reaches no `dart:io`): a desktop binds a file
/// on disk, Webwork its file session.
abstract interface class TomTodoFileText {
  /// The file's text as it is now.
  Future<String> read();

  /// Replaces the file's text with [text].
  Future<void> write(String text);
}

/// A todo file's text held in memory: tests, and an application that
/// writes the text out itself.
class TomMemoryTodoFileText implements TomTodoFileText {
  TomMemoryTodoFileText(this.text);

  String text;

  /// How many times [write] was called.
  int writes = 0;

  @override
  Future<String> read() async => text;

  @override
  Future<void> write(String text) async {
    this.text = text;
    writes++;
  }
}

/// The items of one `*.todo.yaml` file.
///
/// Every edit is a splice into the file's text ([TomTodoFile.withItem],
/// [TomTodoFile.withInserted], [TomTodoFile.withoutTodo]): the layout, the
/// comments and every untouched key keep their bytes; a field that is set is
/// written, an empty one never is. Before each edit the text is read again,
/// so an edit made outside the store is taken in — and reported by [watch] —
/// rather than written over. Edits run one at a time. An item the model
/// refuses ([TomTodoFileEntry.error]) is not listed and cannot be written.
class TomTodoFileStore implements TomItemStore {
  TomTodoFileStore({
    required this.storeId,
    required TomTodoFileText text,
    this.readOnly = false,
  }) : _text = text;

  @override
  final String storeId;

  final TomTodoFileText _text;

  @override
  final bool readOnly;

  /// Every field of [TomItem]: the todo schema declares them all.
  @override
  TomFieldSet get heldFields => TomFieldSet.all;

  TomTodoFile? _file;
  Future<void> _queue = Future.value();
  final _changes = StreamController<TomItemChange>.broadcast();

  /// Reads the text again; reports what changed since the last read.
  Future<TomTodoFile> _reload() async {
    final text = await _text.read();
    final before = _file;
    if (before != null && before.text == text) return before;
    final after = TomTodoFile.parse(text);
    _file = after;
    if (before != null) _report(before, after);
    return after;
  }

  void _report(TomTodoFile before, TomTodoFile after) {
    final old = {for (final i in before.items) i.id: i};
    final now = {for (final i in after.items) i.id: i};
    for (final id in old.keys) {
      if (!now.containsKey(id)) _emit(TomItemChangeKind.removed, id);
    }
    for (final e in now.entries) {
      final was = old[e.key];
      if (was == null) {
        _emit(TomItemChangeKind.added, e.key);
      } else if (was != e.value) {
        _emit(TomItemChangeKind.changed, e.key);
      }
    }
  }

  void _emit(TomItemChangeKind kind, String id) =>
      _changes.add(TomItemChange(kind, id, store: storeId));

  /// Runs [edit] after every edit before it.
  Future<T> _serial<T>(Future<T> Function() edit) {
    final result = _queue.then((_) => edit());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Reads the file again and reports, through [watch], what changed outside
  /// the store since it was last read.
  Future<void> refresh() => _serial(_reload);

  TomItemHome get _home => TomItemHome(store: storeId);

  @override
  Future<TomStoredItem?> read(String id) => _serial(() async {
    final entry = (await _reload()).entryFor(id);
    final item = entry?.item;
    return item == null ? null : TomStoredItem(item.copy(), _home);
  });

  @override
  Stream<TomItem> readAll() async* {
    final file = await _serial(_reload);
    for (final item in file.items) {
      yield item.copy();
    }
  }

  @override
  Future<TomStoredItem> write(TomItem item, {String? container}) =>
      _serial(() async {
        if (readOnly) throw TomStoreReadOnlyException(storeId);
        final lacking = heldFields.lacking(item);
        if (lacking.isNotEmpty) {
          throw TomFieldsNotHeldException(storeId, item.id, lacking);
        }
        final file = await _reload();
        final entry = file.entryFor(item.id);
        if (entry != null && entry.item == null) {
          throw StateError(
            'Item ${item.id} of $storeId cannot be written: ${entry.error}',
          );
        }
        final text = entry == null
            ? file.withInserted(item)
            : file.withItem(entry.index, item);
        if (text != file.text) {
          await _text.write(text);
          _file = TomTodoFile.parse(text);
          _emit(
            entry == null ? TomItemChangeKind.added : TomItemChangeKind.changed,
            item.id,
          );
        }
        final stored = _file!.entryFor(item.id)!.item!;
        return TomStoredItem(stored.copy(), _home);
      });

  @override
  Future<bool> delete(String id) => _serial(() async {
    if (readOnly) throw TomStoreReadOnlyException(storeId);
    final file = await _reload();
    final entry = file.entryFor(id);
    if (entry == null) return false;
    if (entry.item == null) {
      throw StateError(
        'Item $id of $storeId cannot be deleted: ${entry.error}',
      );
    }
    final text = file.withoutTodo(entry.index);
    await _text.write(text);
    _file = TomTodoFile.parse(text);
    _emit(TomItemChangeKind.removed, id);
    return true;
  });

  @override
  Stream<TomItemChange> watch() => _changes.stream;

  /// Closes [watch].
  Future<void> dispose() => _changes.close();
}
