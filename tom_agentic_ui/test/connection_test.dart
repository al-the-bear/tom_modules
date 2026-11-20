import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_agentic_ui/tom_agentic_ui.dart';

/// A [BridgeConnectionService] that returns a fixed `port → workspace` table
/// without opening sockets. The default table mirrors the spec's test
/// assumption: a single live server on 19900.
BridgeConnectionService _fakeService({
  Map<int, String> table = const {19900: 'tom_agent_container'},
}) {
  return BridgeConnectionService(
    scanner: ({required host, required minPort, required maxPort}) async =>
        table,
  );
}

/// An in-memory-ish store backed by a temp file, so persistence is exercised
/// without touching the developer's real sidecar.
/// A BridgeChoiceStore over a fresh in-memory workspace.
BridgeChoiceStore _tempStore() =>
    BridgeChoiceStore.resolveDefault(TomMemoryFileSystem());

void main() {
  group('AgentConnectionController', () {
    test('scan populates servers from the discovered table', () async {
      final controller = AgentConnectionController(
        service: _fakeService(),
        store: _tempStore(),
      );

      await controller.scan();

      expect(controller.scanning, isFalse);
      expect(controller.error, isNull);
      expect(controller.servers, hasLength(1));
      expect(controller.servers.single.port, 19900);
      expect(controller.servers.single.workspace, 'tom_agent_container');
      expect(controller.servers.single.status, BridgeServerStatus.available);
    });

    test('bind marks the server bound and persists the choice', () async {
      final store = _tempStore();
      final controller = AgentConnectionController(
        service: _fakeService(),
        store: store,
      );
      await controller.scan();

      controller.bind(controller.servers.single);

      expect(controller.bound, isNotNull);
      expect(controller.bound!.port, 19900);
      expect(controller.bound!.status, BridgeServerStatus.bound);

      // Choice survives into a fresh controller via the shared store.
      final restored = AgentConnectionController(
        service: _fakeService(),
        store: store,
      );
      await controller.saved;
      await restored.loadPersisted();
      expect(restored.boundChoice, isNotNull);
      expect(restored.boundChoice!.port, 19900);
    });

    test(
      'a binding spelled localhost still matches a 127.0.0.1 scan',
      () async {
        // The sidecar and the scan get their host from different places, so a
        // user who retypes "Bridge host" in settings leaves a binding whose
        // spelling differs from the one the scan reports. Comparing the strings
        // showed the bound window as merely available and offered to bind it
        // again — the picker-side face of the same defect the reconnect
        // coordinator showed as a still-gone modal for a live bridge.
        final store = _tempStore();
        await store.save(const BridgeChoice(host: 'localhost', port: 19900));
        final controller = AgentConnectionController(
          service: _fakeService(),
          store: store,
        );

        await controller.loadPersisted();
        await controller.scan();

        expect(controller.servers.single.host, defaultBridgeHost);
        expect(controller.bound, isNotNull);
        expect(controller.bound!.status, BridgeServerStatus.bound);
      },
    );

    test('a failed scan records the error and clears servers', () async {
      final controller = AgentConnectionController(
        service: BridgeConnectionService(
          scanner: ({required host, required minPort, required maxPort}) =>
              throw const SocketException('scan blew up'),
        ),
        store: _tempStore(),
      );

      await controller.scan();

      expect(controller.error, isNotNull);
      expect(controller.servers, isEmpty);
      expect(controller.scanning, isFalse);
    });
  });

  group('AgentConnectionPicker', () {
    testWidgets('lists the live server and binds it on tap', (tester) async {
      final store = _tempStore();
      final controller = AgentConnectionController(
        service: _fakeService(),
        store: store,
      );
      await controller.scan();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgentConnectionPicker(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      // The picker lists the discovered server (workspace + port·status).
      expect(find.text('tom_agent_container'), findsOneWidget);
      expect(find.text('127.0.0.1:19900 · available'), findsOneWidget);

      // Tapping "Bind" binds the server and persists the choice.
      await tester.tap(find.text('Bind'));
      await tester.pumpAndSettle();

      expect(controller.bound, isNotNull);
      expect(controller.bound!.port, 19900);
      await tester.runAsync(() => controller.saved);
      final saved = await tester.runAsync(store.load);
      expect(saved, isNotNull);
      expect(saved!.port, 19900);
      // The bound row now reads "bound" rather than offering a Bind button.
      expect(find.text('bound'), findsOneWidget);
    });
  });
}
