# tom_ai_trail_ui

The live trails of AI sessions over tom_llm: a tab per session, thinking,
answers rendered as Markdown, tool calls with their results and a per-run
summary, as a panel, a status-line chip or a phone sheet.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| AI trail | `lib/src/trail/` | The live trails of AI sessions over `tom_llm`'s `LlmTrails` (`TomAiTrailView`): an **All** tab and one tab per session, the run header with its instruction, thinking collapsed and dimmed, answers as Markdown (`tom_file_editors`' `TomMarkdownBody`, compact), each tool call a card with its arguments, status and result, retries and notices as lines, and a per-run summary of model, duration, tokens and cost; a filter, Copy, the header saying where a session's trail is written. Sessions are created, renamed and removed from the tab menu, and an application's runs are docked in their session's tab (`TomDockedAiRun`). As a panel below an editing area with a splitter (`TomAiTrailPanel`, `TomAiTrailSplitter`), a status-line chip (`TomAiTrailChip`) and a phone bottom sheet (`showTomAiTrailSheet`), over one `TomAiTrailController`; the host binds its device state, its trail files and its notice surface (`showNotice`). `TomAiSessionPicker` chooses the session a gesture runs in. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_ai_trail_ui/tom_ai_trail_ui.dart` | everything above | all |

## Dependencies

Flutter, `tom_file_editors`, `tom_llm`, `tom_ui_support`.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:tom_llm/tom_llm.dart';
import 'package:tom_ai_trail_ui/tom_ai_trail_ui.dart';

final trails = LlmTrails(); // the session manager's, in an application
final trail = TomAiTrailController(trails: trails)
  ..showNotice = (context, {required kind, required message}) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

Widget panel() => TomAiTrailView(controller: trail);
```

## Tests

`flutter test` from this folder.
