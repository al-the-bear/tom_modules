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
/// outside (an undo, a redo, another view) puts the caret at the change, or
/// at the selection the host gives with it.
///
/// Markers ([TomTextMarker]) underline ranges of the text in the colour of
/// their severity; the line edits ([TomLineEdits]) and the clipboard are
/// reached through the state ([TomTextSourceState]), so a host binds them to
/// its own keys and menus. A host that keeps a scratch draft with no history
/// of its own leaves the text field's undo on ([TomTextSource.hostOwnsUndo]);
/// a host that routes the history keys itself turns the source's own
/// handling of them off ([TomTextSource.handleHistoryKeys]).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tom_text_highlight/tom_text_highlight.dart';

import 'line_edits.dart';
import 'text_marker.dart';

/// The source editor's line height, as a multiple of its font size; the
/// gutter is laid out on the same lines.
const double _lineHeight = 1.45;
const double _fontSize = 13;

/// How a [TomTextSource] looks when its host does not take the Material
/// colours and the default monospaced font: every field left null keeps the
/// default.
class TomTextSourceStyle {
  const TomTextSourceStyle({
    this.textStyle,
    this.lineNumberStyle,
    this.background,
    this.gutterBackground,
    this.gutterBorderColor,
    this.cursorColor,
    this.highlightCurrentLine = false,
  });

  /// Merged over the default text style (monospace, 13, line height 1.45,
  /// the scheme's `onSurface`); its font size and height lay out the gutter
  /// too.
  final TextStyle? textStyle;

  /// Merged over the line numbers' default style (the text style in the
  /// scheme's `onSurfaceVariant`).
  final TextStyle? lineNumberStyle;

  /// Behind the text; default none (the surface below shows).
  final Color? background;

  /// Behind the line numbers; default the scheme's `surfaceContainerLow`.
  final Color? gutterBackground;

  /// A one-pixel line between the line numbers and the text; default none.
  final Color? gutterBorderColor;

  /// The caret's colour; default the theme's.
  final Color? cursorColor;

  /// Whether the caret's line number is drawn at full opacity.
  final bool highlightCurrentLine;
}

/// A source editor.
class TomTextSource extends StatefulWidget {
  const TomTextSource({
    super.key,
    required this.text,
    this.onChanged,
    required this.readOnly,
    this.onUndo,
    this.onRedo,
    this.onSelectionMoved,
    this.onSelectionChanged,
    this.onValueChanged,
    this.onFocusLost,
    this.verticalController,
    this.highlighter,
    this.markers = const [],
    this.selection,
    this.selectionRequest,
    this.hostOwnsUndo = true,
    this.handleHistoryKeys = true,
    this.style,
  });

  final String text;

  /// The user changed the text; null for a source nobody edits.
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// The caret moved, or the selection changed, without the text changing:
  /// the typing burst in progress ends.
  final VoidCallback? onSelectionMoved;

  /// The selection the user left, after every change of the text or of the
  /// selection (not for text shown from outside).
  final ValueChanged<TextSelection>? onSelectionChanged;

  /// The text and the selection together, after every change of either by
  /// the user — for a host that keeps the caret with each history entry.
  final ValueChanged<TextEditingValue>? onValueChanged;

  /// The source lost the focus: the typing burst in progress ends.
  final VoidCallback? onFocusLost;

  /// The markers drawn under the text, offsets into [text].
  final List<TomTextMarker> markers;

  /// The selection to show with [text] when the text arrives from outside
  /// (an undo restoring the caret); null puts the caret at the change.
  final TextSelection? selection;

  /// Selections the host asks the source to show (a jump, a reveal, the
  /// caret after an edit made through an API), applied whenever it fires.
  final ValueListenable<TextSelection?>? selectionRequest;

  /// Whether the host keeps the document's history (the default): the text
  /// field's own undo is then off and the undo and redo keys reach [onUndo]
  /// and [onRedo]. A host editing a scratch draft with no history of its own
  /// passes false and keeps the field's undo.
  final bool hostOwnsUndo;

  /// Whether the source answers the undo and redo keys itself (the
  /// default). A host that routes them through a key map of its own — a
  /// binding the user may change — passes false: the keys then pass by, and
  /// the text field's own undo still answers nothing.
  final bool handleHistoryKeys;

  /// The look, when not the default.
  final TomTextSourceStyle? style;

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
  int _currentLine = 0;

  /// A selection the host asked for in this frame: text that arrives with
  /// it (an edit made through an API) shows it instead of the caret at the
  /// change.
  TextSelection? _requested;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
    _focus.addListener(_onFocus);
    widget.selectionRequest?.addListener(_onSelectionRequested);
  }

  @override
  void didUpdateWidget(TomTextSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionRequest != widget.selectionRequest) {
      oldWidget.selectionRequest?.removeListener(_onSelectionRequested);
      widget.selectionRequest?.addListener(_onSelectionRequested);
    }
    if (widget.text != _text.text) {
      final length = widget.text.length;
      final given = widget.selection ?? _requested;
      _showing = true;
      _text.value = TextEditingValue(
        text: widget.text,
        selection: given != null && given.isValid && given.end <= length
            ? given
            : tomCaretAtChange(_text.text, widget.text),
      );
      _lastSelection = _text.selection;
      _currentLine = _lineOf(_text.selection.extentOffset);
      _showing = false;
    }
  }

  @override
  void dispose() {
    widget.selectionRequest?.removeListener(_onSelectionRequested);
    _focus.removeListener(_onFocus);
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
      widget.onChanged?.call(_text.text);
    } else if (_text.selection != _lastSelection) {
      _lastSelection = _text.selection;
      widget.onSelectionMoved?.call();
    } else {
      return;
    }
    widget.onValueChanged?.call(_text.value);
    widget.onSelectionChanged?.call(_text.selection);
    final line = _lineOf(_text.selection.extentOffset);
    if (line != _currentLine) {
      _currentLine = line;
      if ((widget.style?.highlightCurrentLine ?? false) && mounted) {
        setState(() {});
      }
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus) widget.onFocusLost?.call();
  }

  void _onSelectionRequested() {
    final selection = widget.selectionRequest?.value;
    if (selection == null || !selection.isValid) return;
    _requested = selection;
    SchedulerBinding.instance.addPostFrameCallback((_) => _requested = null);
    if (selection.end > _text.text.length) return;
    _text.selection = selection;
    _scrollToLine(_lineOf(selection.extentOffset));
  }

  /// The 0-based line holding [offset].
  int _lineOf(int offset) {
    if (offset <= 0) return 0;
    final text = _text.text;
    return '\n'
        .allMatches(text.substring(0, math.min(offset, text.length)))
        .length;
  }

  // ── What a host reaches ──

  /// The text shown.
  String get text => _text.text;

  /// The selection shown.
  TextSelection get selection => _text.selection;

  /// Whether some text is selected.
  bool get hasSelection =>
      _text.selection.isValid && !_text.selection.isCollapsed;

  /// Shows [selection] (when it fits the text).
  void select(TextSelection selection) {
    if (!selection.isValid || selection.end > _text.text.length) return;
    _text.selection = selection;
  }

  /// Applies an edit made by a line edit or the clipboard as the user's.
  bool _apply(TextEditingValue? value) {
    if (value == null || widget.readOnly) return false;
    _text.value = value;
    return true;
  }

  /// Deletes the caret's line ([TomLineEdits.deleteLine]).
  bool deleteLine() => _apply(TomLineEdits.deleteLine(_text.value));

  /// Duplicates the caret's line ([TomLineEdits.duplicateLine]).
  bool duplicateLine() => _apply(TomLineEdits.duplicateLine(_text.value));

  /// Moves the caret's line up ([TomLineEdits.moveLineUp]).
  bool moveLineUp() => _apply(TomLineEdits.moveLineUp(_text.value));

  /// Moves the caret's line down ([TomLineEdits.moveLineDown]).
  bool moveLineDown() => _apply(TomLineEdits.moveLineDown(_text.value));

  /// Comments the caret's line out or in with [prefix]
  /// ([TomLineEdits.toggleLineComment]).
  bool toggleLineComment({String prefix = '# '}) =>
      _apply(TomLineEdits.toggleLineComment(_text.value, prefix: prefix));

  /// Copies the selected text to the clipboard.
  Future<void> copy() async {
    if (!hasSelection) return;
    await Clipboard.setData(
      ClipboardData(text: _text.selection.textInside(_text.text)),
    );
  }

  /// Copies the selected text to the clipboard and removes it.
  Future<void> cut() async {
    if (!hasSelection || widget.readOnly) return;
    final selection = _text.selection;
    final text = _text.text;
    await Clipboard.setData(ClipboardData(text: selection.textInside(text)));
    _apply(
      TextEditingValue(
        text: selection.textBefore(text) + selection.textAfter(text),
        selection: TextSelection.collapsed(offset: selection.start),
      ),
    );
  }

  /// Puts the clipboard's text in place of the selection.
  Future<void> paste() async {
    if (widget.readOnly) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null || !mounted) return;
    final selection = _text.selection.isValid
        ? _text.selection
        : TextSelection.collapsed(offset: _text.text.length);
    final text = _text.text;
    _apply(
      TextEditingValue(
        text: selection.textBefore(text) + pasted + selection.textAfter(text),
        selection: TextSelection.collapsed(
          offset: selection.start + pasted.length,
        ),
      ),
    );
  }

  /// Selects the whole text.
  void selectAll() {
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  double get _fontSizeNow => widget.style?.textStyle?.fontSize ?? _fontSize;
  double get _lineHeightNow => widget.style?.textStyle?.height ?? _lineHeight;
  double get _rowHeight => _fontSizeNow * _lineHeightNow;

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
    final history = widget.hostOwnsUndo && widget.handleHistoryKeys;
    if (history && key == LogicalKeyboardKey.keyZ) {
      final call = keys.isShiftPressed ? widget.onRedo : widget.onUndo;
      if (call == null) return KeyEventResult.ignored;
      call();
      return KeyEventResult.handled;
    }
    if (history && key == LogicalKeyboardKey.keyY) {
      final call = widget.onRedo;
      if (call == null) return KeyEventResult.ignored;
      call();
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
    final look = widget.style;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: _lineHeight,
      color: scheme.onSurface,
    ).merge(look?.textStyle);
    final strut = look?.textStyle == null
        ? const StrutStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: _lineHeight,
            forceStrutHeight: true,
          )
        : StrutStyle(
            fontFamily: style.fontFamily,
            fontFamilyFallback: style.fontFamilyFallback,
            fontSize: _fontSizeNow,
            height: _lineHeightNow,
            forceStrutHeight: true,
          );
    final numberStyle = style
        .copyWith(color: scheme.onSurfaceVariant)
        .merge(look?.lineNumberStyle);
    _text
      ..scheme = scheme
      ..highlighter = widget.highlighter
      ..markers = widget.markers
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
          child: _background(
            look?.background,
            LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                controller: _vertical,
                child: SingleChildScrollView(
                  controller: _vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: const Key('tom-text-gutter'),
                        color:
                            look?.gutterBackground ??
                            scheme.surfaceContainerLow,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: (look?.highlightCurrentLine ?? false)
                            ? Text.rich(
                                TextSpan(
                                  children: [
                                    for (var i = 0; i < lines.length; i++)
                                      TextSpan(
                                        text: i == 0
                                            ? '${i + 1}'
                                            : '\n${i + 1}',
                                        style: i == _currentLine
                                            ? numberStyle.copyWith(
                                                color: numberStyle.color
                                                    ?.withAlpha(255),
                                              )
                                            : null,
                                      ),
                                  ],
                                ),
                                textAlign: TextAlign.right,
                                strutStyle: strut,
                                style: numberStyle,
                              )
                            : Text(
                                [
                                  for (var i = 1; i <= lines.length; i++) '$i',
                                ].join('\n'),
                                textAlign: TextAlign.right,
                                strutStyle: strut,
                                style: numberStyle,
                              ),
                      ),
                      if (look?.gutterBorderColor case final border?)
                        Container(
                          key: const Key('tom-text-gutter-border'),
                          width: 1,
                          height: lines.length * _rowHeight + 16,
                          color: border,
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
                              child: _historyGuard(
                                TextField(
                                  key: const Key('tom-text-source'),
                                  controller: _text,
                                  focusNode: _focus,
                                  readOnly: widget.readOnly,
                                  maxLines: null,
                                  style: style,
                                  strutStyle: strut,
                                  cursorColor: look?.cursorColor,
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
        ),
      ],
    );
  }

  Widget _background(Color? color, Widget child) =>
      color == null ? child : ColoredBox(color: color, child: child);

  /// The file's history is the only one: the text field's own undo answers
  /// nothing, or the host's when the source handles the history keys. A
  /// host without a history of its own keeps the field's undo.
  Widget _historyGuard(Widget field) {
    if (!widget.hostOwnsUndo) return field;
    final handle = widget.handleHistoryKeys;
    return Actions(
      actions: <Type, Action<Intent>>{
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            if (handle) widget.onUndo?.call();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            if (handle) widget.onRedo?.call();
            return null;
          },
        ),
      },
      child: field,
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

/// The source's text: the highlighter's spans, the markers' underlines and
/// the find bar's matches.
class _HighlightController extends TextEditingController {
  _HighlightController({super.text});

  ColorScheme? scheme;
  SyntaxHighlighter? highlighter;
  List<TomTextMarker> markers = const [];
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
    final decorations = <_Decoration>[
      for (final marker in markers)
        if (marker.end > marker.start)
          _Decoration(
            marker.start,
            marker.end,
            TextStyle(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.wavy,
              decorationColor: marker.color,
            ),
          ),
      if (query.isNotEmpty)
        for (final (start, end) in _matchesOf(text, query))
          _Decoration(
            start,
            end,
            TextStyle(backgroundColor: colors.tertiaryContainer),
          ),
    ];
    if (decorations.isEmpty) return base;
    return _decorate(base, style, decorations);
  }

  /// Every case-insensitive occurrence of [query] in [text].
  static List<(int, int)> _matchesOf(String text, String query) {
    final hay = text.toLowerCase();
    final needle = query.toLowerCase();
    final marks = <(int, int)>[];
    var at = hay.indexOf(needle);
    while (at != -1) {
      marks.add((at, at + needle.length));
      at = hay.indexOf(needle, at + math.max(1, needle.length));
    }
    return marks;
  }

  /// [span] with each decoration's style merged over the text it covers.
  /// Walks the flat list of leaf spans, splitting where a decoration starts
  /// or ends.
  TextSpan _decorate(
    TextSpan span,
    TextStyle? style,
    List<_Decoration> decorations,
  ) {
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
    final cuts = <int>{
      for (final d in decorations) ...[d.start, d.end],
    }.toList()..sort();
    final out = <InlineSpan>[];
    var offset = 0;
    for (final leaf in leaves) {
      final text = leaf.text!;
      final end = offset + text.length;
      final points = <int>[
        offset,
        for (final c in cuts)
          if (c > offset && c < end) c,
        end,
      ];
      for (var i = 0; i + 1 < points.length; i++) {
        final from = points[i], to = points[i + 1];
        if (to <= from) continue;
        var pieceStyle = leaf.style;
        for (final d in decorations) {
          if (d.start <= from && d.end >= to) {
            pieceStyle = (pieceStyle ?? const TextStyle()).merge(d.style);
          }
        }
        out.add(
          TextSpan(
            text: text.substring(from - offset, to - offset),
            style: pieceStyle,
          ),
        );
      }
      offset = end;
    }
    return TextSpan(style: style, children: out);
  }
}

/// A style merged over [start]..[end] of the text.
class _Decoration {
  const _Decoration(this.start, this.end, this.style);

  final int start;
  final int end;
  final TextStyle style;
}
