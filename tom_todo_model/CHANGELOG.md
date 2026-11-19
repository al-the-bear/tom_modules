## 4.1.0

The reminder schedule: a todo can keep reminding while it is open.

- `TomItem.remind` (`TomTodoRepeat`): the rule an open item rings by — the
  `repeat` rule forms but `manual` (refused by `check`) — independent of
  `repeat`; `nextRemind` (the next moment, `yyyy-MM-ddTHH:MM` with `Z` or an
  offset, absent once the rule has ended) and `remindCount` (the reminders
  sent). Planning fields (D1 §3.5.1), written after `repeat_count` in the flat
  todo-file form, which now has 62 keys.

## 4.0.0

The item model: `TomItem`, one record for whatever can have a status, a
reminder or a repetition (Webwork D1 §3, D2 §2.1).

- `TomItem` with the base fields every item has — the 3.x todo fields and
  `itemTypes`, `summary`, `categories`, `flag`, `start`, `reminders`
  (`TomItemReminder`), `assignees` (`TomItemAddress`), `memberships`
  (`TomItemMembership`), `links` (`TomItemLinks`: `external`, the 3.x
  `references`, and `related`), `source`, `editedBy`, `bodyType`, `body`,
  `presentation`, `template` — and the extensions `container`
  (`TomItemContainer`: `TomItemSlot` and `TomItemInline` children), `people`
  (`TomItemPeople`), `mail` (`TomItemMail`) and `workflow`
  (`TomItemWorkflow`: the quest tooling's fields). `copyWith`, value
  equality, and a field list per group (`recordFields`, `baseFields`,
  `planningFields`, `dependencyFields`, each extension's `fields`).
- The item types (`TomItemType`): `todo` and `reminder` stored in
  `itemTypes` (`addType`, `removeType`, `hasStoredType`); `journalEntry`,
  `mindmapNode` and `email` computed by `types([TomItemTypeContext])` from
  the memberships, the home and the mail extension, and refused by
  `addType`.
- `TomTodoStatus.none` (`none`): an item currently not treated as a todo. It
  is neither done nor a group, and the decision rule leaves it alone.
- The flat todo-file form grows to 59 keys (`TomItem.fields`); every field
  that is set is written, nothing empty is. An item without `item_types` is
  a `todo`; a computed type found in a file is ignored, an unknown one kept.
- `created` and `updated` keep their time of day: a value without one is
  still written `YYYY-MM-DD`, any other as a UTC timestamp, and both forms
  are read. `recordCreation` and `changeStatus` still record the day.
- The stores (Webwork D2 §2.4): `TomItemStore` (`read`, `readAll`, `write`,
  `delete`, `watch`, `heldFields`, `readOnly`) with `TomItemHome`,
  `TomStoredItem`, `TomItemChange`, and the refusals
  `TomFieldsNotHeldException` and `TomStoreReadOnlyException`; `TomFieldSet`
  and `TomItemExtension`. `TomTodoFileStore` over a `TomTodoFileText`
  (`TomMemoryTodoFileText`), holding every field; `TomInMemoryMailStore` for
  tests. `TomItemIndexEntry`, the item index's entry. `TomItemMove`: a move
  between stores that names the fields lost and runs only once exactly those
  are confirmed, the id kept.
- `TomTodoFile`: `TomTodoFileEntry.item`, `TomTodoFile.items`, `withItem`.
  When an item changes, the keys it holds with an empty value (`null`,
  `[]`, `""`) are dropped with the change; an unchanged item is never
  rewritten.

Breaking:

- A new status value: an exhaustive `switch` over `TomTodoStatus` needs a
  `none` case, and a 3.x reader refuses an item with `status: none` or one of
  the new keys (an unknown value / key), leaving the rest of its file
  readable. The workspace's todo files carry none of them.
- The workflow fields live in `TomItem.workflow`; reading one of the 3.x
  forwarders (`todo.decisions`, …) on an item without workflow fields still
  answers the empty value.

Upgrading from 3.x — every 3.x name is kept, deprecated, and names its
replacement, so code compiles and the analyzer lists what to change:

| 3.x | 4.0 |
| --- | --- |
| `TomTodo` | `TomItem` |
| `TomTodo(title: …)`, `todo.title` | `TomItem(headline: …)`, `item.headline` |
| `references:`, `todo.references` | `links: TomItemLinks(external: …)`, `item.links.external` |
| `decisions`, `userAction`, `scope`, `executionRole`, `qaRole`, `orchestrationRole`, `bundleId`, `derivedFrom`, `feedbackSource`, `filedBy`, `onDone`, `lastAnswer`, `resources`, `claimHold`, `claimFree`, `dueReminded`, `archived`, `deleted` | the same names on `item.workflow` (`TomItemWorkflow`) |
| `TomTodoFileEntry.todo` | `TomTodoFileEntry.item` |
| `TomTodoFile.todos`, `withTodo` | `TomTodoFile.items`, `withItem` |

The deprecated names go once the workspace's packages have moved.

## 3.1.0

- `TomTodo.dueReminded` (`due_reminded`, optional): when the one reminder for
  `due` was sent, `yyyy-MM-ddTHH:MM` with `Z` or an offset, kept verbatim. The
  VS Code extension writes it so the reminder goes out once across windows and
  hosts. Setting `due` to another date clears it, so the new date gets its own
  reminder.
- A 3.0 reader refuses a todo carrying the new field (an unknown key), leaving
  the rest of its file readable: move every reader's lock to 3.1.0.

## 3.0.0

- Todo groups. `TomTodoStatus.group` (`group`): a todo that is a group of
  todos, not work itself; `TomTodo.isGroup`. Its members are
  `TomTodo.comprisedOf` (`comprised_of`): todo ids in the same quest or
  `<quest>/<todo>` from another, as `blocked_by` names its blockers. A
  member's groups (`part_of`) are derived by the VS Code extension and never
  stored, so they are no field here. The extension completes a group once
  every member is completed or cancelled and sets it back to `group` when a
  member is reopened; a `<prefix>*` queue walk passes it. A group is neither
  in the done group (`isDone` is false) nor open work.
- Breaking: the new enum value fails an exhaustive `switch` over
  `TomTodoStatus` until it gains a case, and a 2.x reader refuses a todo with
  the new status or field (an unknown value / key), leaving the rest of its
  file readable. Upgrade every package that reads todo files.

## 2.2.0

- The agent-collaboration fields of the workspace todo schema, all optional:
  - `TomTodo.onDone` (`on_done`, `TomTodoOnDone`): what happens when the todo
    is completed — `quest`, `run`, `todos`, `action` (a list of
    `TomTodoOnDoneAction` `unblock` / `notify` / `queue` / `none`; absent
    means `[none]`, `effectiveActions`), `instructions`, `notify_prompt`,
    `report_to`;
  - `TomTodo.filedBy` (`filed_by`, `TomTodoFiledBy`): the `quest`, `run`,
    `session` and `todo` it was filed from, and `at` (`yyyy-MM-ddTHH:MM` with
    `Z` or an offset, kept verbatim);
  - `TomTodo.resources` (`resources`): the resources it claims; null when
    absent, and an empty list (`resources: []`, claims nothing) is kept;
  - `TomTodo.claimHold` / `TomTodo.claimFree` (`claim_hold` / `claim_free`):
    booleans, written only when true.

  `on_done` and `filed_by` are closed like the schema's objects: an unknown
  key, an unknown action or a malformed `at` is a format error.
- Fixed: a todo file writes a boolean or a number plain (`user_action: true`,
  `repeat_count: 2`); they were quoted and did not read back (the copy of
  tom_basics 3.3.1's `yaml_lines.dart`). The test that holds the copy equal to
  tom_basics' file now finds it in the workspace; it skipped everywhere.

## 2.1.0

- Todo groups may start with a number (`001_cleanup1_akki-x`). `tomTodoGroupOf`
  answers a todo id's group and number: a leading number is part of the
  group's name and only sorts the groups (`001_cleanup`, number 1); after it,
  the prefix runs to the first digit, and that digit run is the number
  (`ccparity_b_panels-7_akds-x` → `ccparity_b_panels-`, 7; `csm2r1` → `csm`,
  2), so every id that starts with a letter keeps its group and number. An id
  without a number after its prefix is in no group (prefix `''`).
- `tomTodoIdPattern` / `tomIsTodoId`: the id rule, now allowing a leading
  digit (at least one letter somewhere). It is the workspace todo schema's
  `id.pattern`, held equal by `_bin/check_todo_model.py`.

## 2.0.0

- Repeated todos. `TomTodoStatus.waitingForRepeat` (`waiting-for-repeat`): a
  repeated todo that was done and waits for its next repetition — an open
  status, not in the done group. `TomTodo.repeat` (`TomTodoRepeat`, the
  schema's `repeat` map: `rule` manual / after / daily / weekly / monthly /
  yearly, `every`, `unit`, `weekdays`, `day` (1–31 or `last`), `nth` (1–5 or
  `last`) with `weekday`, `working_day` (first / last), `month`, `time`,
  `until`, `count`; validated on read and construction), `TomTodo.nextRepeat`
  (`next_repeat`, the moment it is due again, `yyyy-MM-ddTHH:MM` with `Z` or an
  offset, kept verbatim) and `TomTodo.repeatCount` (`repeat_count`). The model
  holds the rule; computing the next moment is the VS Code extension's
  repeated-todo controller.
- Breaking: the new enum value fails an exhaustive `switch` over
  `TomTodoStatus` until it gains a case, and a 1.x reader refuses a todo with
  the new status or fields (an unknown value / key). Upgrade every package that
  reads todo files.

## 1.3.0

- `TomTodo.lastAnswer` — the schema's new `last_answer` field: the final
  answer (Markdown) of the prompt-queue run that executed and completed the
  todo, so the result can be read from the todo. Only the last run's answer is
  kept; the VS Code extension writes it when a `<prefix>*` walk's todo is
  completed and removes it when the todo is archived. Written only when set. An
  older reader (1.2.x and earlier) refuses a todo carrying the field as an
  unknown key and reports it, leaving the rest of its file readable: upgrade
  every package that reads todo files.

## 1.2.0

- `TomTodo.blocking` — the schema's new `blocking` field, the reverse of
  `blocked_by`: the live todos whose `blocked_by` names this one (a bare id in
  the same quest, `<quest>/<todo>` from another), so the relation can be read
  from either end. It is derived: the VS Code extension's todo writers keep it
  in step after every write and `validate_todo_corpus.py` reports a pair that
  does not match. This model reads and writes it as it stands; a writer on it
  that changes `blocked_by` leaves `blocking` to the extension's sync. An older
  reader (1.1.x and earlier) refuses a todo carrying the field as an unknown
  key and reports it, leaving the rest of its file readable: upgrade every
  package that reads todo files.

## 1.1.0

- `TomTodo.userAction` — the schema's new `user_action` field: the todo is the
  user's to do (looking at something, answering, deciding by hand), so an
  agent only prepares and reports and a `<prefix>*` queue walk passes it by.
  Written as `user_action: true` only when set; a value that is not a boolean
  is a format error. An older reader (1.0.x) refuses a todo carrying the field
  as an unknown key and reports it, leaving the rest of its file readable:
  upgrade every package that reads todo files before marking todos.

## 1.0.1

- No longer depends on `tom_basics`. The YAML line writers the codec uses
  (`yaml_lines.dart`, from `tom_basics` 3.3.0) are carried as a private copy,
  so the model fits a dependency graph that takes `tom_basics` by path as well
  as one that takes it from pub.dev. A test in the package holds the copy to
  the original while both are in one workspace. Once `tom_basics` is taken from
  pub.dev throughout, the copy goes and the dependency returns.

## 1.0.0

- First release. The shared todo model and the `*.todo.yaml` codec, moved out
  of Worktracker (`tom_worktracker_core`, where they were the `todo.dart`
  entry point) so that every application that reads or writes a todo — the VS
  Code scripting API, Webwork, Forge and Worktracker itself — uses one model:
  - `TomTodo` with `TomTodoStatus`, `TomTodoPriority`, `TomTodoScope`,
    `TomTodoDecision` and `TomTodoReference`: the workspace todo schema's field
    set, including `due`, `estimate`, `blocked_until`, `archived` / `deleted`
    and the orchestration fields.
  - `TomTodoFile`: parses a todo file and edits it as splices into its own text
    (`withTodo`, `withInserted`, `withoutTodo`, `withMoved`, `withFileKey`), so
    every byte an edit does not touch stays as it was; an item the model
    refuses is kept and reported, never rewritten.
  - The file names (`TomTodoFileName`: the `-archived` / `-deleted` siblings),
    the date-coded ids, relocation between files, and the decisions journal.
