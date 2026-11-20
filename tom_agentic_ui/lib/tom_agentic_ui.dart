/// The agent and chat UI over `tom_core_agentic`, for any Flutter
/// application with an agent: UI only. The provider and model API, the prompt
/// queue, trail and profile models and the placeholder engine live in
/// `tom_core_agentic`; these widgets and controllers render over them and
/// never own a transport.
///
/// - **Chat**: [ChatComposerPanel] with its [PlaceholderPreview], and the
///   [ChatSendCoordinator] that records a sent prompt in the trail.
/// - **Send**: [AgentSendController] (the send pipeline over the bound
///   connection), [AgentSendPanel], [AgentReconnectBanner].
/// - **Queue and trail**: [PromptQueueController] with [PromptQueueView],
///   [PromptTrailController] with [PromptTrailView].
/// - **Connection**: [AgentConnectionController] (scan, bind, the stored
///   choice) with [AgentConnectionPicker].
/// - **Changes**: [ChangeLog] of [ChangeEntry]s, [ChangeLogPanel],
///   [ChangeReviewPanel] (the three-way review).
///
/// Tom Forge's `tom_forge_agentic` re-exports this package and adds the
/// Forge module, the chat view and the queue and trail editors.
library;

export 'src/changes/change_entry.dart';
export 'src/changes/change_log.dart';
export 'src/changes/change_log_panel.dart';
export 'src/changes/change_review_panel.dart';
export 'src/chat/chat_composer_panel.dart';
export 'src/chat/chat_send_coordinator.dart';
export 'src/chat/placeholder_preview.dart';
export 'src/connection/agent_connection_controller.dart';
export 'src/connection/agent_connection_picker.dart';
export 'src/queue/prompt_queue_controller.dart';
export 'src/queue/prompt_queue_view.dart';
export 'src/send/agent_reconnect_banner.dart';
export 'src/send/agent_send_controller.dart';
export 'src/send/agent_send_panel.dart';
export 'src/trail/prompt_trail_controller.dart';
export 'src/trail/prompt_trail_view.dart';
