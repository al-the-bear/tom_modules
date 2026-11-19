/// The store side of the item model: the field set, the todo-file store, the
/// in-memory mail store, watch, the index entry and the move between stores.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

const String _file = '''# Garden todos
quest: garden
todos:
  # the beds
  - id: gx1_ajka-plant
    title: Plant the beds
    description: Plant the spring beds.
    status: not-started   # first
    execution_role: gardener
    decisions:
      - summary: When
        decision_needed: Morning or evening?
        decision: Mornings.

  - id: gx2_ajka-water
    title: Water
    description: Twice a week.
    status: in-progress
''';

/// A store holding only [held], over a map: the target that cannot hold
/// what the real stores can.
class _MapStore implements TomItemStore {
  _MapStore(this.storeId, this.heldFields);

  @override
  final String storeId;
  @override
  final TomFieldSet heldFields;
  @override
  bool get readOnly => false;

  final items = <String, TomItem>{};

  @override
  Future<TomStoredItem?> read(String id) async => items[id] == null
      ? null
      : TomStoredItem(items[id]!, TomItemHome(store: storeId));

  @override
  Stream<TomItem> readAll() => Stream.fromIterable(items.values);

  @override
  Future<TomStoredItem> write(TomItem item, {String? container}) async {
    final lacking = heldFields.lacking(item);
    if (lacking.isNotEmpty) {
      throw TomFieldsNotHeldException(storeId, item.id, lacking);
    }
    items[item.id] = item;
    return TomStoredItem(item, TomItemHome(store: storeId));
  }

  @override
  Future<bool> delete(String id) async => items.remove(id) != null;

  @override
  Stream<TomItemChange> watch() => const Stream.empty();
}

/// Every change [store] reports while [body] runs.
Future<List<TomItemChange>> changesOf(
  TomItemStore store,
  Future<void> Function() body,
) async {
  final seen = <TomItemChange>[];
  final sub = store.watch().listen(seen.add);
  await body();
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return seen;
}

TomItemChange _change(TomItemChangeKind kind, String id, String store) =>
    TomItemChange(kind, id, store: store);

void main() {
  group('STORE-F the field set', () {
    test('STORE-F1: all is every field; base is every field outside the '
        'four extensions; an extension adds its keys', () {
      expect(TomFieldSet.all.fields, TomItem.fields);
      for (final e in TomItemExtension.values) {
        expect(TomFieldSet.base.holdsExtension(e), isFalse, reason: e.name);
        expect(TomFieldSet.all.holdsExtension(e), isTrue, reason: e.name);
      }
      expect(TomFieldSet.base.holds('reminders'), isTrue);
      expect(TomFieldSet.base.holds('body'), isTrue);
      expect(TomFieldSet.base.holds('decisions'), isFalse);
      final mail = TomFieldSet.base.withExtensions(const [
        TomItemExtension.mail,
      ]);
      expect(mail.holdsExtension(TomItemExtension.mail), isTrue);
      expect(mail.holds('people'), isFalse);
      expect(TomInMemoryMailStore.held.holds('people'), isTrue);
      expect(TomInMemoryMailStore.held.holds('children'), isFalse);
    });

    test('STORE-F2: lacking names what the item holds and the set does '
        'not, in field order; a set without identity or with a non-field is '
        'refused', () {
      final item = TomItem(id: 'a', headline: 'A')
        ..workflow = TomItemWorkflow(executionRole: 'r', userAction: true)
        ..container = TomItemContainer(
          children: const [TomItemSlot(ref: '#b')],
        );
      expect(TomFieldSet.base.lacking(item), [
        'user_action',
        'execution_role',
        'children',
      ]);
      expect(TomFieldSet.all.lacking(item), isEmpty);
      expect(() => TomFieldSet({'id', 'title'}), throwsArgumentError);
      expect(
        () => TomFieldSet({'id', 'title', 'status', 'colour'}),
        throwsArgumentError,
      );
    });
  });

  group('STORE-T the todo-file store', () {
    late TomMemoryTodoFileText text;
    late TomTodoFileStore store;
    setUp(() {
      text = TomMemoryTodoFileText(_file);
      store = TomTodoFileStore(storeId: 'garden.todo.yaml', text: text);
    });
    tearDown(() => store.dispose());

    test('STORE-T1: reads the file\'s items with their home; every field is '
        'held', () async {
      expect(store.heldFields, TomFieldSet.all);
      final stored = (await store.read('gx1_ajka-plant'))!;
      expect(stored.item.headline, 'Plant the beds');
      expect(stored.item.workflow!.executionRole, 'gardener');
      expect(stored.home, const TomItemHome(store: 'garden.todo.yaml'));
      expect(await store.read('nope'), isNull);
      expect(await store.readAll().map((i) => i.id).toList(), [
        'gx1_ajka-plant',
        'gx2_ajka-water',
      ]);
    });

    test('STORE-T2: a write is a splice: one changed key, every other byte '
        'kept; watch reports the change', () async {
      final item = (await store.read('gx2_ajka-water'))!.item
        ..status = TomTodoStatus.completed;
      final changes = await changesOf(store, () => store.write(item));
      expect(
        text.text,
        _file.replaceFirst('status: in-progress', 'status: completed'),
      );
      expect(changes, [
        _change(TomItemChangeKind.changed, 'gx2_ajka-water', store.storeId),
      ]);
    });

    test('STORE-T3: a write that changes nothing writes nothing and reports '
        'nothing', () async {
      final item = (await store.read('gx1_ajka-plant'))!.item;
      final changes = await changesOf(store, () => store.write(item));
      expect(text.writes, 0);
      expect(changes, isEmpty);
    });

    test('STORE-T4: a new item is added with every field it holds, nothing '
        'empty; it reads back equal', () async {
      final item = TomItem(
        id: 'gx3_ajka-harvest',
        headline: 'Harvest',
        description: 'Beans first.',
        flag: true,
        reminders: [TomItemReminder(at: '2026-11-20T09:00+01:00')],
        memberships: const [TomItemMembership(ref: '#journal')],
        bodyType: 'text/markdown',
        body: 'Notes.\n',
        mail: TomItemMail(messageId: 'm@example.com'),
      );
      final changes = await changesOf(store, () => store.write(item));
      expect(changes, [
        _change(TomItemChangeKind.added, 'gx3_ajka-harvest', store.storeId),
      ]);
      expect(text.text, startsWith(_file));
      expect(text.text, contains('    flag: true\n'));
      expect(text.text, isNot(contains('[]')));
      expect((await store.read('gx3_ajka-harvest'))!.item, item);
    });

    test('STORE-T5: delete removes the item and reports it; a missing id is '
        'false', () async {
      final changes = await changesOf(store, () async {
        expect(await store.delete('gx1_ajka-plant'), isTrue);
        expect(await store.delete('gx1_ajka-plant'), isFalse);
      });
      expect(changes, [
        _change(TomItemChangeKind.removed, 'gx1_ajka-plant', store.storeId),
      ]);
      expect(text.text, isNot(contains('gx1_ajka-plant')));
      expect(text.text, contains('# Garden todos\nquest: garden\n'));
    });

    test('STORE-T6: an edit made outside the store is taken in, reported, '
        'and not written over', () async {
      await store.readAll().toList();
      text.text = text.text.replaceFirst(
        'title: Water\n',
        'title: Water the beds\n',
      );
      final item = (await store.read('gx1_ajka-plant'))!.item
        ..priority = TomTodoPriority.high;
      final changes = await changesOf(store, () async {
        await store.refresh();
        await store.write(item);
      });
      expect(text.text, contains('title: Water the beds\n'));
      expect(text.text, contains('priority: high\n'));
      expect(changes, [
        _change(TomItemChangeKind.changed, 'gx1_ajka-plant', store.storeId),
      ]);
    });

    test('STORE-T7: refresh reports what changed outside the store', () async {
      await store.readAll().toList();
      final changes = await changesOf(store, () async {
        text.text = text.text
            .replaceFirst('status: in-progress', 'status: blocked')
            .replaceFirst(
              RegExp(r'  # the beds\n  - id: gx1_ajka-plant[\s\S]*?\n\n'),
              '',
            );
        text.text +=
            '  - id: gx9_ajka-new\n    title: New\n    description: N.\n'
            '    status: not-started\n';
        await store.refresh();
      });
      expect(changes.toSet(), {
        _change(TomItemChangeKind.removed, 'gx1_ajka-plant', store.storeId),
        _change(TomItemChangeKind.changed, 'gx2_ajka-water', store.storeId),
        _change(TomItemChangeKind.added, 'gx9_ajka-new', store.storeId),
      });
    });

    test('STORE-T8: a read-only store refuses every write; an item the '
        'model refuses cannot be written or deleted', () async {
      final locked = TomTodoFileStore(
        storeId: 'locked',
        text: TomMemoryTodoFileText(_file),
        readOnly: true,
      );
      final item = (await locked.read('gx1_ajka-plant'))!.item;
      await expectLater(
        locked.write(item),
        throwsA(isA<TomStoreReadOnlyException>()),
      );
      await expectLater(
        locked.delete('gx1_ajka-plant'),
        throwsA(isA<TomStoreReadOnlyException>()),
      );
      await locked.dispose();

      final broken = TomTodoFileStore(
        storeId: 'broken',
        text: TomMemoryTodoFileText(
          'todos:\n  - id: a\n    status: sleeping\n',
        ),
      );
      expect(await broken.read('a'), isNull);
      await expectLater(
        broken.write(TomItem(id: 'a', headline: 'A')),
        throwsStateError,
      );
      await expectLater(broken.delete('a'), throwsStateError);
      await broken.dispose();
    });

    test('STORE-T9: edits run one at a time, each on the text the one before '
        'left', () async {
      final a = (await store.read('gx1_ajka-plant'))!.item..flag = true;
      final b = (await store.read('gx2_ajka-water'))!.item..flag = true;
      await Future.wait([store.write(a), store.write(b), store.delete('x')]);
      final items = await store.readAll().toList();
      expect(items.every((i) => i.flag), isTrue);
    });
  });

  group('STORE-M the in-memory mail store', () {
    test('STORE-M1: holds the base fields, mail and people; the home is the '
        'mailbox', () async {
      final store = TomInMemoryMailStore();
      final email = TomItem(
        id: 'mail-1',
        headline: 'Invoice',
        itemTypes: const [],
        status: TomTodoStatus.none,
        description: 'Please pay.',
        mail: TomItemMail(messageId: 'm1@example.com', mailbox: 'INBOX'),
        people: TomItemPeople(
          from: const TomItemAddress(address: 'shop@example.com'),
        ),
      );
      final changes = await changesOf(store, () async {
        await store.write(email);
        await store.write(email.copyWith(flag: true), container: 'Archive');
        await store.delete('mail-1');
      });
      expect(changes, [
        _change(TomItemChangeKind.added, 'mail-1', store.storeId),
        _change(TomItemChangeKind.changed, 'mail-1', store.storeId),
        _change(TomItemChangeKind.removed, 'mail-1', store.storeId),
      ]);
      await store.write(email);
      final stored = (await store.read('mail-1'))!;
      expect(stored.home.container, 'INBOX');
      expect(stored.item.types(), {TomItemType.email});
      await store.dispose();
    });

    test('STORE-M2: a write holding a field outside the set is refused, '
        'naming the fields; nothing is stored', () async {
      final store = TomInMemoryMailStore();
      final todo = TomItem(id: 't', headline: 'T')
        ..workflow = TomItemWorkflow(executionRole: 'r');
      await expectLater(
        store.write(todo),
        throwsA(
          isA<TomFieldsNotHeldException>().having((e) => e.fields, 'fields', [
            'execution_role',
          ]),
        ),
      );
      expect(await store.read('t'), isNull);
      final locked = TomInMemoryMailStore(readOnly: true);
      await expectLater(
        locked.write(TomItem(id: 'x')),
        throwsA(isA<TomStoreReadOnlyException>()),
      );
    });
  });

  group('STORE-I the index entry', () {
    test('STORE-I1: the entry carries id, store, home, types, headline, the '
        'todo fields and the memberships; valueOf answers wire forms', () {
      final item = TomItem(
        id: 'a',
        headline: 'Review',
        description: 'The plan.',
        status: TomTodoStatus.inProgress,
        priority: TomTodoPriority.high,
        flag: true,
        start: DateTime.utc(2026, 11, 20),
        due: DateTime.utc(2026, 11, 21),
        estimate: 'PT1H',
        reminders: [TomItemReminder(before: 'PT1H')],
        tags: const ['weekly'],
        dependencies: const ['b'],
        blockedBy: const ['c'],
        memberships: const [TomItemMembership(ref: '#journal')],
      );
      final entry = TomItemIndexEntry.of(
        TomStoredItem(item, const TomItemHome(store: 's', container: 'list')),
        context: TomItemTypeContext(kindOf: (_) => TomContainerKind.journal),
      );
      expect(entry.store, 's');
      expect(entry.home.container, 'list');
      expect(entry.types, {TomItemType.todo, TomItemType.journalEntry});
      expect(entry.valueOf('types'), ['todo', 'journal-entry']);
      expect(entry.valueOf('status'), 'in-progress');
      expect(entry.valueOf('priority'), 'high');
      expect(entry.valueOf('due'), '2026-11-21');
      expect(entry.valueOf('start'), '2026-11-20');
      expect(entry.valueOf('flag'), isTrue);
      expect(entry.valueOf('memberships'), ['#journal']);
      expect(entry.valueOf('blocked_by'), ['c']);
      expect(entry.valueOf('home'), 's#list');
      expect(entry.valueOf('colour'), isNull);
      for (final facet in TomItemIndexEntry.facets) {
        expect(() => entry.valueOf(facet), returnsNormally, reason: facet);
      }
      expect(() => entry.tags.add('x'), throwsUnsupportedError);
    });
  });

  group('STORE-V the move between stores', () {
    late TomTodoFileStore todos;
    late TomInMemoryMailStore mail;
    setUp(() {
      todos = TomTodoFileStore(
        storeId: 'garden.todo.yaml',
        text: TomMemoryTodoFileText(_file),
      );
      mail = TomInMemoryMailStore();
    });
    tearDown(() async {
      await todos.dispose();
      await mail.dispose();
    });

    test('STORE-V1: the move names the fields the target cannot hold and '
        'refuses until exactly those are confirmed; nothing is written '
        'meanwhile', () async {
      final move = TomItemMove(
        source: todos,
        target: mail,
        id: 'gx1_ajka-plant',
      );
      expect(await move.lostFields(), ['decisions', 'execution_role']);
      await expectLater(move.run(), throwsA(isA<TomItemMoveRefused>()));
      await expectLater(
        move.run(confirmLost: ['decisions']),
        throwsA(isA<TomItemMoveRefused>()),
      );
      expect(await mail.read('gx1_ajka-plant'), isNull);
      expect(await todos.read('gx1_ajka-plant'), isNotNull);
    });

    test('STORE-V2: a confirmed move keeps the id, drops the lost fields, '
        'and the item leaves its source; both stores report it', () async {
      final move = TomItemMove(
        source: todos,
        target: mail,
        id: 'gx1_ajka-plant',
        container: 'Garden',
      );
      final seen = <TomItemChange>[];
      final subs = [
        todos.watch().listen(seen.add),
        mail.watch().listen(seen.add),
      ];
      final moved = await move.run(
        confirmLost: ['execution_role', 'decisions'],
      );
      await Future<void>.delayed(Duration.zero);
      for (final s in subs) {
        await s.cancel();
      }
      expect(moved.item.id, 'gx1_ajka-plant');
      expect(moved.item.headline, 'Plant the beds');
      expect(moved.item.workflow, isNull);
      expect(
        moved.home,
        const TomItemHome(store: 'mail:memory', container: 'Garden'),
      );
      expect(await todos.read('gx1_ajka-plant'), isNull);
      expect(seen, [
        _change(TomItemChangeKind.added, 'gx1_ajka-plant', 'mail:memory'),
        _change(
          TomItemChangeKind.removed,
          'gx1_ajka-plant',
          'garden.todo.yaml',
        ),
      ]);
    });

    test('STORE-V3: nothing lost needs no confirmation; it moves back with '
        'the same id', () async {
      await TomItemMove(
        source: todos,
        target: mail,
        id: 'gx2_ajka-water',
      ).run();
      final back = TomItemMove(
        source: mail,
        target: todos,
        id: 'gx2_ajka-water',
      );
      expect(await back.lostFields(), isEmpty);
      final moved = await back.run();
      expect(moved.item.id, 'gx2_ajka-water');
      expect(moved.item.status, TomTodoStatus.inProgress);
    });

    test('STORE-V4: an item with a body is refused by a store without one; '
        'a missing item, a taken id, one store and a read-only side are '
        'refused', () async {
      final noBody = _MapStore(
        'no-body',
        TomFieldSet(TomFieldSet.base.fields.difference({'body', 'body_type'})),
      );
      await mail.write(
        TomItem(
          id: 'doc',
          headline: 'Doc',
          bodyType: 'text/markdown',
          body: '# Doc\n',
        ),
      );
      final withBody = TomItemMove(source: mail, target: noBody, id: 'doc');
      expect(await withBody.lostFields(), ['body_type', 'body']);
      await expectLater(
        withBody.run(confirmLost: ['body_type', 'body']),
        throwsA(isA<TomItemMoveRefused>()),
      );
      expect(noBody.items, isEmpty);
      await expectLater(
        TomItemMove(source: mail, target: noBody, id: 'nope').run(),
        throwsA(isA<TomItemMoveRefused>()),
      );
      await mail.write(TomItem(id: 'gx2_ajka-water', headline: 'Taken'));
      await expectLater(
        TomItemMove(source: todos, target: mail, id: 'gx2_ajka-water').run(),
        throwsA(isA<TomItemMoveRefused>()),
      );
      await expectLater(
        TomItemMove(source: todos, target: todos, id: 'gx2_ajka-water').run(),
        throwsA(isA<TomItemMoveRefused>()),
      );
      await expectLater(
        TomItemMove(
          source: todos,
          target: TomInMemoryMailStore(storeId: 'ro', readOnly: true),
          id: 'gx2_ajka-water',
        ).run(),
        throwsA(isA<TomStoreReadOnlyException>()),
      );
    });
  });
}
