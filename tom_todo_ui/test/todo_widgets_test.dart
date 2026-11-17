/// The todo row, its badges and the details editor, driven on their own:
/// the row reports every change and owns none, the badges show the facets
/// the checkbox cannot, and the editor returns an edited copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_todo_ui/tom_todo_ui.dart';
import 'package:tom_ui_support/tom_ui_support.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 800, child: child)),
);

void main() {
  group('the row', () {
    testWidgets('the checkbox reports a toggle and the title a commit, and '
        'the row changes nothing itself', (tester) async {
      final item = TomTodo(id: 't1', title: 'Plan');
      var toggled = 0;
      final committed = <String>[];
      final controller = TextEditingController(text: item.title);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          TomTodoRow(
            item: item,
            readOnly: false,
            controller: controller,
            focusNode: focus,
            onToggleDone: () => toggled++,
            onCommitTitle: committed.add,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('todo-done-t1')));
      expect(toggled, 1);
      expect(item.status, TomTodoStatus.notStarted);

      await tester.enterText(find.byType(TextField), 'Plan the launch');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(committed, ['Plan the launch']);
      expect(item.title, 'Plan');
    });

    testWidgets('read-only shows the title and offers no control', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Plan');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          TomTodoRow(
            item: TomTodo(id: 't1', title: 'Plan'),
            readOnly: true,
            controller: controller,
            focusNode: focus,
            onToggleDone: () {},
            onCommitTitle: (_) {},
            onDelete: () {},
          ),
        ),
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      expect(find.byType(PopupMenuButton<void>), findsNothing);
    });
  });

  group('the badges', () {
    testWidgets('a status the checkbox cannot express, blockers, open '
        'decisions and dependencies each wear a badge', (tester) async {
      final item = TomTodo(
        id: 'p1',
        title: 'Plan',
        status: TomTodoStatus.blocked,
        priority: TomTodoPriority.high,
        blockedBy: ['legal'],
        dependencies: ['budget'],
        decisions: [
          TomTodoDecision(summary: 'Venue?', decisionNeeded: 'A or B'),
        ],
      );
      expect(TomTodoBadges.hasAny(item), isTrue);
      await tester.pumpWidget(_host(TomTodoBadges(item: item)));
      expect(find.byKey(const Key('tom-todo-has-blockers-p1')), findsOneWidget);
      expect(
        find.byKey(const Key('tom-todo-has-open-decisions-p1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tom-todo-has-dependencies-p1')),
        findsOneWidget,
      );
    });

    test('a plain not-started todo wears none', () {
      expect(TomTodoBadges.hasAny(TomTodo(id: 'x', title: 'x')), isFalse);
    });

    testWidgets('a repeated todo waiting for its next repetition wears '
        'waiting-for-repeat, and the aggregate shows it as a repeat', (
      tester,
    ) async {
      final item = TomTodo(
        id: 'w',
        title: 'Water the plants',
        status: TomTodoStatus.waitingForRepeat,
      );
      expect(TomTodoBadges.hasAny(item), isTrue);
      await tester.pumpWidget(_host(Column(children: [
        TomTodoBadges(item: item),
        const TomTodoStatusIcon(status: TomTodoStatus.waitingForRepeat),
      ])));
      expect(find.text('waiting-for-repeat'), findsOneWidget);
      expect(find.byIcon(Icons.event_repeat), findsOneWidget);
    });

    testWidgets('a todo group wears group, its own icon, and its box does not '
        'complete it (it completes when its members do)', (tester) async {
      final item = TomTodo(
        id: 'g',
        title: 'The release',
        status: TomTodoStatus.group,
        comprisedOf: ['a', 'b'],
      );
      expect(item.isGroup, isTrue);
      expect(item.isDone, isFalse, reason: 'a group is not in the done group');
      expect(TomTodoBadges.hasAny(item), isTrue);
      var toggled = 0;
      final controller = TextEditingController(text: item.title);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(_host(Column(children: [
        TomTodoRow(
          item: item,
          readOnly: false,
          controller: controller,
          focusNode: focus,
          onToggleDone: () => toggled++,
          onCommitTitle: (_) {},
        ),
        const TomTodoStatusIcon(status: TomTodoStatus.group),
      ])));
      expect(find.text('group'), findsOneWidget);
      expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('todo-done-g')));
      expect(toggled, 0, reason: 'the box is disabled for a group');
      expect(
        tester.widget<Checkbox>(find.byKey(const Key('todo-done-g'))).onChanged,
        isNull,
      );
    });
  });

  group('the details editor', () {
    testWidgets('saving returns an edited copy and leaves the original', (
      tester,
    ) async {
      final todo = TomTodo(id: 'd1', title: 'Draft');
      TomTodo? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showTomTodoDetails(
                context,
                todo: todo,
                candidates: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tom-todo-details-title')),
        'Final',
      );
      await tester.tap(find.byKey(const Key('tom-todo-details-save')));
      await tester.pumpAndSettle();
      expect(result?.title, 'Final');
      expect(result, isNot(same(todo)));
      expect(todo.title, 'Draft');
    });
  });

  group('what the extension shows (qim_none-2)', () {
    Widget row(TomTodo item, {bool readOnly = false}) {
      final controller = TextEditingController(text: item.title);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      return _host(TomTodoRow(
        item: item,
        readOnly: readOnly,
        controller: controller,
        focusNode: focus,
        onToggleDone: () {},
        onCommitTitle: (_) {},
      ));
    }

    testWidgets('a user_action todo wears 👤 and a purple title, editable '
        'and read-only alike', (tester) async {
      final item = TomTodo(id: 'u1', title: 'Look at it', userAction: true);
      await tester.pumpWidget(row(item));
      expect(find.byKey(const Key('tom-todo-user-action-u1')), findsOneWidget);
      expect(find.text('👤'), findsOneWidget);
      final surface =
          Theme.of(tester.element(find.byType(TextField))).colorScheme.surface;
      final purple = tomReadableOn(Colors.purple, surface);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.color, purple);

      await tester.pumpWidget(row(item, readOnly: true));
      expect(tester.widget<Text>(find.text('Look at it')).style?.color, purple);
    });

    testWidgets('a todo nobody has to do keeps the default title colour and no '
        'mark', (tester) async {
      await tester.pumpWidget(row(TomTodo(id: 'a1', title: 'Agent work')));
      expect(find.byKey(const Key('tom-todo-user-action-a1')), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).style?.color,
          isNull);
    });

    testWidgets('a todo that blocks others wears ⛓️ with their number, and '
        'its tooltip names them', (tester) async {
      final item = TomTodo(
          id: 'b1', title: 'Publish', blocking: ['c1', 'other/c2']);
      await tester.pumpWidget(_host(TomTodoBadges(item: item)));
      expect(find.text('⛓️ 2'), findsOneWidget);
      final tip = tester.widget<Tooltip>(
          find.byKey(const Key('tom-todo-blocks-b1')));
      expect(tip.message, 'Blocks 2 todos:\nc1\nother/c2');
      expect(TomTodoBadges.hasAny(item), isTrue);
    });

    Future<TomTodo?> openDetails(WidgetTester tester, TomTodo todo,
        Future<void> Function() inDialog) async {
      TomTodo? result;
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showTomTodoDetails(
              context,
              todo: todo,
              candidates: const [
                TomTodoCandidate(id: 'c1', title: 'Consume it', where: 'here'),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await inDialog();
      await tester.tap(find.byKey(const Key('tom-todo-details-save')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('the details edit user_action', (tester) async {
      final todo = TomTodo(id: 'd1', title: 'Decide');
      final result = await openDetails(tester, todo, () async {
        final toggle = find.byKey(const Key('tom-todo-details-user-action'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      });
      expect(result?.userAction, isTrue);
      expect(todo.userAction, isFalse);
    });

    testWidgets('the details show what the todo blocks, read-only, and the '
        'last answer as Markdown under its label', (tester) async {
      final todo = TomTodo(
        id: 'd2',
        title: 'Publish',
        blocking: ['c1', 'other/c9'],
        lastAnswer: '## Published\n\nVersion **1.3.0** is on pub.dev.',
      );
      final result = await openDetails(tester, todo, () async {
        final known = find.byKey(const Key('tom-todo-details-blocks-c1'));
        expect(known, findsOneWidget);
        expect(find.descendant(of: known, matching: find.text('Consume it')),
            findsOneWidget, reason: 'a known todo is named by its title');
        expect(find.byKey(const Key('tom-todo-details-blocks-other/c9')),
            findsOneWidget, reason: 'one in another quest by its reference');
        expect(tester.widget<Chip>(known).onDeleted, isNull,
            reason: 'blocking is derived: it is not edited here');
        final answer = find.byKey(const Key('tom-todo-details-last-answer'));
        await tester.ensureVisible(answer);
        expect(find.descendant(of: answer, matching: find.text('Answer')),
            findsOneWidget);
        expect(find.descendant(of: answer, matching: find.text('Published')),
            findsOneWidget, reason: 'the heading is rendered, not shown raw');
        expect(find.textContaining('##'), findsNothing);
      });
      expect(result?.blocking, ['c1', 'other/c9']);
      expect(result?.lastAnswer, todo.lastAnswer);
    });

    testWidgets('a todo with neither shows no blocks list and no answer', (
      tester,
    ) async {
      await openDetails(tester, TomTodo(id: 'd3', title: 'Plain'), () async {
        expect(find.text('Blocks'), findsNothing);
        expect(find.byKey(const Key('tom-todo-details-last-answer')),
            findsNothing);
      });
    });

    test('tomCopyTodoDetails carries user_action', () {
      final to = TomTodo(id: 'x', title: 'x');
      tomCopyTodoDetails(TomTodo(id: 'x', title: 'x', userAction: true), to);
      expect(to.userAction, isTrue);
    });
  });

  group('readable colours', () {
    test('a tinted chip\'s foreground is readable on its background', () {
      final chip = tomTintedChip(Colors.orange, Colors.white);
      expect(
        tomContrastRatio(chip.foreground, chip.background),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
