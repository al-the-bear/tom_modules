// Tests for the chat suite (§11.1–11.3): the prompt trail, the prompt queue
// (send-next / reorder / retry) and the send coordinator that records each
// exchange. Queue dispatch runs over a faked SDK transport (mirroring
// send_test.dart) so the whole pipeline runs without a socket.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_core_agentic/tom_core_agentic.dart';
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_agentic_ui/tom_agentic_ui.dart';
// `tom_vscode_scripting_api` also exports a `QueuedPromptStatus`; this suite
// asserts against the `tom_core_agentic` one, so hide the scripting-API name.
import 'package:tom_vscode_scripting_api/tom_vscode_scripting_api.dart'
    hide QueuedPromptStatus;

/// A transport double that emits a scripted message sequence for every started
/// query (mirrors send_test.dart). [script] maps the call index to the raw
/// `SDKMessage` JSON maps to stream back, in order.
class _ScriptedTransport implements AgentSdkTransport {
  _ScriptedTransport(this.script);

  final List<Map<String, dynamic>> Function(int call) script;

  final _chunks = StreamController<Map<String, dynamic>>.broadcast();
  int _calls = 0;

  @override
  Stream<Map<String, dynamic>> get chunks => _chunks.stream;

  @override
  Future<void> startQuery(Map<String, dynamic> params) async {
    final streamId = params['streamId'];
    final messages = script(_calls++);
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

/// A SpecSessionStore over a fresh in-memory workspace.
SpecSessionStore _tempSessionStore() =>
    SpecSessionStore.resolveDefault(TomMemoryFileSystem());

Future<AgentConnectionController> _boundConnection() async {
  final store = BridgeChoiceStore.resolveDefault(TomMemoryFileSystem());
  await store.save(const BridgeChoice(host: '127.0.0.1', port: 19900));
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

/// A PromptQueueStore over a fresh in-memory workspace.
PromptQueueStore _tempQueueStore() =>
    PromptQueueStore.resolveDefault(TomMemoryFileSystem());

/// A PromptTrailStore over a fresh in-memory workspace.
PromptTrailStore _tempTrailStore() =>
    PromptTrailStore.resolveDefault(TomMemoryFileSystem());

/// A counter-based id generator for deterministic test ids.
String Function() _ids(String prefix) {
  var n = 0;
  return () => '$prefix-${n++}';
}

void main() {
  group('PromptTrailController', () {
    test('records a request then closes it with the answer', () async {
      final controller = PromptTrailController(
        store: _tempTrailStore(),
        newId: _ids('t'),
        now: () => '2026-06-17T10:00:00Z',
      );

      final id = controller.recordRequest('hello');
      expect(controller.pairs, hasLength(1));
      expect(controller.pairs.single.request.text, 'hello');
      expect(controller.pairs.single.answer, isNull);

      controller.completeAnswer(id, 'hi there');
      expect(controller.pairs.single.answer?.text, 'hi there');
    });

    test('persists pairs and reloads them in a fresh controller', () async {
      final store = _tempTrailStore();
      final first = PromptTrailController(store: store, newId: _ids('t'));
      final id = first.recordRequest('ask');
      first.completeAnswer(id, 'answer');

      await first.saved;
      final reloaded = PromptTrailController(store: store);
      await reloaded.load();
      expect(reloaded.pairs.single.request.text, 'ask');
      expect(reloaded.pairs.single.answer?.text, 'answer');
    });

    test('failAnswer records the error text in place of the answer', () async {
      final controller = PromptTrailController(
        store: _tempTrailStore(),
        newId: _ids('t'),
      );
      final id = controller.recordRequest('boom');
      controller.failAnswer(id, 'connection lost');
      expect(controller.pairs.single.answer?.text, 'connection lost');
    });
  });

  group('PromptQueueController', () {
    Future<PromptQueueController> build({
      required _ScriptedTransport transport,
      PromptQueueStore? queueStore,
      PromptTrailController? trail,
    }) async {
      final send = AgentSendController(
        connection: await _boundConnection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );
      final coordinator = ChatSendCoordinator(
        send: send,
        trail:
            trail ??
            PromptTrailController(store: _tempTrailStore(), newId: _ids('t')),
      );
      return PromptQueueController(
        coordinator: coordinator,
        store: queueStore ?? _tempQueueStore(),
        newId: _ids('q'),
        now: () => '2026-06-17T10:00:00Z',
      );
    }

    test('addPrompt appends a pending item and persists it', () async {
      final store = _tempQueueStore();
      final transport = _ScriptedTransport((_) => [_success('s')]);
      addTearDown(transport.dispose);
      final controller = await build(transport: transport, queueStore: store);

      controller.addPrompt('do A');
      controller.addPrompt('do B');

      expect(controller.items.map((i) => i.originalText), ['do A', 'do B']);
      expect(controller.items.first.status, QueuedPromptStatus.pending);
      // Persisted: a fresh controller over the same store reloads them.
      await controller.saved;
      expect((await store.load()).map((i) => i.originalText), ['do A', 'do B']);
    });

    test('moveUp / moveDown reorder the queue', () async {
      final transport = _ScriptedTransport((_) => [_success('s')]);
      addTearDown(transport.dispose);
      final controller = await build(transport: transport);
      controller.addPrompt('first');
      controller.addPrompt('second');

      controller.moveDown(0);
      expect(controller.items.map((i) => i.originalText), ['second', 'first']);
      controller.moveUp(1);
      expect(controller.items.map((i) => i.originalText), ['first', 'second']);
    });

    test('removeById drops the item', () async {
      final transport = _ScriptedTransport((_) => [_success('s')]);
      addTearDown(transport.dispose);
      final controller = await build(transport: transport);
      final a = controller.addPrompt('keep');
      final b = controller.addPrompt('remove');

      controller.removeById(b.id);
      expect(controller.items.map((i) => i.id), [a.id]);
    });

    test(
      'sendNext dispatches the head pending item and records the trail',
      () async {
        final transport = _ScriptedTransport(
          (_) => [_assistant('done!'), _success('s1')],
        );
        addTearDown(transport.dispose);
        final trail = PromptTrailController(
          store: _tempTrailStore(),
          newId: _ids('t'),
        );
        final controller = await build(transport: transport, trail: trail);
        controller.addPrompt('first task');
        controller.addPrompt('second task');

        await controller.sendNext();

        expect(controller.items.first.status, QueuedPromptStatus.sent);
        expect(controller.items.first.sentAt, isNotNull);
        expect(controller.items[1].status, QueuedPromptStatus.pending);
        // The exchange landed in the trail as a request/answer pair.
        expect(trail.pairs, hasLength(1));
        expect(trail.pairs.single.request.text, 'first task');
        expect(trail.pairs.single.answer?.text, 'done!');
      },
    );

    test('compose expands the prompt before it is sent (§11.5)', () async {
      final transport = _ScriptedTransport(
        (_) => [_assistant('ack'), _success('s')],
      );
      addTearDown(transport.dispose);
      final send = AgentSendController(
        connection: await _boundConnection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );
      final trail = PromptTrailController(
        store: _tempTrailStore(),
        newId: _ids('t'),
      );
      final coordinator = ChatSendCoordinator(
        send: send,
        trail: trail,
        compose: (raw) async => raw.replaceAll('{{who}}', 'Alex'),
      );

      await coordinator.sendNow('hi {{who}}');

      // The trail pair (the actual exchange) carries the *composed* request.
      expect(trail.pairs.single.request.text, 'hi Alex');
      expect(trail.pairs.single.answer?.text, 'ack');
    });

    test(
      'a compose failure is a failed trail pair, not a crash or a send',
      () async {
        final transport = _ScriptedTransport((_) => [_success('s')]);
        addTearDown(transport.dispose);
        final send = AgentSendController(
          connection: await _boundConnection(),
          sessionStore: _tempSessionStore(),
          clientFactory: ({required host, required port}) async =>
              AgentSdkClient(transport),
        );
        final trail = PromptTrailController(
          store: _tempTrailStore(),
          newId: _ids('t'),
        );
        final coordinator = ChatSendCoordinator(
          send: send,
          trail: trail,
          compose: (_) => throw PlaceholderExpressionsUnsupportedError('1 + 1'),
        );

        await coordinator.sendNow(r'compute ${{ 1 + 1 }}');

        // The raw prompt is recorded with the unsupported-expression error; the
        // transport was never queried (nothing streamed).
        expect(trail.pairs.single.request.text, r'compute ${{ 1 + 1 }}');
        expect(
          trail.pairs.single.answer?.text,
          contains('PlaceholderExpressionsUnsupportedError'),
        );
        expect(send.output, isEmpty);
      },
    );

    test(
      'sendNow brackets the send with a turn boundary (§9/§10, OE-10)',
      () async {
        // The streamed answer marks the window during which the §8 tools mutate
        // the document; the turn must open before it and close after it.
        final transport = _ScriptedTransport(
          (_) => [_assistant('did work'), _success('s')],
        );
        addTearDown(transport.dispose);
        final send = AgentSendController(
          connection: await _boundConnection(),
          sessionStore: _tempSessionStore(),
          clientFactory: ({required host, required port}) async =>
              AgentSdkClient(transport),
        );
        final trail = PromptTrailController(
          store: _tempTrailStore(),
          newId: _ids('t'),
        );

        final events = <String>[];
        String? turnId;
        final coordinator = ChatSendCoordinator(
          send: send,
          trail: trail,
          onTurnBegin: (id) {
            turnId = id;
            // No answer has streamed yet — the turn opens before the send.
            events.add('begin output=${send.output}');
          },
          onTurnEnd: () => events.add('end output=${send.output}'),
        );

        await coordinator.sendNow('go');

        // Opened before the send (empty output) and closed after it (answer in),
        // in that order — one bracket around the mutating window.
        expect(events, ['begin output=', 'end output=did work']);
        // The turn id is the trail pair id, so the change-log turn and the trail
        // exchange share an identifier.
        expect(turnId, trail.pairs.single.id);
      },
    );

    test('a turn that fails still closes its boundary (OE-10)', () async {
      final transport = _ScriptedTransport((_) => [_errorResult('boom')]);
      addTearDown(transport.dispose);
      final send = AgentSendController(
        connection: await _boundConnection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );
      final trail = PromptTrailController(
        store: _tempTrailStore(),
        newId: _ids('t'),
      );
      var begins = 0;
      var ends = 0;
      final coordinator = ChatSendCoordinator(
        send: send,
        trail: trail,
        onTurnBegin: (_) => begins++,
        onTurnEnd: () => ends++,
      );

      await coordinator.sendNow('go');

      // The turn opened and closed exactly once even though the send failed —
      // the host's undo group is never left open.
      expect(begins, 1);
      expect(ends, 1);
      expect(trail.pairs.single.answer?.text, contains('boom'));
    });

    test('a compose failure never opens a turn (OE-10)', () async {
      final transport = _ScriptedTransport((_) => [_success('s')]);
      addTearDown(transport.dispose);
      final send = AgentSendController(
        connection: await _boundConnection(),
        sessionStore: _tempSessionStore(),
        clientFactory: ({required host, required port}) async =>
            AgentSdkClient(transport),
      );
      final trail = PromptTrailController(
        store: _tempTrailStore(),
        newId: _ids('t'),
      );
      var begins = 0;
      var ends = 0;
      final coordinator = ChatSendCoordinator(
        send: send,
        trail: trail,
        compose: (_) => throw PlaceholderExpressionsUnsupportedError('1 + 1'),
        onTurnBegin: (_) => begins++,
        onTurnEnd: () => ends++,
      );

      await coordinator.sendNow(r'compute ${{ 1 + 1 }}');

      // Nothing was sent, so nothing could mutate — no turn is opened.
      expect(begins, 0);
      expect(ends, 0);
    });

    test('retry re-dispatches an errored item to success', () async {
      // First dispatch errors; the retry succeeds.
      final transport = _ScriptedTransport(
        (call) => call == 0
            ? [_errorResult('temporary failure')]
            : [_assistant('recovered'), _success('s2')],
      );
      addTearDown(transport.dispose);
      final controller = await build(transport: transport);
      final item = controller.addPrompt('flaky task');

      await controller.sendNext();
      expect(controller.items.single.status, QueuedPromptStatus.error);
      expect(controller.items.single.error, isNotNull);

      await controller.retry(item.id);
      expect(controller.items.single.status, QueuedPromptStatus.sent);
      // The error was cleared on the successful retry.
      expect(controller.items.single.error, isNull);
    });
  });
}
