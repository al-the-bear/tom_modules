/// The AI trail view over `tom_llm`'s trails.
///
/// * TRAIL-V1–V3 — every entry kind, two concurrent sessions in two tabs and
///   the All tab, closing a tab, the filter, Copy.
/// * TRAIL-V4–V5 — thinking and long tool results collapse and expand; the
///   view follows new entries until the reader scrolls up.
/// * TRAIL-V6 — the header: memory, a written file, and the memory-only
///   switch.
/// * TRAIL-S1–S4 — sessions: created from the view, internal or bound to a
///   quest folder; the tab menu says which gestures run in a session and
///   renames or removes it; a built-in session can be neither renamed nor
///   removed, and a running one cannot be removed.
/// * TRAIL-N1 — a notice goes to the host's surface when one is bound.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_llm/tom_llm.dart';
import 'package:tom_ai_trail_ui/tom_ai_trail_ui.dart';

void _run(
  LlmTrails trails,
  String session,
  String run, {
  String purpose = 'agent',
  bool end = true,
  String answer = 'The answer has **bold** text.',
}) {
  trails
    ..record(
      session,
      LlmRunStarted(purpose: purpose, providerId: 'hosted'),
      runId: run,
    )
    ..record(session, const LlmUserPrompt(instruction: 'Rename it'), runId: run)
    ..record(session, const LlmSystemInit(model: 'claude-test'), runId: run)
    ..record(
      session,
      const LlmThinkingDelta('First I look.\nThen I act.'),
      runId: run,
    )
    ..record(session, LlmTextDelta(answer), runId: run)
    ..record(
      session,
      LlmToolCall(
        callId: '$run-c1',
        name: 'read_note',
        arguments: const {'sectionId': 'abc'},
      ),
      runId: run,
    )
    ..record(
      session,
      LlmToolResult(
        callId: '$run-c1',
        isError: false,
        text: 'Chapter 1',
        fullLength: 9,
      ),
      runId: run,
    )
    ..record(
      session,
      LlmToolCall(callId: '$run-c2', name: 'write_note'),
      runId: run,
    )
    ..record(
      session,
      LlmToolResult(
        callId: '$run-c2',
        isError: true,
        text: 'E_NOT_FOUND',
        fullLength: 11,
      ),
      runId: run,
    )
    ..record(
      session,
      const LlmRetry(attempt: 2, cause: 'overloaded'),
      runId: run,
    )
    ..record(
      session,
      const LlmUsage(inputTokens: 120, outputTokens: 40, costUsd: 0.0021),
      runId: run,
    );
  if (end) {
    trails.record(
      session,
      LlmRunCompleted(
        report: _report,
        toolCalls: 2,
        duration: Duration(milliseconds: 2300),
      ),
      runId: run,
    );
  }
}

Widget _view(TomAiTrailController controller) => MaterialApp(
  home: Scaffold(body: TomAiTrailView(controller: controller)),
);

TomAiTrailController _controller({List<String>? questFolders}) {
  final controller = TomAiTrailController(trails: LlmTrails());
  if (questFolders != null) {
    controller.questFolders = () async => questFolders;
  }
  return controller;
}

Future<void> _create(
  WidgetTester tester,
  String name, {
  String? questFolder,
}) async {
  await tester.tap(find.byKey(const Key('tom-ai-trail-new-session')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('tom-ai-session-name')), name);
  await tester.pump();
  if (questFolder != null) {
    await tester.tap(find.byKey(const Key('tom-ai-session-kind-quest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tom-ai-session-quest-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(questFolder).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('tom-ai-session-create')));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String id, String item) async {
  await tester.tap(find.byKey(Key('tom-ai-trail-tab-menu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(item)));
  await tester.pumpAndSettle();
}

/// Frames enough for a menu to open or close where a running session's
/// spinner means the tree never settles.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('TRAIL-V1: every entry kind renders: header, thinking, '
      'Markdown text, tool cards with status and result, notices and the '
      'summary [1012]', (tester) async {
    final trails = LlmTrails();
    final c = TomAiTrailController(trails: trails)..select('default');
    addTearDown(c.dispose);
    _run(trails, 'default', 'r1');
    trails.record(
      'default',
      const LlmStall(Duration(seconds: 120)),
      runId: 'r1',
    );
    await tester.pumpWidget(_view(c));

    expect(find.text('Rename it'), findsOneWidget);
    expect(find.textContaining('agent · hosted · claude-test'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    // Collapsed: only the first line, dimmed.
    expect(find.byKey(const Key('tom-ai-trail-thinking-text')), findsNothing);
    expect(find.text('First I look.'), findsOneWidget);
    // Markdown: the bold run is its own span, and the answer is selectable.
    final answer = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.textSpan?.toPlainText() ?? '') == 'The answer has bold text.',
      ),
    );
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        spans.add(span);
        span.children?.forEach(collect);
      }
    }

    collect(answer.textSpan!);
    final bold = spans.firstWhere(
      (s) =>
          s.style?.fontWeight == FontWeight.bold && s.toPlainText() == 'bold',
    );
    expect(bold.style?.fontWeight, FontWeight.bold);
    expect(
      find.ancestor(
          of: find.byWidget(answer), matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    expect(find.text('read_note'), findsOneWidget);
    expect(find.textContaining('"sectionId": "abc"'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('tom-ai-trail-tool-status-r1-c1')))
          .data,
      'done',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('tom-ai-trail-tool-status-r1-c2')))
          .data,
      'error',
    );
    final error = tester.widget<SelectableText>(
      find.byKey(const Key('tom-ai-trail-tool-result-r1-c2')),
    );
    expect(
      error.style?.color,
      Theme.of(tester.element(find.byType(TomAiTrailView))).colorScheme.error,
    );
    expect(
      find.textContaining('Retrying (attempt 2): overloaded.'),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing arrived for 120 s'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('tom-ai-trail-summary'))).data,
      'completed · 2.3 s · 2 tool calls · claude-test · 120 in · 40 out · '
      '\$0.0021',
    );
  });

  testWidgets('TRAIL-V2: two concurrent sessions show in two tabs, each '
      'marked running, and interleaved under All with their names [1012]', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final trails = LlmTrails();
    final c = TomAiTrailController(trails: trails);
    addTearDown(c.dispose);
    await tester.pumpWidget(_view(c));
    _run(
      trails,
      'default',
      'a',
      purpose: 'summarize',
      end: false,
      answer: 'Summary text.',
    );
    _run(trails, 'chat', 'b', end: false, answer: 'Chat text.');
    await tester.pump();

    expect(find.byKey(const Key('tom-ai-trail-tab-all')), findsOneWidget);
    expect(find.byKey(const Key('tom-ai-trail-tab-default')), findsOneWidget);
    expect(find.byKey(const Key('tom-ai-trail-tab-chat')), findsOneWidget);
    expect(
      find.byKey(const Key('tom-ai-trail-running-default')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tom-ai-trail-running-chat')), findsOneWidget);
    expect(c.runningCount, 2);
    // All: both answers, each entry badged with its session.
    expect(find.text('Summary text.'), findsOneWidget);
    expect(find.text('Chat text.'), findsOneWidget);
    expect(find.text('chat'), findsWidgets);

    await tester.tap(find.byKey(const Key('tom-ai-trail-tab-chat')));
    await tester.pump();
    expect(find.text('Chat text.'), findsOneWidget);
    expect(find.text('Summary text.'), findsNothing);

    trails.record('chat', LlmRunCompleted(report: _report), runId: 'b');
    await tester.pump();
    expect(find.byKey(const Key('tom-ai-trail-running-chat')), findsNothing);
    expect(c.runningCount, 1);
  });

  testWidgets('TRAIL-V3: closing a tab clears that session\'s trail; '
      'the filter hides a kind; Copy and Copy all reach the clipboard [1012]', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final trails = LlmTrails();
    final c = TomAiTrailController(trails: trails);
    addTearDown(c.dispose);
    _run(trails, 'default', 'a');
    _run(trails, 'chat', 'b');
    await tester.pumpWidget(_view(c));

    await tester.tap(find.byKey(const Key('tom-ai-trail-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tom-ai-trail-filter-tool')));
    await tester.pumpAndSettle();
    expect(find.text('read_note'), findsNothing);
    expect(c.hidden, {LlmTrailEntryKind.tool});

    await tester.tap(find.byKey(const Key('tom-ai-trail-copy-all')));
    await tester.pump();
    expect(copied.single, contains('[default] agent via hosted'));
    expect(copied.single, contains('[chat] The answer has **bold** text.'));
    expect(copied.single, isNot(contains('read_note')));

    final first = c.entries.first;
    await tester.tap(
      find.byKey(Key('tom-ai-trail-copy-${tomTrailEntryKey(first)}')),
    );
    await tester.pump();
    expect(copied.last, first.plainText);

    await tester.tap(find.byKey(const Key('tom-ai-trail-tab-close-default')));
    await tester.pump();
    expect(trails.sessions, ['chat']);
    expect(find.byKey(const Key('tom-ai-trail-tab-default')), findsNothing);
  });

  testWidgets('TRAIL-V4: thinking and a long tool result expand and '
      'collapse [1012]', (tester) async {
    final trails = LlmTrails();
    final c = TomAiTrailController(trails: trails)..select('default');
    addTearDown(c.dispose);
    trails
      ..record(
        'default',
        const LlmRunStarted(purpose: 'agent', providerId: 't'),
        runId: 'r',
      )
      ..record(
        'default',
        const LlmThinkingDelta('Line one.\nLine two.'),
        runId: 'r',
      )
      ..record(
        'default',
        const LlmToolCall(callId: 'x', name: 'big'),
        runId: 'r',
      )
      ..record(
        'default',
        LlmToolResult(
          callId: 'x',
          isError: false,
          text: 'y' * 1500,
          fullLength: 4000,
        ),
        runId: 'r',
      );
    await tester.pumpWidget(_view(c));

    await tester.tap(find.byKey(const Key('tom-ai-trail-thinking-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('tom-ai-trail-thinking-text')), findsOneWidget);

    SelectableText result() => tester.widget<SelectableText>(
      find.byKey(const Key('tom-ai-trail-tool-result-x')),
    );
    expect(result().data!.length, tomTrailResultPreview + 1);
    expect(
      find.textContaining('The tool answered 4000 characters'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('tom-ai-trail-tool-expand-x')));
    await tester.pump();
    expect(result().data!.length, 1500);
    expect(find.text('Collapse'), findsOneWidget);
  });

  testWidgets('TRAIL-V5: the view follows new entries, and stops while '
      'the reader has scrolled up [1012]', (tester) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final trails = LlmTrails();
    final c = TomAiTrailController(trails: trails)..select('default');
    addTearDown(c.dispose);
    await tester.pumpWidget(_view(c));
    for (var i = 0; i < 6; i++) {
      _run(trails, 'default', 'r$i');
      await tester.pumpAndSettle();
    }
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('tom-ai-trail-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position().pixels, position().maxScrollExtent);

    position().jumpTo(0);
    await tester.pump();
    _run(trails, 'default', 'more');
    await tester.pumpAndSettle();
    expect(position().pixels, 0);

    position().jumpTo(position().maxScrollExtent);
    await tester.pump();
    _run(trails, 'default', 'again');
    await tester.pumpAndSettle();
    expect(position().pixels, position().maxScrollExtent);
  });

  testWidgets('TRAIL-V6: the header says where a session\'s trail is '
      'written, or that it is in memory, and asks before keeping a '
      'memory-only trail on disk [1012]', (tester) async {
    final trails = LlmTrails();
    var kept = false;
    final c = TomAiTrailController(trails: trails)
      ..trailFileFor = (session) => switch (session) {
        'default' => const TomAiTrailFileStatus(
          path: '/w/live-trail.default.md',
          reason: 'set in settings',
        ),
        _ => TomAiTrailFileStatus(
          path: '/w/live-trail.chat.md',
          reason: 'the run drew on an encrypted document.',
          memoryOnly: true,
          keepOnDisk: () async => kept = true,
        ),
      };
    addTearDown(c.dispose);
    _run(trails, 'default', 'a');
    _run(trails, 'chat', 'b');
    await tester.pumpWidget(_view(c));
    expect(find.text('Every session, interleaved by time.'), findsOneWidget);

    c.select('default');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('tom-ai-trail-file'))).data,
      'Written to /w/live-trail.default.md (set in settings).',
    );

    c.select('chat');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tom-ai-trail-keep-on-disk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('/w/live-trail.chat.md'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tom-ai-trail-keep-confirm-ok')));
    await tester.pumpAndSettle();
    expect(kept, isTrue);

    c.trailFileFor = null;
    c.select('default');
    await tester.pump();
    expect(find.byKey(const Key('tom-ai-trail-memory')), findsOneWidget);
  });

  testWidgets('TRAIL-S1: an internal session is created from the trail '
      'view and its tab is shown and selected [1019]', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(_view(c));
    await _create(tester, 'Research notes');

    final session = c.registry.byId('research-notes')!;
    expect(session.kind, LlmSessionKind.internal);
    expect(
      find.byKey(const Key('tom-ai-trail-tab-research-notes')),
      findsOneWidget,
    );
    expect(find.text('Research notes'), findsOneWidget);
    expect(c.selected, 'research-notes');
  });

  testWidgets('TRAIL-S2: a quest session is bound to a folder chosen '
      'from those offered; without a source the quest kind is off [1019]', (
    tester,
  ) async {
    final c = _controller(questFolders: ['/w/quests/garden']);
    addTearDown(c.dispose);
    await tester.pumpWidget(_view(c));
    await _create(tester, 'Garden', questFolder: '/w/quests/garden');
    final session = c.registry.byId('garden')!;
    expect(session.kind, LlmSessionKind.quest);
    expect(session.questFolder, '/w/quests/garden');

    final none = _controller();
    addTearDown(none.dispose);
    await tester.pumpWidget(_view(none));
    await tester.tap(find.byKey(const Key('tom-ai-trail-new-session')));
    await tester.pumpAndSettle();
    final quest = tester.widget<RadioListTile<bool>>(
      find.byKey(const Key('tom-ai-session-kind-quest')),
    );
    expect(quest.enabled, isFalse);
  });

  testWidgets('TRAIL-S3: the tab menu chooses the session for actions '
      'and the agent, renames and removes [1019]', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(_view(c));
    await _create(tester, 'Notes');

    await _menu(tester, 'notes', 'tom-ai-trail-session-actions');
    expect(c.registry.actionSession, 'notes');
    await _menu(tester, 'notes', 'tom-ai-trail-session-agent');
    expect(c.registry.agentSession, 'notes');

    await _menu(tester, 'notes', 'tom-ai-trail-session-rename');
    await tester.enterText(
      find.byKey(const Key('tom-ai-session-name')),
      'Reading',
    );
    await tester.tap(find.byKey(const Key('tom-ai-session-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Reading'), findsOneWidget);
    expect(c.registry.byId('notes')!.name, 'Reading');

    await _menu(tester, 'notes', 'tom-ai-trail-session-remove');
    expect(c.registry.byId('notes'), isNull);
    expect(find.byKey(const Key('tom-ai-trail-tab-notes')), findsNothing);
    expect(c.registry.actionSession, 'default');
    expect(c.registry.agentSession, 'chat');
  });

  testWidgets('TRAIL-S4: a built-in session\'s menu offers no rename or '
      'remove, and a running session is not removed [1019]', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.trails!.record(
      'default',
      const LlmRunStarted(purpose: 'summarize', providerId: 't'),
      runId: 'r1',
    );
    await tester.pumpWidget(_view(c));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('tom-ai-trail-tab-menu-default')));
    await _frames(tester);
    expect(
      find.byKey(const Key('tom-ai-trail-session-actions')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tom-ai-trail-session-rename')), findsNothing);
    expect(find.byKey(const Key('tom-ai-trail-session-remove')), findsNothing);
    await tester.tapAt(Offset.zero);
    await _frames(tester);

    await c.createSession('Busy');
    c.trails!.record(
      'busy',
      const LlmRunStarted(purpose: 'summarize', providerId: 't'),
      runId: 'r1',
    );
    await expectLater(
      c.removeSession('busy'),
      throwsA(isA<LlmSessionException>()),
    );
    expect(c.registry.byId('busy'), isNotNull);
  });

  testWidgets('TRAIL-N1: a copy notice goes to the host\'s surface, by kind', (
    tester,
  ) async {
    final trails = LlmTrails();
    final controller = TomAiTrailController(trails: trails);
    addTearDown(controller.dispose);
    final notices = <(String, String)>[];
    controller.showNotice = (context, {required kind, required message}) =>
        notices.add((kind, message));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    _run(trails, 'default', 'a');
    await tester.pumpWidget(_view(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tom-ai-trail-copy-all')));
    await tester.pumpAndSettle();
    expect(notices, [('trail-copied', 'Trail copied.')]);
  });
}

const _report = LlmCallReport(
  providerId: 'fake',
  modelId: '',
  anchorHash: '',
  promptHash: '',
  tokensIn: 0,
  tokensOut: 0,
  retries: 0,
  wallClockMs: 0,
);
