# Changelog

## 0.1.0

- The agent and chat views and controllers over `tom_core_agentic`, taken
  out of Tom Forge's `tom_forge_agentic`, which re-exports them: the chat
  composer and placeholder preview, the send coordinator, controller, panel
  and reconnect banner, the prompt queue and trail with their controllers,
  the agent connection controller and picker, and the change log with its
  panels. Their tests moved with them.
- An example: the composer over a fake agent connection.
