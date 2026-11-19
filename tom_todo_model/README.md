# Tom Todo Model

The item model of the Tom workspace and the codec for its `*.todo.yaml`
files: one record for whatever can have a status, a reminder or a repetition
— a workspace todo, a reminder, a journal entry, a mindmap node, an email, a
document section.

- **`TomItem`** — one item. Its **base fields** are the same for every item:
  `id`, the stored `itemTypes`, `headline`, `summary`, `description`
  (Markdown: CommonMark with the GitHub extensions), `categories`, `tags`,
  the todo fields (`status`, `priority`, `flag`, `start`, `due`, `estimate`,
  `reminders`, `repeat`, `nextRepeat`, `repeatCount`, `remind`,
  `nextRemind`, `remindCount`, `completedDate`, `completedBy`), the
  dependency fields (`dependencies`, `blockedBy`, `blocking`,
  `blockedUntil`, `comprisedOf`), `assignees`, `memberships`,
  `links` (`external`, the todo schema's `references`, and `related`),
  `source`, `notes`, `created`, `updated`, `author`, `editedBy`, and the body
  (`bodyType`, a MIME type; `body`; `presentation`; `template`). The four
  **extensions** are optional facets, present only when used:
  `container` (`children`: reference slots and inline items), `people`
  (`from`, `to`, `cc`, `bcc`), `mail` (an item with it is an email) and
  `workflow` (the quest tooling's fields: `decisions`, `userAction`, `scope`,
  the roles, `filedBy`, `onDone`, `lastAnswer`, `resources`, `claimHold`,
  `claimFree`, `dueReminded`, `archived`, `deleted`). `TomItem.recordFields`,
  `baseFields`, `planningFields`, `dependencyFields` and each extension's
  `fields` are the field list per group.
  - **Status.** Every item has one: a todo status (`not-started`,
    `in-progress`, `blocked`, `decision-needed`, `waiting-for-repeat`,
    `completed`, `cancelled`), `group` (a todo group, not work itself), or
    `none` — an item currently not treated as a todo, which stays out of the
    todo and reminder handling until it gets a todo status.
  - **Item types.** `todo` and `reminder` are stored (`itemTypes`);
    `journal-entry`, `mindmap-node` and `email` are computed by
    `types([TomItemTypeContext])` from the item's memberships, its home and
    its mail extension, and cannot be set (`addType` refuses them).
  - **Dates.** `due`, `start` and `completedDate` are date-only; `created`
    and `updated` keep their time of day (a value without one is a date).
    `estimate` is a verbatim ISO-8601 duration.
  - The item is mutable, with `copy()`, `copyWith(...)` and value equality.
- **The flat form** — `TomItem.toMap` / `fromMap` and `TomItem.fields`: the
  item as a todo file holds it — `title` for the headline, `references` and
  `related` for the links, the planning, dependency and workflow fields as
  top-level keys, `children`, `people` and `mail` as mappings. Every field
  that is set is written, nothing empty is; an item without `item_types` is
  a `todo`. `fromMap` is the wire boundary: it refuses a value the schema
  does not allow, with the reason. The workspace `todo.schema.json` has
  exactly these properties.
- **`TomTodoFile`** — parses a todo file and edits it **as splices into its
  own text**: changing one item rewrites only the keys that changed, so the
  rest of the file — other items, comments between and around them, key
  order, block scalars, keys this model does not know — stays byte for byte.
  (A key that is rewritten is written fresh, together with any comment on its
  line.) When an item changes, the keys it holds with an empty value
  (`null`, `[]`) go with the change. An item the model refuses is listed with
  its reason and is never rewritten. Every todo file of the workspace reads
  and writes back unchanged (`test/workspace_round_trip_test.dart`).
- **The stores** — every item has one home, a store and the container in
  it, and every store answers `TomItemStore`: `read` (the item with its
  `TomItemHome`), `readAll`, `write` (refused, nothing written, when the item
  holds a field outside the store's `heldFields` — `TomFieldsNotHeldException`
  naming them — or the store is `readOnly`), `delete` and `watch`
  (`TomItemChange`: added, changed, removed, by id). `TomFieldSet` declares
  what a store holds (`all`, `base`, `withExtensions`, `lacking`).
  - `TomTodoFileStore` — a `*.todo.yaml` file over `TomTodoFile`: every
    field held, every edit a splice, the text read again before each edit
    so a change made outside is taken in and reported, never written over;
    the file's text comes through `TomTodoFileText` (the application binds
    the file; `TomMemoryTodoFileText` holds it in memory).
  - `TomInMemoryMailStore` — emails in memory (the base fields, `mail`,
    `people`), for tests: nothing here reads real mail.
  - `TomItemIndexEntry` — what the item index gathers per item: id, store,
    home, types, headline, description, the todo fields, tags, dependencies,
    memberships; `valueOf(facet)` in wire form.
  - `TomItemMove` — moves an item between stores, id kept: `lostFields`
    names what the target cannot hold, `run` refuses until exactly those are
    confirmed, and refuses an item with a body for a store without one.
- **File names, ids, relocation, decisions** — `TomTodoFileName` (a todo
  file's `-archived` and `-deleted` siblings), the date-coded ids
  (`<base>_<date code>-<what>`), the id rule (`tomTodoIdPattern`,
  `tomIsTodoId`) and an id's group and number (`tomTodoGroupOf`: a leading
  number names the group and sorts it, `001_cleanup1` is todo 1 of
  `001_cleanup`), moving a todo between files, and the decisions journal an
  archived todo's decisions are copied into.
- **The 3.x names** — `TomTodo` is a deprecated alias of `TomItem`, and the
  3.x members are kept deprecated, each naming what replaces it (`title` →
  `headline`, `references` → `links.external`, the workflow fields →
  `workflow`, `TomTodoFileEntry.todo` → `item`, `TomTodoFile.todos` →
  `items`, `withTodo` → `withItem`). See the CHANGELOG for the upgrade.

The package reaches no `dart:io` and no Flutter: it works on the text of a
file, and reading and writing the file is the application's. A browser build
can use it.

## Example

```dart
import 'package:tom_todo_model/tom_todo_model.dart';

void main() {
  final file = TomTodoFile.parse('''
quest: garden
todos:
  # the beds
  - id: gx1_ajka-plant
    title: Plant the beds
    status: not-started   # first
''');
  final entry = file.entryFor('gx1_ajka-plant')!;
  final done = entry.item!.copy()
    ..changeStatus(TomTodoStatus.completed, on: DateTime(2026, 10, 21));
  // Only the edited keys are rewritten; `# the beds` and the other items stay.
  print(file.withItem(entry.index, done));
}
```

See `example/tom_todo_model_example.dart` for a runnable version.

## Where it is used

The VS Code extension's scripting API (`tom_vscode_scripting_api`), Webwork,
Forge and Worktracker read and write items through this one model; Webwork's
document section is a `TomItem` with its part. The schema the flat form
follows is the workspace's `todo.schema.json`.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
