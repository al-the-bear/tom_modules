/// A file's source — a monospaced editor with line numbers,
/// the file kind's highlighting and search in the file. The Markdown source,
/// the plain-text editor, the `.env` raw view and the YAML source are all
/// this editor.
///
/// The editor holds no history of its own. Every change is reported, and the
/// host writes it through the file's session as a grouped edit, so a burst of
/// typing is one entry in the file's history; a caret move ends the burst
/// ([TomTextSource.onSelectionMoved]). The undo and redo keys are routed to
/// that history, and the text field's own undo is off. Text changed from
/// outside (an undo, a redo, another view) puts the caret at the change.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

/// The source editor's line height, as a multiple of its font size; the
/// gutter is laid out on the same lines.
const double _lineHeight = 1.45;
const double _fontSize = 13;

/// A source editor.
class TomTextSource extends StatefulWidget {
  const TomTextSource({
    super.key,
    required this.text,
    required this.onChanged,
    required this.readOnly,
    this.onUndo,
    this.onRedo,
    this.onSelectionMoved,
    this.verticalController,
    this.highlighter,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final bool readOnly;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// The caret moved, or the selection changed, without the text changing:
  /// the typing burst in progress ends.
  final VoidCallback? onSelectionMoved;

  /// The vertical scroll position, for a split view to follow.
  final ScrollController? verticalController;

  /// The kind's highlighting, through the one highlighter interface; none
  /// for plain text. A kind styled from the Material colours builds it from
  /// the context's colour scheme (e.g. `tomYamlSourceHighlighter`).
  final SyntaxHighlighter? highlighter;

  @override
  State<TomTextSource> createState() => TomTextSourceState();
}

/// The source editor's state: what an outline, a tree or the shell reach.
class TomTextSourceState extends State<TomTextSource> {
  late final _HighlightController _text = _HighlightController(
    text: widget.text,
  );
  final FocusNode _focus = FocusNode();
  late final ScrollController _vertical =
      widget.verticalController ?? ScrollController();
  final ScrollController _horizontal = ScrollController();
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _searching = false;
  int _match = -1;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void didUpdateWidget(TomTextSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _text.text) {
      _showing = true;
      _text.value = TextEditingValue(
        text: widget.text,
        selection: tomCaretAtChange(_text.text, widget.text),
      );
      _lastSelection = _text.selection;
      _showing = false;
    }
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    _focus.dispose();
    if (widget.verticalController == null) _vertical.dispose();
    _horizontal.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// True while the source shows text from outside.
  var _showing = false;
  TextSelection? _lastSelection;

  void _onText() {
    if (_showing) return;
    if (_text.text != widget.text) {
      _lastSelection = _text.selection;
      widget.onChanged(_text.text);
    } else if (_text.selection != _lastSelection) {
      _lastSelection = _text.selection;
      widget.onSelectionMoved?.call();
    }
  }

  double get _rowHeight => _fontSize * _lineHeight;

  /// Scrolls so that 0-based [line] is in view and puts the caret on it.
  void jumpToLine(int line) {
    final lines = _text.text.split('\n');
    var offset = 0;
    for (var i = 0; i < line && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    _text.selection = TextSelection.collapsed(offset: offset);
    _scrollToLine(line);
  }

  void _scrollToLine(int line) {
    if (!_vertical.hasClients) return;
    final target = math.max(0.0, line * _rowHeight - 3 * _rowHeight);
    _vertical.jumpTo(math.min(target, _vertical.position.maxScrollExtent));
  }

  /// Selects [start]..[end] and scrolls its first line into view — a YAML
  /// tree node selecting its source. The source takes focus, since
  /// an unfocused field does not draw its selection: a node that selected its
  /// text invisibly would look as though the click did nothing.
  void selectRange(int start, int end) {
    final length = _text.text.length;
    _focus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: math.min(start, length),
      extentOffset: math.min(end, length),
    );
    _scrollToLine(
      '\n'.allMatches(_text.text.substring(0, math.min(start, length))).length,
    );
  }

  /// Opens the find bar.
  void openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _queryFocus.requestFocus(),
    );
  }

  List<int> get _matches {
    final q = _query.text;
    if (q.isEmpty) return const [];
    final hay = _text.text.toLowerCase();
    final needle = q.toLowerCase();
    final out = <int>[];
    var at = hay.indexOf(needle);
    while (at != -1) {
      out.add(at);
      at = hay.indexOf(needle, at + math.max(1, needle.length));
    }
    return out;
  }

  void _step(int by) {
    final matches = _matches;
    if (matches.isEmpty) return;
    setState(() => _match = (_match + by) % matches.length);
    final start = matches[_match];
    _text.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + _query.text.length,
    );
    _scrollToLine('\n'.allMatches(_text.text.substring(0, start)).length);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    if (!command) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyZ) {
      (keys.isShiftPressed ? widget.onRedo : widget.onUndo)?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      widget.onRedo?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      openSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: _lineHeight,
      color: scheme.onSurface,
    );
    const strut = StrutStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: _lineHeight,
      forceStrutHeight: true,
    );
    _text
      ..scheme = scheme
      ..highlighter = widget.highlighter
      ..query = _searching ? _query.text : '';
    final lines = _text.text.split('\n');
    final widest = lines.fold<int>(0, (m, l) => math.max(m, l.length));
    final charWidth = (TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout()).width;
    final matches = _searching ? _matches : const <int>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searching)
          Material(
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      key: const Key('tom-text-search'),
                      controller: _query,
                      focusNode: _queryFocus,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Find in file',
                      ),
                      onChanged: (_) => setState(() => _match = -1),
                      onSubmitted: (_) => _step(1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _query.text.isEmpty
                        ? ''
                        : matches.isEmpty
                        ? 'No matches'
                        : '${_match < 0 ? 0 : _match + 1} of ${matches.length}',
                    key: const Key('tom-text-search-count'),
                    style: theme.textTheme.labelSmall,
                  ),
                  IconButton(
                    tooltip: 'Previous',
                    onPressed: () => _step(-1),
                    icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  ),
                  IconButton(
                    key: const Key('tom-text-search-next'),
                    tooltip: 'Next',
                    onPressed: () => _step(1),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => setState(() => _searching = false),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _vertical,
              child: SingleChildScrollView(
                controller: _vertical,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const Key('tom-text-gutter'),
                      color: scheme.surfaceContainerLow,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Text(
                        [
                          for (var i = 1; i <= lines.length; i++) '$i',
                        ].join('\n'),
                        textAlign: TextAlign.right,
                        strutStyle: strut,
                        style: style.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: math.max(
                            constraints.maxWidth - 60,
                            widest * charWidth + 48,
                          ),
                          child: Focus(
                            onKeyEvent: _onKey,
                            // The file's history is the only one: the text
                            // field's own undo answers nothing.
                            child: Actions(
                              actions: <Type, Action<Intent>>{
                                UndoTextIntent: CallbackAction<UndoTextIntent>(
                                  onInvoke: (_) {
                                    widget.onUndo?.call();
                                    return null;
                                  },
                                ),
                                RedoTextIntent: CallbackAction<RedoTextIntent>(
                                  onInvoke: (_) {
                                    widget.onRedo?.call();
                                    return null;
                                  },
                                ),
                              },
                              child: TextField(
                                key: const Key('tom-text-source'),
                                controller: _text,
                                focusNode: _focus,
                                readOnly: widget.readOnly,
                                maxLines: null,
                                style: style,
                                strutStyle: strut,
                                scrollPhysics:
                                    const NeverScrollableScrollPhysics(),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where the caret goes when [before] became [after] from outside: at the end
/// of what was inserted, or where text was removed.
TextSelection tomCaretAtChange(String before, String after) {
  final limit = math.min(before.length, after.length);
  var prefix = 0;
  while (prefix < limit &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < limit - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) ==
          after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  return TextSelection.collapsed(offset: after.length - suffix);
}

/// The source's text: the highlighter's spans, and the find bar's matches.
class _HighlightController extends TextEditingController {
  _HighlightController({super.text});

  ColorScheme? scheme;
  SyntaxHighlighter? highlighter;
  String query = '';

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final colors = scheme;
    if (colors == null ||
        (withComposing &&
            value.composing.isValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final h = highlighter;
    final spans = h == null
        ? <InlineSpan>[TextSpan(text: text)]
        : highlightedInlineSpans(text, h.highlight(text));
    final base = TextSpan(style: style, children: spans);
    if (query.isEmpty) return base;
    return _markMatches(base, style, colors);
  }

  /// [span] with every case-insensitive occurrence of [query] backed in the
  /// match colour. Walks the flat list of leaf spans, splitting where needed.
  TextSpan _markMatches(TextSpan span, TextStyle? style, ColorScheme colors) {
    final leaves = <TextSpan>[];
    void collect(InlineSpan s, TextStyle? inherited) {
      if (s is! TextSpan) return;
      final merged = inherited?.merge(s.style) ?? s.style;
      if (s.text != null) leaves.add(TextSpan(text: s.text, style: merged));
      for (final c in s.children ?? const <InlineSpan>[]) {
        collect(c, merged);
      }
    }

    collect(span, null);
    final full = leaves.map((l) => l.text).join();
    final hay = full.toLowerCase();
    final needle = query.toLowerCase();
    final marks = <(int, int)>[];
    var at = hay.indexOf(needle);
    while (at != -1) {
      marks.add((at, at + needle.length));
      at = hay.indexOf(needle, at + math.max(1, needle.length));
    }
    if (marks.isEmpty) return span;
    final out = <InlineSpan>[];
    var offset = 0;
    for (final leaf in leaves) {
      final text = leaf.text!;
      var cut = 0;
      for (final (start, end) in marks) {
        final s = math.max(start - offset, cut);
        final e = math.min(end - offset, text.length);
        if (e <= s || e <= 0 || s >= text.length) continue;
        if (s > cut) {
          out.add(TextSpan(text: text.substring(cut, s), style: leaf.style));
        }
        out.add(
          TextSpan(
            text: text.substring(s, e),
            style: (leaf.style ?? const TextStyle()).copyWith(
              backgroundColor: colors.tertiaryContainer,
            ),
          ),
        );
        cut = e;
      }
      if (cut < text.length) {
        out.add(TextSpan(text: text.substring(cut), style: leaf.style));
      }
      offset += text.length;
    }
    return TextSpan(style: style, children: out);
  }
}
