import 'package:flutter/material.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';

import 'agent_connection_controller.dart';

/// The *port · workspace · status* server picker (§6, Q4).
///
/// Lists every live VS Code bridge the [controller] discovered, highlights the
/// bound one, and binds the tapped server (persisting the choice). A header row
/// carries the rescan affordance and reflects scan/error/empty states.
class AgentConnectionPicker extends StatelessWidget {
  const AgentConnectionPicker({super.key, required this.controller});

  final AgentConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme),
            const Divider(height: 1),
            Expanded(child: _body(theme)),
          ],
        );
      },
    );
  }

  Widget _header(ThemeData theme) {
    final bound = controller.bound;
    final boundChoice = controller.boundChoice;
    final String subtitle;
    if (bound != null) {
      subtitle = 'Bound to ${bound.workspace} · :${bound.port}';
    } else if (boundChoice != null) {
      subtitle = 'Bound :${boundChoice.port} (offline)';
    } else {
      subtitle = 'No server bound';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.cable, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VS Code bridge',
                    style: theme.textTheme.labelLarge),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (controller.scanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Rescan ports 19900–19909',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: controller.scan,
            ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (controller.error != null) {
      return _centered(
        theme,
        Icons.error_outline,
        'Scan failed:\n${controller.error}',
        theme.colorScheme.error,
      );
    }
    if (controller.scanning && controller.servers.isEmpty) {
      return _centered(theme, Icons.search, 'Scanning for VS Code servers…',
          theme.colorScheme.onSurfaceVariant);
    }
    if (controller.servers.isEmpty) {
      return _centered(
        theme,
        Icons.search_off,
        'No live VS Code server found on 19900–19909.\nOpen a window and rescan.',
        theme.colorScheme.onSurfaceVariant,
      );
    }
    return ListView.separated(
      itemCount: controller.servers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _ServerTile(
        server: controller.servers[i],
        onBind: () => controller.bind(controller.servers[i]),
      ),
    );
  }

  Widget _centered(ThemeData theme, IconData icon, String text, Color color) {
    // Scrollable so the empty/scanning/error states never overflow the short
    // bottom panel (§5) — the picker can be hosted in a region only a few dozen
    // pixels tall.
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in the picker: *port · workspace · status*, bound rows accented.
class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.onBind});

  final BridgeServer server;
  final VoidCallback onBind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBound = server.status == BridgeServerStatus.bound;
    return ListTile(
      dense: true,
      selected: isBound,
      leading: Icon(
        isBound ? Icons.check_circle : Icons.dns_outlined,
        size: 18,
        color: isBound
            ? Colors.green.shade400
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(server.workspace,
          style: const TextStyle(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${server.host}:${server.port} · ${server.status.token}',
        style: TextStyle(
            fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: isBound
          ? Text('bound',
              style: TextStyle(
                  fontSize: 11, color: Colors.green.shade400))
          : TextButton(onPressed: onBind, child: const Text('Bind')),
      onTap: onBind,
    );
  }
}
