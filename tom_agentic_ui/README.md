# Tom Agentic UI

The agent and chat UI over [`tom_core_agentic`](../../core_extension/tom_core_agentic/),
for any Flutter application with an agent. UI only: the provider and model
API, the prompt queue, trail and profile models and the placeholder engine
live in `tom_core_agentic`; these widgets and controllers render over them and
never own a transport.

| Area | What it holds |
| --- | --- |
| Chat | `ChatComposerPanel` (the prompt field, *Add to queue* and *Send now*, a profile picker, the inline `PlaceholderPreview` of the expanded prompt) and `ChatSendCoordinator`, which records a sent prompt in the trail. |
| Send | `AgentSendController` (the send pipeline over the bound connection, the streamed answer, the reconnect phases), `AgentSendPanel`, `AgentReconnectBanner` (the inline strip and the modal decisions while the agent is away). |
| Queue and trail | `PromptQueueController` with `PromptQueueView`, `PromptTrailController` with `PromptTrailView`. |
| Connection | `AgentConnectionController` (scan the bridge ports, bind a server, keep the choice in the workspace's sidecar) with `AgentConnectionPicker`. |
| Changes | `ChangeLog` of `ChangeEntry`s, `ChangeLogPanel`, `ChangeReviewPanel` (the three-way review of a change). |

Tom Forge's `tom_forge_agentic` depends on this package and re-exports it,
adding what needs the Forge shell: the chat module (`AgentChatModule`), the
chat view and the queue and trail editors.

## Usage

```dart
import 'package:tom_agentic_ui/tom_agentic_ui.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';

final connection = AgentConnectionController(
  service: BridgeConnectionService(),
  store: BridgeChoiceStore.resolveDefault(workspace),
);
final send = AgentSendController(
  connection: connection,
  sessionStore: SpecSessionStore.resolveDefault(workspace),
);

Column(
  children: [
    AgentConnectionPicker(controller: connection),
    Expanded(
      child: ChatComposerPanel(
        controller: send,
        onSendNow: (prompt) => send.send(prompt),
        onAddToQueue: (prompt) => queue.add(prompt),
      ),
    ),
  ],
);
```

`example/` runs the picker and the composer over a fake connection: the scan
finds one made-up server, and what the composer sends or queues is listed
instead of reaching an agent.

## License

BSD-3-Clause, see [LICENSE](LICENSE).
