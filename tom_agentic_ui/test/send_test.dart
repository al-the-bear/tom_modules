// Tests for the editor agent send controller (§7): folding the engine's event
// stream into observable UI state, and the §7.2 session refresh, all over a
// faked SDK transport so the whole pipeline runs without a socket.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_agentic_ui/tom_agentic_ui.dart';
import 'package:tom_vscode_scripting_api/tom_vscode_scripting_api.dart';

/// A transport double that emits a scripted message sequence for every started
/// query (mirrors the engine-level test in tom_core_agentic). [script] maps the
/// `startQuery` params (carrying the serialized `options`, including `resume`)
/// to the raw `SDKMessage` JSON maps to stream back, in order.
class _ScriptedTransport implements AgentSdkTransport {
  _ScriptedTransport(this.script);

  final List<Map<String, dynamic>> Function(Map<String, dynamic> params) script;

  final _chunks = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> started = [];

  @override
  Stream<Map<String, dynamic>> get chunks => _chunks.stream;

  @override
  Future<void> startQuery(Map<String, dynamic> params) async {
    started.add(params);
    final streamId = params['streamId'];
    final messages = script(params);
    unawaited(
      Future<void>(() async {
        for (final message in messages) {
          _chunks.add({'streamId': streamId, 'message': message});
        }
        _chunks.add({'streamId': streamId, 'done': true});
      }),
    );
  }

  @override
  Future<void> cancelQuery(String streamId) async {}

  @override
  void registerTools(String streamId, AgentSdkToolRegistry registry) {}

  @override
  void unregisterTools(String streamId) {}

  @override
  void registerCanUseTool(String streamId, CanUseTool callback) {}

  @override
  void unregisterCanUseTool(String streamId) {}

  Future<void> dispose() => _chunks.close();
}

/// A transport double that streams one assistant chunk and then *stalls* — it
/// never emits the terminal `done`, so the turn stays in flight until the
/// controller [AgentSendController.cancel]s it. Records the stream ids passed to
/// [cancelQuery] so a test can assert the remote query was aborted.
class _StallingTransport implements AgentSdkTransport {
  final _chunks = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> started = [];
  final List<String> cancelled = [];

  @override
  Stream<Map<String, dynamic>> get chunks => _chunks.stream;

  @override
  Future<void> startQuery(Map<String, dynamic> params) async {
    started.add(params);
    final streamId = params['streamId'];
    // One chunk, then silence — no `done`, so the turn never completes on its
    // own; only a cancel ends it.
    unawaited(
      Future<void>(() async {
        _chunks.add({'streamId': streamId, 'message': _assistant('partial')});
      }),
    );
  }

  @override
  Future<void> cancelQuery(String streamId) async {
    cancelled.add(streamId);
  }

  @override
  void registerTools(String streamId, AgentSdkToolRegistry registry) {}

  @override
  void unregisterTools(String streamId) {}

  @override
  void registerCanUseTool(String streamId, CanUseTool callback) {}

  @override
  void unregisterCanUseTool(String streamId) {}

  Future<void> dispose() => _chunks.close();
}

Map<String, dynamic> _assistant(String text) => {
  'type': 'assistant',
  'message': {
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

Map<String, dynamic> _success(String sessionId) => {
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'session_id': sessionId,
  'result': 'ok',
};

Map<String, dynamic> _errorResult(String text) => {
  'type': 'result',
  'subtype': 'error_during_execution',
  'is_error': true,
  'result': text,
};

String? _resumeOf(Map<String, dynamic> params) =>
    (params['options'] as Map?)?['resume'] as String?;

/// A SpecSessionStore over a fresh in-memory workspace.
SpecSessionStore _tempSessionStore() =>
    SpecSessionStore.resolveDefault(TomMemoryFileSystem());

/// A connection controller, optionally bound to 127.0.0.1:19900, without
/// scanning sockets.
Future<AgentConnectionController> _connection({bool bound = true}) async {
  final store = BridgeChoiceStore.resolveDefault(TomMemoryFileSystem());
  if (bound) {
    await store.save(const BridgeChoice(host: '127.0.0.1', port: 19900));
  }
  final controller = AgentConnectionController(
    service: BridgeConnectionService(
      scanner: ({required host, required minPort, required maxPort}) async =>
          const {},
    ),
    store: store,
  );
  await controller.loadPersisted();
  return controller;
}

/// A connection whose successive scans return [scans] in order (the last entry
/// repeats), so the §6.1 reconnect probe can watch the bound server drop and
/// return — possibly serving a different workspace. The caller scans + binds
/// once before driving the controller.
AgentConnectionController _reconnectConnection(List<Map<int, String>> scans) {
  final store = BridgeChoiceStore.resolveDefault(TomMemoryFileSystem());
  var call = 0;
  return AgentConnectionController(
    service: BridgeConnectionService(
      scanner: ({required host, required minPort, required maxPort}) async {
        final result = scans[call < scans.length ? call : scans.length - 1];
        call++;
        return result;
      },
    ),
    store: store,
  );
}

void main() {
  group('AgentSendController.send', () {
    test('streams the answer into output and records the session id', () async {
      final transport = _ScriptedTransport(
        (_) => [_assistant('hello'), _success('s-new')],
      );
      addTearDown(transport.dispose);

      final controller = AgentSendController(
        connection: await _connection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );

      expect(controller.canSend, isTrue);
      await controller.send('hi');

      expect(controller.output, 'hello');
      expect(controller.sessionId, 's-new');
      expect(controller.sending, isFalse);
      expect(controller.error, isNull);
      // The query connected to the bound bridge.
      expect(transport.started, hasLength(1));
    });

    test(
      'refreshes the session id on a session error and retries fresh',
      () async {
        final transport = _ScriptedTransport((params) {
          if (_resumeOf(params) == 'stale-id') {
            return [_errorResult('Session not found: invalid session id')];
          }
          return [_assistant('recovered'), _success('s-fresh')];
        });
        addTearDown(transport.dispose);

        final sessionStore = _tempSessionStore();
        await sessionStore.save('stale-id');
        final controller = AgentSendController(
          connection: await _connection(),
          sessionStore: sessionStore,
          clientFactory: ({required host, required port}) async =>
              AgentSdkClient(transport),
        );

        await controller.send('hi');

        expect(controller.sessionRefreshed, isTrue);
        expect(controller.output, 'recovered');
        expect(controller.sessionId, 's-fresh');
        expect(await sessionStore.load(), 's-fresh');
        // First attempt resumed the stale id; the retry was fresh.
        expect(transport.started, hasLength(2));
        expect(_resumeOf(transport.started[0]), 'stale-id');
        expect(_resumeOf(transport.started[1]), isNull);
      },
    );

    test('with no bound connection sets an error and never connects', () async {
      var factoryCalled = false;
      final controller = AgentSendController(
        connection: await _connection(bound: false),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async {
          factoryCalled = true;
          throw StateError('should not connect');
        },
      );

      expect(controller.canSend, isFalse);
      await controller.send('hi');

      expect(controller.error, isA<StateError>());
      expect(factoryCalled, isFalse);
    });
  });

  group('AgentSendPanel', () {
    testWidgets('renders the streamed answer and disables Send while busy', (
      tester,
    ) async {
      final transport = _ScriptedTransport(
        (_) => [_assistant('streamed!'), _success('s1')],
      );
      addTearDown(transport.dispose);

      final controller = AgentSendController(
        connection: await _connection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgentSendPanel(controller: controller)),
        ),
      );

      // Type a prompt, then tap Send and let the turn finish on the real event
      // loop. Both the tap and the poll run inside runAsync so the faked
      // transport's real-async emits are delivered (a fake-async pump cannot
      // advance them, and polling outside the send's zone would deadlock).
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.send));
        while (controller.sending) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();

      expect(controller.output, 'streamed!');
      expect(controller.sending, isFalse);
      // The streamed answer is rendered in the read-only output area.
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'streamed!',
        ),
        findsOneWidget,
      );
    });
  });

  group('AgentSendController reconnect (§6.1)', () {
    // A zero-duration back-off so the controller runs the protocol without
    // waiting the real 10/30/60 s.
    const instantBackoff = [Duration.zero];

    test(
      'a dropped connection auto-resends the prefixed prompt on reconnect',
      () async {
        final transport = _ScriptedTransport(
          (_) => [_assistant('back online'), _success('s-recon')],
        );
        addTearDown(transport.dispose);

        final connection = _reconnectConnection([
          {19900: 'specs-ws'}, // initial pick
          {19900: 'specs-ws'}, // reconnect probe → same workspace returns
        ]);
        await connection.scan();
        connection.bind(connection.servers.single);

        var factoryCalls = 0;
        final controller = AgentSendController(
          connection: connection,
          sessionStore: _tempSessionStore(),
          reconnectBackoff: instantBackoff,
          clientFactory: ({required host, required port}) async {
            factoryCalls++;
            if (factoryCalls == 1) throw StateError('bridge gone');
            return AgentSdkClient(transport);
          },
        );

        await controller.send('do the thing');

        // First connect dropped; the reconnect probe found the server and re-sent.
        expect(factoryCalls, 2);
        expect(controller.reconnectPhase, ReconnectPhase.idle);
        expect(controller.error, isNull);
        expect(controller.output, 'back online');
        // Only the re-send reached the bridge, carrying the interrupt prefix.
        expect(transport.started, hasLength(1));
        final resent = transport.started.single['prompt'] as String;
        expect(resent, startsWith(AgentProfile.defaultInterruptRetryPrefix));
        expect(resent, contains('do the thing'));
      },
    );

    test(
      'a different workspace pauses for confirmation, then binds and resends',
      () async {
        final transport = _ScriptedTransport(
          (_) => [_assistant('on the other window'), _success('s-other')],
        );
        addTearDown(transport.dispose);

        final connection = _reconnectConnection([
          {19900: 'specs-ws'}, // initial pick
          {19900: 'other-ws'}, // reconnect probe → different workspace
        ]);
        await connection.scan();
        connection.bind(connection.servers.single);

        var factoryCalls = 0;
        final controller = AgentSendController(
          connection: connection,
          sessionStore: _tempSessionStore(),
          reconnectBackoff: instantBackoff,
          clientFactory: ({required host, required port}) async {
            factoryCalls++;
            if (factoryCalls == 1) throw StateError('bridge gone');
            return AgentSdkClient(transport);
          },
        );

        await controller.send('hello there');

        // The protocol paused for the user; nothing re-sent, prompt preserved.
        expect(
          controller.reconnectPhase,
          ReconnectPhase.awaitingDifferentWorkspace,
        );
        expect(controller.differentWorkspaceServer?.workspace, 'other-ws');
        expect(controller.pendingPrompt, 'hello there');
        expect(transport.started, isEmpty);

        await controller.confirmDifferentWorkspace();

        expect(controller.reconnectPhase, ReconnectPhase.idle);
        expect(controller.output, 'on the other window');
        // The new workspace's server is now bound and the prefixed prompt re-sent.
        expect(connection.boundWorkspace, 'other-ws');
        expect(transport.started, hasLength(1));
        expect(
          transport.started.single['prompt'],
          startsWith(AgentProfile.defaultInterruptRetryPrefix),
        );
      },
    );

    test(
      'a different workspace left unconfirmed stays unbound, prompt preserved',
      () async {
        final transport = _ScriptedTransport((_) => [_success('s')]);
        addTearDown(transport.dispose);

        final connection = _reconnectConnection([
          {19900: 'specs-ws'}, // initial pick
          {19900: 'other-ws'}, // reconnect probe → different workspace
        ]);
        await connection.scan();
        connection.bind(connection.servers.single);

        final controller = AgentSendController(
          connection: connection,
          sessionStore: _tempSessionStore(),
          reconnectBackoff: instantBackoff,
          clientFactory: ({required host, required port}) async =>
              throw StateError('bridge gone'),
        );

        await controller.send('keep me');

        // Paused awaiting the user; binding untouched and the prompt preserved.
        expect(
          controller.reconnectPhase,
          ReconnectPhase.awaitingDifferentWorkspace,
        );
        expect(
          controller.error,
          isNull,
        ); // never auto-interrupt; nothing aborted
        expect(controller.pendingPrompt, 'keep me'); // prompt preserved
        expect(transport.started, isEmpty); // nothing re-sent
        expect(connection.boundWorkspace, 'specs-ws'); // binding untouched
      },
    );

    test(
      'still gone surfaces the modal; the user can abort to fail the send',
      () async {
        final transport = _ScriptedTransport((_) => [_success('s')]);
        addTearDown(transport.dispose);

        final connection = _reconnectConnection([
          {19900: 'specs-ws'}, // initial pick
          <int, String>{}, // every probe → gone
        ]);
        await connection.scan();
        connection.bind(connection.servers.single);

        final controller = AgentSendController(
          connection: connection,
          sessionStore: _tempSessionStore(),
          reconnectBackoff: instantBackoff,
          clientFactory: ({required host, required port}) async =>
              throw StateError('bridge gone'),
        );

        await controller.send('keep this prompt');

        // Paused at the still-gone modal; the prompt is preserved, not yet failed.
        expect(controller.reconnectPhase, ReconnectPhase.awaitingStillGone);
        expect(controller.pendingPrompt, 'keep this prompt');
        expect(controller.error, isNull);
        expect(transport.started, isEmpty);

        controller.abortReconnect();

        expect(controller.error, isA<StateError>());
        expect(controller.reconnectPhase, ReconnectPhase.idle);
        expect(transport.started, isEmpty);
      },
    );
  });

  group('AgentSendController.cancel (OE-7)', () {
    test(
      'stops the in-flight turn, keeps the partial output, aborts the query',
      () async {
        final transport = _StallingTransport();
        addTearDown(transport.dispose);

        final controller = AgentSendController(
          connection: await _connection(),
          sessionStore: _tempSessionStore(),
          clientFactory: ({required host, required port}) async =>
              AgentSdkClient(transport),
        );

        // Start the turn but don't await — the transport stalls (no `done`), so
        // the send only completes once we cancel it.
        final pending = controller.send('do the long thing');
        while (controller.output.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(controller.sending, isTrue);

        controller.cancel();
        await pending;

        // The turn is over, the streamed text is retained, and a deliberate stop
        // is not surfaced as an error.
        expect(controller.sending, isFalse);
        expect(controller.output, 'partial');
        expect(controller.error, isNull);
        // The remote query is aborted through the transport's cancel path; the
        // abort cascade runs asynchronously, so give it a moment to land.
        final streamId = transport.started.single['streamId'] as String;
        while (transport.cancelled.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(transport.cancelled, contains(streamId));
      },
    );

    test('is a no-op when nothing is in flight', () async {
      final transport = _StallingTransport();
      addTearDown(transport.dispose);

      final controller = AgentSendController(
        connection: await _connection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );

      controller.cancel();

      expect(controller.sending, isFalse);
      expect(transport.cancelled, isEmpty);
      expect(transport.started, isEmpty);
    });
  });

  group('AgentSendPanel cancel (OE-7)', () {
    testWidgets('shows a Stop button while sending and cancels on tap', (
      tester,
    ) async {
      final transport = _StallingTransport();
      addTearDown(transport.dispose);

      final controller = AgentSendController(
        connection: await _connection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgentSendPanel(controller: controller)),
        ),
      );

      // Start a stalling turn; the composer should swap Send → Stop.
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.send));
        while (controller.output.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();

      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);

      // Tapping Stop cancels the turn and restores the Send button. The abort
      // cascade is asynchronous, so wait for the transport cancel to land too.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.stop));
        while (controller.sending || transport.cancelled.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();

      expect(controller.sending, isFalse);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsNothing);
      final streamId = transport.started.single['streamId'] as String;
      expect(transport.cancelled, contains(streamId));
    });
  });

  group('AgentReconnectBanner modals (§6.1 steps 4–5, OE-8)', () {
    const instantBackoff = [Duration.zero];

    testWidgets(
      'a different-workspace pause is a modal; Reconnect binds and resends',
      (tester) async {
        final transport = _ScriptedTransport(
          (_) => [_assistant('on the other window'), _success('s-other')],
        );
        addTearDown(transport.dispose);

        final connection = _reconnectConnection([
          {19900: 'specs-ws'}, // initial pick
          {19900: 'other-ws'}, // reconnect probe → different workspace
        ]);
        await connection.scan();
        connection.bind(connection.servers.single);

        var factoryCalls = 0;
        final controller = AgentSendController(
          connection: connection,
          sessionStore: _tempSessionStore(),
          reconnectBackoff: instantBackoff,
          clientFactory: ({required host, required port}) async {
            factoryCalls++;
            if (factoryCalls == 1) throw StateError('bridge gone');
            return AgentSdkClient(transport);
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AgentSendPanel(controller: controller)),
          ),
        );

        // Drive the send to the paused phase on the real event loop, then let the
        // phase listener open the modal.
        await tester.runAsync(() => controller.send('hello there'));
        await tester.pumpAndSettle();

        expect(
          controller.reconnectPhase,
          ReconnectPhase.awaitingDifferentWorkspace,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('other-ws'), findsOneWidget);

        // Tapping Reconnect confirms: bind the other workspace and re-send the
        // prefixed prompt. The phase returning to idle dismisses the modal.
        await tester.runAsync(() async {
          await tester.tap(find.text('Reconnect'));
          while (controller.sending ||
              controller.reconnectPhase != ReconnectPhase.idle) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        });
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(connection.boundWorkspace, 'other-ws');
        expect(controller.output, 'on the other window');
        expect(
          transport.started.single['prompt'],
          startsWith(AgentProfile.defaultInterruptRetryPrefix),
        );
      },
    );

    testWidgets('a still-gone pause is a modal; Abort fails the send', (
      tester,
    ) async {
      final transport = _ScriptedTransport((_) => [_success('s')]);
      addTearDown(transport.dispose);

      final connection = _reconnectConnection([
        {19900: 'specs-ws'}, // initial pick
        <int, String>{}, // every probe → gone
      ]);
      await connection.scan();
      connection.bind(connection.servers.single);

      final controller = AgentSendController(
        connection: connection,
        sessionStore: _tempSessionStore(),
        reconnectBackoff: instantBackoff,
        clientFactory: ({required host, required port}) async =>
            throw StateError('bridge gone'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgentSendPanel(controller: controller)),
        ),
      );

      await tester.runAsync(() => controller.send('keep this prompt'));
      await tester.pumpAndSettle();

      expect(controller.reconnectPhase, ReconnectPhase.awaitingStillGone);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Abort'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Abort fails the send and dismisses the modal (the prompt was never
      // re-sent).
      await tester.tap(find.text('Abort'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.error, isA<StateError>());
      expect(controller.reconnectPhase, ReconnectPhase.idle);
      expect(transport.started, isEmpty);
    });
  });
}
