# Changelog

## 0.2.0

- Takes `tom_todo_model` ^3.0.0: a todo group (`status: group`, its members in
  `comprised_of`) is read instead of refused. It wears the `group` badge and
  its own status icon (`TomTodoStatusIcon`), and its checkbox is disabled: a
  group is no work itself and completes when its members do.

## 0.1.0

First version, from the Webwork application's `tom_reusable_ui` package, which is split into nine Tom UI modules in `tom_modules` (`tom_ui_support`, `tom_ui_testing`, `tom_host_ui`, `tom_credentials_ui`, `tom_sync_ui`, `tom_calendar_ui`, `tom_file_editors`, `tom_todo_ui`, `tom_ai_trail_ui`). Type and function names are unchanged.
