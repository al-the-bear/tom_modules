# Changelog

## 0.2.0

- Takes `tom_todo_model` ^4.1.0, the item model: the widgets take a `TomItem`
  (`TomTodo` is its 3.x name), read the headline, `links.external` and the
  workflow fields under `item.workflow`, and a todo file with the 4.x fields
  is read instead of refused. An item with `status: none` (not treated as a
  todo now) wears its status badge and its own icon.
- A todo group (`status: group`, its members in `comprised_of`) is read
  instead of refused. It wears the `group` badge and its own status icon
  (`TomTodoStatusIcon`), and its checkbox is disabled: a group is no work
  itself and completes when its members do.

## 0.1.0

First version, from the Webwork application's `tom_reusable_ui` package, which is split into nine Tom UI modules in `tom_modules` (`tom_ui_support`, `tom_ui_testing`, `tom_host_ui`, `tom_credentials_ui`, `tom_sync_ui`, `tom_calendar_ui`, `tom_file_editors`, `tom_todo_ui`, `tom_ai_trail_ui`). Type and function names are unchanged.
