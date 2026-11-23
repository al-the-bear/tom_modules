/// The source editor's features one by one: markers, the line edits and the
/// clipboard through its state, find, the undo and redo keys (routed to the
/// host, passed by for a host with its own key map, or left to the field for
/// a scratch draft), read-only, the selection from outside and on request,
/// what it reports, and its look.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_file_editors/tom_file_editors.dart';

/// A host keeping the text, like an editor over a session.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.initial,
    this.markers = const [],
    this.readOnly = false,
    this.hostOwnsUndo = true,
    this.handleHistoryKeys = true,
    this.style,
    this.selectionRequest,
    this.log,
  });

  final String initial;
  final List<TomTextMarker> markers;
  final bool readOnly;
  final bool hostOwnsUndo;
  final bool handleHistoryKeys;
  final TomTextSourceStyle? style;
  final ValueListenable<TextSelection?>? selectionRequest;
  final List<String>? log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final key = GlobalKey<TomTextSourceState>();
  late String text = widget.initial;
  TextSelection? selection;
  TextEditingValue? lastValue;
  TextSelection? lastSelection;

  void show(String value, {TextSelection? at}) => setState(() {
    text = value;
    selection = at;
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: TomTextSource(
        key: key,
        text: text,
        selection: selection,
        readOnly: widget.readOnly,
        markers: widget.markers,
        hostOwnsUndo: widget.hostOwnsUndo,
        handleHistoryKeys: widget.handleHistoryKeys,
        style: widget.style,
        selectionRequest: widget.selectionRequest,
        onChanged: (value) => setState(() => text = value),
        onValueChanged: (value) => lastValue = value,
        onSelectionChanged: (value) => lastSelection = value,
        onSelectionMoved: () => widget.log?.add('moved'),
        onFocusLost: () => widget.log?.add('blur'),
        onUndo: () => widget.log?.add('undo'),
        onRedo: () => widget.log?.add('redo'),
      ),
    ),
  );
}

Future<_HostState> _pump(WidgetTester tester, _Host host) async {
  await tester.pumpWidget(host);
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

TextEditingController _controller(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller;

/// The leaf spans the source draws, with their merged styles.
List<TextSpan> _leaves(WidgetTester tester) {
  final span = _controller(tester).buildTextSpan(
    context: tester.element(find.byType(EditableText)),
    withComposing: false,
  );
  final out = <TextSpan>[];
  void walk(InlineSpan s, TextStyle? inherited) {
    if (s is! TextSpan) return;
    final merged = inherited?.merge(s.style) ?? s.style;
    if (s.text != null) out.add(TextSpan(text: s.text, style: merged));
    for (final c in s.children ?? const <InlineSpan>[]) {
      walk(c, merged);
    }
  }

  walk(span, null);
  return out;
}

Future<void> _command(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.metaLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  group('TomLineEdits', () {
    TextEditingValue at(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

    test('TS-LE1: delete takes the caret\'s line with its break', () {
      final out = TomLineEdits.deleteLine(at('a\nbb\nc', 3))!;
      expect(out.text, 'a\nc');
      expect(out.selection.baseOffset, 2);
      expect(TomLineEdits.deleteLine(at('a\nlast', 4))!.text, 'a');
    });

    test('TS-LE2: duplicate repeats the line below, caret on the copy', () {
      final out = TomLineEdits.duplicateLine(at('ab\ncd', 1))!;
      expect(out.text, 'ab\nab\ncd');
      expect(out.selection.baseOffset, 4);
    });

    test('TS-LE3: move up and down swap with the neighbour, nothing at the '
        'edges', () {
      final up = TomLineEdits.moveLineUp(at('one\ntwo', 5))!;
      expect(up.text, 'two\none');
      expect(up.selection.baseOffset, 1);
      expect(TomLineEdits.moveLineUp(at('one\ntwo', 1)), isNull);
      final down = TomLineEdits.moveLineDown(at('one\ntwo', 1))!;
      expect(down.text, 'two\none');
      expect(down.selection.baseOffset, 5);
      expect(TomLineEdits.moveLineDown(at('one\ntwo', 5)), isNull);
    });

    test('TS-LE4: the comment toggles after the indentation, with or '
        'without its space', () {
      final out = TomLineEdits.toggleLineComment(at('  key: 1', 4))!;
      expect(out.text, '  # key: 1');
      expect(out.selection.baseOffset, 6);
      expect(
        TomLineEdits.toggleLineComment(at('  # key: 1', 6))!.text,
        '  key: 1',
      );
      expect(TomLineEdits.toggleLineComment(at('#key', 0))!.text, 'key');
      expect(
        TomLineEdits.toggleLineComment(at('x', 0), prefix: '// ')!.text,
        '// x',
      );
    });

    test('TS-LE5: a caret outside the text edits nothing', () {
      const none = TextEditingValue(text: 'abc');
      expect(TomLineEdits.deleteLine(none), isNull);
      expect(TomLineEdits.duplicateLine(none), isNull);
    });
  });

  group('TomTextSource', () {
    testWidgets('TS-M1: markers underline their range wavy, in the colour of '
        'their severity', (tester) async {
      await _pump(
        tester,
        const _Host(
          initial: 'name: x\nport: eighty',
          markers: [
            TomTextMarker(start: 14, end: 20, message: 'not an integer'),
            TomTextMarker(
              start: 0,
              end: 4,
              message: 'hint',
              severity: TomTextMarkerSeverity.info,
            ),
          ],
        ),
      );
      final leaves = _leaves(tester);
      TextSpan leafOf(String text) => leaves.firstWhere((l) => l.text == text);
      final error = leafOf('eighty').style!;
      expect(error.decoration, TextDecoration.underline);
      expect(error.decorationStyle, TextDecorationStyle.wavy);
      expect(error.decorationColor, const Color(0xFFF44747));
      expect(leafOf('name').style!.decorationColor, const Color(0xFF569CD6));
      expect(
        leaves.where((l) => l.text!.contains('port')).single.style?.decoration,
        isNot(TextDecoration.underline),
      );
      expect(
        tomTextMarkerColor(TomTextMarkerSeverity.warning),
        const Color(0xFFCCA700),
      );
    });

    testWidgets('TS-M2: markers and highlighting draw together', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TomTextSource(
                text: 'key: value',
                readOnly: false,
                highlighter: tomYamlSourceHighlighter(
                  Theme.of(context).colorScheme,
                ),
                markers: const [
                  TomTextMarker(start: 5, end: 10, message: 'bad'),
                ],
              ),
            ),
          ),
        ),
      );
      final leaves = _leaves(tester);
      final key = leaves.firstWhere((l) => l.text == 'key');
      expect(key.style?.color, isNotNull, reason: 'highlighted');
      final value = leaves.firstWhere((l) => l.text!.contains('value'));
      expect(value.style!.decorationStyle, TextDecorationStyle.wavy);
    });

    testWidgets('TS-L1: the line edits through the state change the text as '
        'the user\'s edit; read-only refuses them', (tester) async {
      final host = await _pump(tester, const _Host(initial: 'a\nb\nc'));
      final source = host.key.currentState!;
      source.select(const TextSelection.collapsed(offset: 2));
      expect(source.duplicateLine(), isTrue);
      await tester.pump();
      expect(host.text, 'a\nb\nb\nc');
      expect(host.lastValue!.text, 'a\nb\nb\nc');
      expect(source.moveLineUp(), isTrue);
      await tester.pump();
      expect(host.text, 'a\nb\nb\nc');
      expect(source.deleteLine(), isTrue);
      await tester.pump();
      expect(host.text, 'a\nb\nc');
      expect(source.toggleLineComment(prefix: '# '), isTrue);
      await tester.pump();
      expect(
        host.text.split('\n').where((l) => l.startsWith('# ')),
        hasLength(1),
      );
      final before = host.text.split('\n');
      source.select(const TextSelection.collapsed(offset: 0));
      expect(source.moveLineDown(), isTrue);
      await tester.pump();
      expect(host.text.split('\n'), [before[1], before[0], before[2]]);

      final readOnly = await _pump(
        tester,
        const _Host(key: ValueKey('ro'), initial: 'x\ny', readOnly: true),
      );
      final locked = readOnly.key.currentState!;
      locked.select(const TextSelection.collapsed(offset: 0));
      expect(locked.deleteLine(), isFalse);
      expect(locked.duplicateLine(), isFalse);
      expect(readOnly.text, 'x\ny');
    });

    testWidgets('TS-C1: cut, copy, paste and select all through the state', (
      tester,
    ) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboard};
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
      final host = await _pump(tester, const _Host(initial: 'hello world'));
      final source = host.key.currentState!;
      source.select(const TextSelection(baseOffset: 0, extentOffset: 5));
      expect(source.hasSelection, isTrue);
      await source.copy();
      expect(clipboard, 'hello');
      await source.cut();
      await tester.pump();
      expect(host.text, ' world');
      source.select(const TextSelection.collapsed(offset: 6));
      await source.paste();
      await tester.pump();
      expect(host.text, ' worldhello');
      source.selectAll();
      expect(
        source.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
    });

    testWidgets('TS-F1: the find key opens the find bar, which counts and '
        'steps through the matches', (tester) async {
      await _pump(tester, const _Host(initial: 'one two one'));
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await _command(tester, LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(find.byKey(const Key('tom-text-search')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('tom-text-search')), 'one');
      await tester.pump();
      await tester.tap(find.byKey(const Key('tom-text-search-next')));
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
    });

    testWidgets('TS-U1: the undo and redo keys reach the host\'s history; the '
        'field\'s own undo answers nothing', (tester) async {
      final log = <String>[];
      await _pump(tester, _Host(initial: 'a', log: log));
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await _command(tester, LogicalKeyboardKey.keyZ);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(log.where((e) => e == 'undo' || e == 'redo'), ['undo', 'redo']);
    });

    testWidgets('TS-U2: a host with its own key map gets the keys passed by; '
        'the field\'s undo still answers nothing', (tester) async {
      final log = <String>[];
      final host = await _pump(
        tester,
        _Host(initial: 'a', log: log, handleHistoryKeys: false),
      );
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'ab');
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pump(const Duration(seconds: 1));
      await _command(tester, LogicalKeyboardKey.keyZ);
      await _command(
        tester,
        LogicalKeyboardKey.keyZ,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(log.where((e) => e == 'undo'), isEmpty);
      expect(host.text, 'abc', reason: 'no undo of the field\'s own');
    });

    testWidgets('TS-U3: a scratch draft keeps the field\'s own undo', (
      tester,
    ) async {
      final log = <String>[];
      final host = await _pump(
        tester,
        _Host(initial: 'a', log: log, hostOwnsUndo: false),
      );
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'ab');
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pump(const Duration(seconds: 1));
      await _command(
        tester,
        LogicalKeyboardKey.keyZ,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      await tester.pump();
      expect(log.where((e) => e == 'undo'), isEmpty);
      expect(host.text, 'ab', reason: 'the field undid its own typing');
    });

    testWidgets('TS-S1: text from outside shows with the selection the host '
        'gives, else the caret at the change', (tester) async {
      final host = await _pump(tester, const _Host(initial: 'abc'));
      host.show('abcdef');
      await tester.pump();
      expect(_controller(tester).selection.baseOffset, 6);
      host.show('xyz', at: const TextSelection(baseOffset: 0, extentOffset: 1));
      await tester.pump();
      expect(
        _controller(tester).selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
    });

    testWidgets('TS-S2: a requested selection is shown and reported as a '
        'caret move', (tester) async {
      final request = ValueNotifier<TextSelection?>(null);
      addTearDown(request.dispose);
      final log = <String>[];
      final host = await _pump(
        tester,
        _Host(initial: 'one\ntwo', selectionRequest: request, log: log),
      );
      request.value = const TextSelection(baseOffset: 4, extentOffset: 7);
      await tester.pump();
      expect(
        _controller(tester).selection,
        const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      expect(host.lastSelection, _controller(tester).selection);
      expect(log, contains('moved'));
    });

    testWidgets('TS-S3: losing the focus is reported (the burst ends)', (
      tester,
    ) async {
      final log = <String>[];
      await _pump(tester, _Host(initial: 'a', log: log));
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(log, contains('blur'));
    });

    testWidgets('TS-V1: the style sets the colours, the gutter border and '
        'the current line\'s number', (tester) async {
      const style = TomTextSourceStyle(
        textStyle: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: Color(0xFF00FF00),
        ),
        lineNumberStyle: TextStyle(color: Color(0x80FF0000)),
        background: Color(0xFF101010),
        gutterBackground: Color(0xFF202020),
        gutterBorderColor: Color(0xFF404040),
        highlightCurrentLine: true,
      );
      final host = await _pump(
        tester,
        const _Host(initial: 'a\nb\nc', style: style),
      );
      expect(find.byKey(const Key('tom-text-gutter-border')), findsOneWidget);
      final gutter = tester.widget<Container>(
        find.byKey(const Key('tom-text-gutter')),
      );
      expect(gutter.color, const Color(0xFF202020));
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFF101010),
        ),
        findsOneWidget,
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.style.color, const Color(0xFF00FF00));
      expect(field.style.fontSize, 14);

      host.key.currentState!.select(const TextSelection.collapsed(offset: 2));
      await tester.pump();
      final numbers = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('tom-text-gutter')),
          matching: find.byType(Text),
        ),
      );
      final lines = (numbers.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(lines[1].style!.color!.a, 1.0, reason: 'the caret\'s line');
      expect(lines[0].style, isNull);
    });

    testWidgets('TS-V2: without a style the source looks as before: no '
        'border, the plain gutter', (tester) async {
      await _pump(tester, const _Host(initial: 'a\nb'));
      expect(find.byKey(const Key('tom-text-gutter-border')), findsNothing);
      final numbers = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('tom-text-gutter')),
          matching: find.byType(Text),
        ),
      );
      expect(numbers.data, '1\n2');
    });
  });
}
