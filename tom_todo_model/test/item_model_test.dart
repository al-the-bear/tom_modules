/// The item model of 4.0.0: the base fields, the extensions, the item types,
/// the flat todo-file form and the 3.x names.
library;

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

/// An item carrying every field 4.0.0 added, beside a few 3.x ones.
TomItem everyNewField() => TomItem(
  id: '7f3c9e21-0000-4000-8000-000000000001',
  headline: 'Review the mindmap',
  itemTypes: const ['todo', 'reminder'],
  summary: 'Friday review',
  description: 'Go through **every** branch.\n\n- the plan\n- the risks',
  categories: const ['project-alpha', '+review'],
  tags: const ['weekly'],
  status: TomTodoStatus.inProgress,
  flag: true,
  start: DateTime.utc(2026, 11, 20),
  due: DateTime.utc(2026, 11, 21),
  reminders: [
    TomItemReminder(at: '2026-11-20T09:00+01:00'),
    TomItemReminder(before: 'PT1H', time: '17:00', snoozedUntil: null),
  ],
  assignees: const [
    TomItemAddress(address: 'ana@example.com', name: 'Ana', contact: '#ana'),
  ],
  memberships: const [
    TomItemMembership(ref: '#journal-1', order: '2026-11-18T07:30Z'),
    TomItemMembership(ref: '../ideas.webwork#map-1'),
  ],
  links: TomItemLinks(
    external: const [TomTodoReference(path: 'doc/plan.md')],
    related: const [TomItemRelated(ref: '#risk-1', label: 'Risks')],
  ),
  source: 'web:https://example.com/plan',
  created: DateTime.utc(2026, 11, 18, 7, 30, 15),
  updated: DateTime.utc(2026, 11, 19),
  author: 'ana',
  editedBy: 'ben',
  bodyType: 'text/markdown',
  body: '# Plan\n\nText.\n',
  presentation: const {'slide': true, 'layout': 'title'},
  template: true,
  container: TomItemContainer(
    children: [
      const TomItemSlot(ref: '#part-2', embedded: true, alias: 'Part two'),
      TomItemInline(TomItem(id: 'idea-1', headline: 'Sub-idea')),
    ],
  ),
  people: TomItemPeople(
    from: const TomItemAddress(address: 'ana@example.com'),
    to: const [TomItemAddress(address: 'ben@example.com')],
    cc: const [TomItemAddress(address: 'cy@example.com', name: 'Cy')],
  ),
  mail: TomItemMail(
    messageId: 'abc@example.com',
    mailReferences: const ['x@example.com'],
    sent: '2026-11-18T07:00:00Z',
    mailbox: 'INBOX',
    mailFlags: const [r'\Seen'],
  ),
  workflow: TomItemWorkflow(
    userAction: true,
    executionRole: 'idea_author',
    resources: const [],
  ),
);

void main() {
  group('ITEM-F fields and the flat form', () {
    test('ITEM-F1: every field survives toMap → fromMap, nothing lost', () {
      final item = everyNewField();
      final read = TomItem.fromMap(item.toMap());
      expect(read, item);
      expect(read.created, DateTime.utc(2026, 11, 18, 7, 30, 15));
      expect(read.reminders.last.time, '17:00');
      expect(read.links.related.single.label, 'Risks');
      expect(read.container!.children.first, isA<TomItemSlot>());
      final inline = read.container!.children.last as TomItemInline;
      expect(inline.item.headline, 'Sub-idea');
      expect(read.people!.cc.single.name, 'Cy');
      expect(read.mail!.mailFlags, [r'\Seen']);
      expect(read.workflow!.resources, isEmpty);
      expect(read.body, '# Plan\n\nText.\n');
    });

    test('ITEM-F2: every key of the flat form is a field, in field order; '
        'the field set is the D1 field lists flattened', () {
      final keys = everyNewField().toMap().keys.toList();
      expect(keys.every(TomItem.fields.contains), isTrue);
      expect(TomItem.fields.where(keys.contains).toList(), keys);
      // The D1 groups and extensions flattened: title is the headline,
      // references and related the links, every workflow key top-level.
      final flattened = {
        ...TomItem.baseFields.map((f) => f == 'headline' ? 'title' : f),
        ...TomItem.planningFields,
        ...TomItem.dependencyFields,
        'references',
        'related',
        'children',
        'people',
        'mail',
        ...TomItemWorkflow.fields,
      };
      expect(flattened, TomItem.fields);
    });

    test('ITEM-F3: nothing empty is written; status always, resources [] '
        'kept, the lone todo type left out', () {
      final item = TomItem(id: 'a', headline: '');
      expect(item.toMap(), {'id': 'a', 'title': '', 'status': 'not-started'});
      item.workflow = TomItemWorkflow(resources: const []);
      expect(item.toMap()['resources'], isEmpty);
      final typeless = TomItem(id: 'b', itemTypes: const []);
      expect(typeless.toMap()['item_types'], isEmpty, reason: 'not a todo');
      expect(TomItem.fromMap(typeless.toMap()).itemTypes, isEmpty);
    });

    test('ITEM-F4: created and updated keep their time; a value without a '
        'time of day is written as a date', () {
      expect(
        TomItem.encodeDateOrTime(DateTime.utc(2026, 11, 18)),
        '2026-11-18',
      );
      expect(TomItem.encodeDateOrTime(DateTime(2026, 11, 18)), '2026-11-18');
      expect(
        TomItem.encodeDateOrTime(DateTime.utc(2026, 11, 18, 7, 30)),
        '2026-11-18T07:30:00Z',
      );
      expect(
        TomItem.decodeDateOrTime('2026-11-18T08:30+01:00', field: 'created'),
        DateTime.utc(2026, 11, 18, 7, 30),
      );
      expect(
        () => TomItem.decodeDateOrTime('18.11.2026', field: 'created'),
        throwsFormatException,
      );
    });

    test('ITEM-F5: malformed new fields are format errors', () {
      expect(() => TomItemReminder(), throwsFormatException);
      expect(
        () => TomItemReminder(at: '2026-11-20T09:00Z', before: 'PT1H'),
        throwsFormatException,
      );
      expect(
        () => TomItem.fromMap({
          'id': 'a',
          'reminders': [
            {'at': 'x', 'ring': true},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => TomItem.fromMap({
          'id': 'a',
          'children': [
            {r'$ref': '#b', 'id': 'b'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => TomItem.fromMap({'id': 'a', 'start': '2026-11-20T10:00Z'}),
        throwsFormatException,
      );
    });

    test('ITEM-F6: copy is deep, copyWith replaces, equality is by value', () {
      final item = everyNewField();
      final copy = item.copy();
      expect(copy, item);
      copy.container!.children.add(const TomItemSlot(ref: '#x'));
      copy.workflow!.decisions.add(
        TomTodoDecision(summary: 's', decisionNeeded: 'q'),
      );
      expect(item.container!.children, hasLength(2));
      expect(item.workflow!.decisions, isEmpty);
      final changed = item.copyWith(headline: 'Other', flag: false);
      expect(changed.headline, 'Other');
      expect(changed.flag, isFalse);
      expect(changed.id, item.id);
      expect(changed == item, isFalse);
      expect(item.headline, 'Review the mindmap');
    });
  });

  group('ITEM-T item types', () {
    test('ITEM-T1: todo and reminder are stored; the computed ones are '
        'answered from memberships, home and the mail extension', () {
      final item = everyNewField();
      expect(item.types(), {
        TomItemType.todo,
        TomItemType.reminder,
        TomItemType.email,
      });
      final kinds = {
        '#journal-1': TomContainerKind.journal,
        '../ideas.webwork#map-1': TomContainerKind.mindmap,
      };
      expect(
        item.types(TomItemTypeContext(kindOf: (ref) => kinds[ref])),
        TomItemType.values.toSet(),
      );
      final idea = TomItem(id: 'n', itemTypes: const []);
      expect(idea.types(), isEmpty);
      expect(
        idea.types(const TomItemTypeContext(home: TomContainerKind.mindmap)),
        {TomItemType.mindmapNode},
      );
      expect(
        idea.types(
          const TomItemTypeContext(listedIn: [TomContainerKind.journal]),
        ),
        {TomItemType.journalEntry},
        reason: 'a membership recorded on the container (D1 §3.8)',
      );
    });

    test('ITEM-T2: a computed type cannot be set or removed; it follows from '
        'what it is computed from', () {
      final item = TomItem(id: 'a', itemTypes: const []);
      expect(() => item.addType(TomItemType.email), throwsArgumentError);
      expect(
        () => item.removeType(TomItemType.journalEntry),
        throwsArgumentError,
      );
      item.addType(TomItemType.reminder);
      expect(item.itemTypes, ['reminder']);
      item.mail = TomItemMail(messageId: 'm@example.com');
      expect(item.types(), {TomItemType.reminder, TomItemType.email});
      item.mail = null;
      expect(item.types(), {TomItemType.reminder});
      item.removeType(TomItemType.reminder);
      expect(item.itemTypes, isEmpty);
    });

    test('ITEM-T3: a computed type in a file is ignored, an unknown one '
        'kept verbatim', () {
      final item = TomItem.fromMap({
        'id': 'a',
        'item_types': ['email', 'todo', 'later-type'],
      });
      expect(item.itemTypes, ['todo', 'later-type']);
      expect(item.toMap()['item_types'], ['todo', 'later-type']);
      expect(item.types(), {TomItemType.todo});
    });
  });

  group('ITEM-S status none', () {
    test('ITEM-S1: an item not treated as a todo has status none: neither '
        'done nor a group, and the decision rule leaves it alone', () {
      final item = TomItem(id: 'a', status: TomTodoStatus.none);
      expect(item.toMap()['status'], 'none');
      expect(TomItem.fromMap(item.toMap()).status, TomTodoStatus.none);
      expect(item.isDone, isFalse);
      expect(item.isGroup, isFalse);
      final previous = item.copy();
      item.workflow = TomItemWorkflow(
        decisions: [TomTodoDecision(summary: 's', decisionNeeded: 'q')],
      );
      expect(tomApplyDecisionRule(item, previous: previous), isFalse);
      expect(item.status, TomTodoStatus.none);
    });
  });

  group('ITEM-C 3.x compatibility', () {
    test('ITEM-C1: the 3.x names reach the 4.0 fields', () {
      // ignore: deprecated_member_use_from_same_package
      final TomTodo todo = TomItem(
        id: 'a',
        // ignore: deprecated_member_use_from_same_package
        title: 'Old',
        // ignore: deprecated_member_use_from_same_package
        references: const [TomTodoReference(url: 'https://x.example')],
        // ignore: deprecated_member_use_from_same_package
        executionRole: 'author',
      );
      expect(todo.headline, 'Old');
      expect(todo.links.external.single.url, 'https://x.example');
      expect(todo.workflow!.executionRole, 'author');
      // ignore: deprecated_member_use_from_same_package
      todo.decisions.add(TomTodoDecision(summary: 's', decisionNeeded: 'q'));
      expect(todo.workflow!.decisions, hasLength(1));
      // ignore: deprecated_member_use_from_same_package
      todo.title = 'New';
      expect(todo.headline, 'New');
      expect(
        () => TomItem(
          id: 'b',
          links: TomItemLinks(),
          // ignore: deprecated_member_use_from_same_package
          references: const [],
        ),
        throwsArgumentError,
      );
    });

    test('ITEM-C2: reading a workflow forwarder does not make the item '
        'carry an empty workflow', () {
      final item = TomItem(id: 'a');
      // ignore: deprecated_member_use_from_same_package
      expect(item.decisions, isEmpty);
      expect(item.toMap().keys, ['id', 'title', 'status']);
      expect(item, TomItem(id: 'a'));
    });
  });

  group('ITEM-W the todo file writes every set field', () {
    const file = '''
todos:
  - id: a
    title: A
    description: Old.
    status: not-started
    tags: []
    notes: null
    x_note: kept
''';

    test('ITEM-W1: a new field set on an item is written under its key; '
        'its empty keys go with the change, its unknown keys stay', () {
      final parsed = TomTodoFile.parse(file);
      final item = parsed.entries.single.item!.copy()
        ..flag = true
        ..start = DateTime.utc(2026, 11, 20);
      final after = parsed.withItem(0, item);
      expect(
        after,
        'todos:\n'
        '  - id: a\n'
        '    title: A\n'
        '    description: Old.\n'
        '    status: not-started\n'
        '    flag: true\n'
        '    start: "2026-11-20"\n'
        '    x_note: kept\n',
      );
      final reread = TomTodoFile.parse(after).entries.single.item!;
      expect(reread, item);
    });

    test('ITEM-W2: an item the codec reads and nobody changes is not '
        'rewritten, empty keys included', () {
      final parsed = TomTodoFile.parse(file);
      expect(parsed.withItem(0, parsed.entries.single.item!.copy()), file);
    });

    test('ITEM-W3: an item inserted with every new field reads back equal', () {
      final parsed = TomTodoFile.parse(file);
      final after = parsed.withInserted(everyNewField());
      final reread = TomTodoFile.parse(after);
      expect(reread.entries[1].item, everyNewField());
      expect(reread.entries[1].unknownKeys, isEmpty);
    });
  });
}
