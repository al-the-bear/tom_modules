// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The document surface: tiles, LibreOffice's caret, selection and cursors,
/// scrolling and zoom, and the input that goes to the helper.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import '../callbacks.dart';
import '../controller.dart';
import '../input/vcl_keys.dart';
import '../office_editor_trail.dart';
import '../tiles/tile_cache.dart';

/// LibreOffice's mouse buttons (`MOUSE_LEFT`, `MOUSE_MIDDLE`, `MOUSE_RIGHT`).
const _lokLeft = 1;
const _lokMiddle = 2;
const _lokRight = 4;

/// The document of [controller], drawn as tiles with LibreOffice's overlays.
class TomOfficeDocumentView extends StatefulWidget {
  /// The view. [zoom] is the zoom in percent, or `null` for *fit width*.
  const TomOfficeDocumentView({
    super.key,
    required this.controller,
    required this.zoom,
    required this.onZoom,
    this.onVisible,
    this.focusNode,
  });

  /// The document.
  final TomOfficeEditorController controller;

  /// The zoom in percent; `null` fits the width.
  final int? zoom;

  /// A zoom change asked for by keys, the wheel or a pinch (`null`: fit
  /// width).
  final ValueChanged<int?> onZoom;

  /// The visible area in twips, after each scroll or zoom (the spreadsheet
  /// headers follow it).
  final ValueChanged<OfficeTwipRect>? onVisible;

  /// The focus node; one of its own when `null`.
  final FocusNode? focusNode;

  @override
  State<TomOfficeDocumentView> createState() => TomOfficeDocumentViewState();
}

/// The view's state; the editor's tests reach the focus node through it.
class TomOfficeDocumentViewState extends State<TomOfficeDocumentView>
    implements DeltaTextInputClient {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  late FocusNode _focus;
  bool _ownsFocus = false;
  Size _viewport = Size.zero;
  int _effectiveZoom = 100;
  double _dpr = 1;
  Timer? _viewTimer;
  Timer? _blink;
  bool _caretOn = true;
  Offset? _lastRightClick;
  TextInputConnection? _connection;
  TextEditingValue _value = TextEditingValue.empty;
  bool _composing = false;
  double? _pinchStartZoom;

  // Mouse state.
  int _clickCount = 1;
  DateTime _lastDown = DateTime(0);
  Offset _lastDownAt = Offset.zero;
  int _buttons = 0;
  DateTime _lastHover = DateTime(0);
  int? _dragHandle; // 0 start, 1 end of a text selection
  bool _dragGraphic = false;

  TomOfficeEditorController get _c => widget.controller;

  /// The focus node the view takes keys with.
  FocusNode get focusNode => _focus;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'office editor');
    _ownsFocus = widget.focusNode == null;
    _focus.addListener(_onFocus);
    _vertical.addListener(_onScroll);
    _horizontal.addListener(_onScroll);
    _c.addListener(_onController);
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!mounted || !_focus.hasFocus) return;
      setState(() => _caretOn = !_caretOn);
    });
  }

  @override
  void didUpdateWidget(TomOfficeDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    if (oldWidget.zoom != widget.zoom) _afterLayout();
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _viewTimer?.cancel();
    _blink?.cancel();
    _closeInput();
    _focus.removeListener(_onFocus);
    if (_ownsFocus) _focus.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ geometry

  double get _scale => _effectiveZoom / 100 / kTwipsPerPixel; // px per twip

  Size get _contentSize =>
      Size(_c.documentSize.width * _scale, _c.documentSize.height * _scale);

  Offset get _scroll => Offset(
    _horizontal.hasClients ? _horizontal.offset : 0,
    _vertical.hasClients ? _vertical.offset : 0,
  );

  /// A view position as document twips.
  (int, int) _twips(Offset local) {
    final p = local + _scroll;
    return ((p.dx / _scale).round(), (p.dy / _scale).round());
  }

  Rect _toView(OfficeTwipRect r) => Rect.fromLTWH(
    r.x * _scale - _scroll.dx,
    r.y * _scale - _scroll.dy,
    math.max(r.w * _scale, 1),
    math.max(r.h * _scale, 1),
  );

  int _zoomFor(double width) {
    final wanted = widget.zoom;
    if (wanted != null) return wanted;
    final doc = _c.documentSize.width;
    if (doc <= 0 || width <= 0) return 100;
    return (width * kTwipsPerPixel * 100 / doc).floor().clamp(20, 400);
  }

  // ------------------------------------------------------- tiles and view

  void _onScroll() {
    _requestTiles();
    _scheduleView();
    setState(() {});
  }

  void _onController() {
    if (!mounted) return;
    final menu = _c.contextMenu;
    if (menu != null) {
      _c.contextMenuShown();
      unawaited(_showContextMenu(menu));
    }
    _requestTiles();
    _updateCaretRect();
    setState(() {});
  }

  void _afterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestTiles();
      _scheduleView();
    });
  }

  void _requestTiles() {
    if (_viewport.isEmpty) return;
    final tile = kOfficeTileSize.toDouble();
    final s = _scroll;
    final firstCol = (s.dx / tile).floor();
    final firstRow = (s.dy / tile).floor();
    final lastCol = ((s.dx + _viewport.width) / tile).floor();
    final lastRow = ((s.dy + _viewport.height) / tile).floor();
    final maxCol = (_contentSize.width / tile).ceil() - 1;
    final maxRow = (_contentSize.height / tile).ceil() - 1;
    final part = _c.tilePart;
    final visible = <TileKey>{};
    for (var r = firstRow; r <= math.min(lastRow, maxRow); r++) {
      for (var col = firstCol; col <= math.min(lastCol, maxCol); col++) {
        if (r >= 0 && col >= 0) {
          visible.add(TileKey(part, _effectiveZoom, col, r));
        }
      }
    }
    final ring = <TileKey>[];
    for (var r = firstRow - 1; r <= lastRow + 1; r++) {
      for (var col = firstCol - 1; col <= lastCol + 1; col++) {
        if (r < 0 || col < 0 || r > maxRow || col > maxCol) continue;
        final key = TileKey(part, _effectiveZoom, col, r);
        if (!visible.contains(key)) ring.add(key);
      }
    }
    _c.showTiles(
      visible,
      ring: ring,
      zoom: _effectiveZoom,
      devicePixelRatio: _dpr,
    );
  }

  void _scheduleView() {
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _viewport.isEmpty) return;
      final (x, y) = _twips(Offset.zero);
      final visible = OfficeTwipRect(
        x,
        y,
        (_viewport.width / _scale).round(),
        (_viewport.height / _scale).round(),
      );
      _c.setView(visible, _effectiveZoom);
      widget.onVisible?.call(visible);
    });
  }

  /// Scrolls so that the caret is visible (after input).
  void _revealCaret() {
    final cursor = _c.cursor ?? _c.cellCursor?.rect;
    if (cursor == null || _viewport.isEmpty) return;
    final r = _toView(cursor);
    if (_vertical.hasClients) {
      if (r.top < 0) {
        _vertical.jumpTo(math.max(0, _vertical.offset + r.top - 16));
      } else if (r.bottom > _viewport.height) {
        _vertical.jumpTo(
          math.min(
            _vertical.position.maxScrollExtent,
            _vertical.offset + r.bottom - _viewport.height + 16,
          ),
        );
      }
    }
    if (_horizontal.hasClients) {
      if (r.left < 0) {
        _horizontal.jumpTo(math.max(0, _horizontal.offset + r.left - 16));
      } else if (r.right > _viewport.width) {
        _horizontal.jumpTo(
          math.min(
            _horizontal.position.maxScrollExtent,
            _horizontal.offset + r.right - _viewport.width + 16,
          ),
        );
      }
    }
  }

  // --------------------------------------------------------------- focus

  void _onFocus() {
    officeTrail('focus ${_focus.hasFocus ? 'in' : 'out'}');
    if (_focus.hasFocus && _c.acceptsEdits) {
      _openInput();
    } else {
      _closeInput();
    }
    setState(() => _caretOn = true);
  }

  // ------------------------------------------------------------------ keys

  int get _vclModifiers {
    final k = HardwareKeyboard.instance;
    var mods = 0;
    if (k.isShiftPressed) mods |= VclKey.shift;
    if (k.isMetaPressed) mods |= VclKey.mod1;
    if (k.isAltPressed) mods |= VclKey.mod2;
    if (k.isControlPressed) mods |= VclKey.mod3;
    return mods;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final command = k.isMetaPressed || k.isControlPressed;
    if (command && !k.isShiftPressed && !k.isAltPressed) {
      if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd) {
        widget.onZoom(_nextZoom(1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        widget.onZoom(_nextZoom(-1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit0) {
        widget.onZoom(100);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyF) {
        // LibreOffice's Find & Replace.
        _c.find();
        return KeyEventResult.handled;
      }
    }
    final meaning = officeKeyMeaning(
      key,
      shift: k.isShiftPressed,
      meta: k.isMetaPressed,
      alt: k.isAltPressed,
      control: k.isControlPressed,
    );
    switch (meaning) {
      case OfficeVclKey(:final keyCode):
        _c.key(keyCode);
        _afterInput();
        return KeyEventResult.handled;
      case OfficeClipboardCommand(key: final which):
        unawaited(_clipboard(which));
        return KeyEventResult.handled;
      case OfficeKeyIgnored():
        return KeyEventResult.ignored;
    }
  }

  int _nextZoom(int direction) {
    final now = _effectiveZoom;
    if (direction > 0) {
      return kOfficeZoomSteps.firstWhere(
        (z) => z > now,
        orElse: () => kOfficeZoomSteps.last,
      );
    }
    return kOfficeZoomSteps.lastWhere(
      (z) => z < now,
      orElse: () => kOfficeZoomSteps.first,
    );
  }

  void _afterInput() {
    _caretOn = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealCaret();
    });
  }

  /// Runs a clipboard command: copy and cut put the selection's text on
  /// the clipboard, paste hands the clipboard's text to LibreOffice.
  Future<void> _clipboard(OfficeClipboardKey which) async {
    switch (which) {
      case OfficeClipboardKey.copy:
      case OfficeClipboardKey.cut:
        final data = which == OfficeClipboardKey.cut
            ? await _c.cutSelection()
            : await _c.copySelection();
        final text = data['text/plain;charset=utf-8'] ?? data['text/plain'];
        if (text != null && text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
        }
      case OfficeClipboardKey.paste:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null) _c.paste('text/plain;charset=utf-8', text);
        _afterInput();
    }
  }

  /// What the shell's edit commands do here (`TomEditingSurface`).
  bool perform(TomOfficeEditCommand command) {
    switch (command) {
      case TomOfficeEditCommand.copy:
        unawaited(_clipboard(OfficeClipboardKey.copy));
      case TomOfficeEditCommand.cut:
        if (!_c.acceptsEdits) return false;
        unawaited(_clipboard(OfficeClipboardKey.cut));
      case TomOfficeEditCommand.paste:
        if (!_c.acceptsEdits) return false;
        unawaited(_clipboard(OfficeClipboardKey.paste));
      case TomOfficeEditCommand.selectAll:
        _c.uno('.uno:SelectAll');
    }
    return true;
  }

  // ----------------------------------------------------------- the mouse

  void _onPointerDown(PointerDownEvent e) {
    if (!_focus.hasFocus) _focus.requestFocus();
    final (x, y) = _twips(e.localPosition);
    final now = DateTime.now();
    if (now.difference(_lastDown) < kDoubleTapTimeout &&
        (e.localPosition - _lastDownAt).distance < 4) {
      _clickCount = _clickCount >= 3 ? 1 : _clickCount + 1;
    } else {
      _clickCount = 1;
    }
    _lastDown = now;
    _lastDownAt = e.localPosition;
    _buttons = _lokButtons(e.buttons);
    if (_buttons == _lokRight) _lastRightClick = e.position;
    // A selection handle or a shape's frame is dragged, not clicked.
    _dragHandle = _handleAt(e.localPosition);
    _dragGraphic = _dragHandle == null && _onGraphicHandle(e.localPosition);
    if (_dragHandle != null) return;
    if (_dragGraphic) {
      _c.dragSelection(OfficeSelectionKind.graphic, 0, x, y);
      return;
    }
    _c.mouse(
      OfficeMouseEventType.down,
      x,
      y,
      count: _clickCount,
      buttons: _buttons,
      modifiers: _vclModifiers,
    );
    _afterInput();
  }

  void _onPointerMove(PointerMoveEvent e) {
    final (x, y) = _twips(e.localPosition);
    final handle = _dragHandle;
    if (handle != null) {
      _c.dragSelection(OfficeSelectionKind.text, handle, x, y);
      return;
    }
    if (_dragGraphic) return;
    _c.mouse(
      OfficeMouseEventType.move,
      x,
      y,
      count: 1,
      buttons: _buttons,
      modifiers: _vclModifiers,
    );
  }

  void _onPointerUp(PointerUpEvent e) {
    final (x, y) = _twips(e.localPosition);
    final handle = _dragHandle;
    _dragHandle = null;
    if (handle != null) {
      _c.dragSelection(OfficeSelectionKind.text, handle, x, y);
      return;
    }
    if (_dragGraphic) {
      _dragGraphic = false;
      _c.dragSelection(OfficeSelectionKind.graphic, 1, x, y);
      return;
    }
    _c.mouse(
      OfficeMouseEventType.up,
      x,
      y,
      count: _clickCount,
      buttons: _buttons,
      modifiers: _vclModifiers,
    );
    _buttons = 0;
  }

  void _onHover(PointerHoverEvent e) {
    final now = DateTime.now();
    if (now.difference(_lastHover) < const Duration(milliseconds: 50)) return;
    _lastHover = now;
    final (x, y) = _twips(e.localPosition);
    _c.mouse(OfficeMouseEventType.move, x, y, count: 0, buttons: 0);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        widget.onZoom(_nextZoom(e.scrollDelta.dy < 0 ? 1 : -1));
      });
    }
  }

  int _lokButtons(int flutter) {
    var b = 0;
    if (flutter & kPrimaryButton != 0) b |= _lokLeft;
    if (flutter & kSecondaryButton != 0) b |= _lokRight;
    if (flutter & kMiddleMouseButton != 0) b |= _lokMiddle;
    return b == 0 ? _lokLeft : b;
  }

  int? _handleAt(Offset p) {
    for (final (i, r) in [(0, _c.selectionStart), (1, _c.selectionEnd)]) {
      if (r == null) continue;
      final v = _toView(r);
      final handle = Offset(v.left, v.bottom + 6);
      if ((p - handle).distance <= 10) return i;
    }
    return null;
  }

  bool _onGraphicHandle(Offset p) {
    final g = _c.graphicSelection;
    if (g == null || !_c.acceptsEdits) return false;
    for (final h in _graphicHandles(_toView(g))) {
      if ((p - h).distance <= 8) return true;
    }
    return false;
  }

  static List<Offset> _graphicHandles(Rect r) => [
    r.topLeft,
    r.topCenter,
    r.topRight,
    r.centerLeft,
    r.centerRight,
    r.bottomLeft,
    r.bottomCenter,
    r.bottomRight,
  ];

  Future<void> _showContextMenu(List<OfficeContextMenuEntry> menu) async {
    final at = _lastRightClick;
    if (at == null || !mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final items = <PopupMenuEntry<String>>[];
    void add(List<OfficeContextMenuEntry> entries, int depth) {
      for (final e in entries) {
        if (e.isSeparator) {
          if (items.isNotEmpty && items.last is! PopupMenuDivider) {
            items.add(const PopupMenuDivider());
          }
          continue;
        }
        final indent = '    ' * depth;
        if (e.children.isNotEmpty) {
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              height: 28,
              child: Text('$indent${e.text}'),
            ),
          );
          add(e.children, depth + 1);
          continue;
        }
        final command = e.command;
        items.add(
          CheckedPopupMenuItem<String>(
            value: command,
            enabled: e.enabled && command != null,
            checked: e.checked,
            height: 32,
            child: Text('$indent${e.text}'),
          ),
        );
      }
    }

    add(menu, 0);
    if (items.isEmpty) return;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(at.dx, at.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (chosen != null) {
      officeTrail('context menu: $chosen');
      _c.uno(chosen);
    }
  }

  // ----------------------------------------------------------- text input

  void _openInput() {
    if (_connection?.attached ?? false) return;
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableDeltaModel: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      ),
    );
    _value = TextEditingValue.empty;
    _connection!
      ..setEditingState(_value)
      ..show();
    _updateCaretRect();
  }

  void _closeInput() {
    _connection?.close();
    _connection = null;
    _composing = false;
  }

  void _updateCaretRect() {
    final connection = _connection;
    if (connection == null || !connection.attached) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    connection.setEditableSizeAndTransform(box.size, box.getTransformTo(null));
    final cursor = _c.cursor;
    if (cursor != null) connection.setCaretRect(_toView(cursor));
  }

  void _take(TextEditingValue value) {
    final composing = value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      _composing = true;
      _value = value;
      _c.compose(composing.textInside(value.text));
      return;
    }
    final text = value.text;
    _composing = false;
    if (text.isNotEmpty) {
      _c.commitText(text);
      _afterInput();
    }
    _value = TextEditingValue.empty;
    _connection?.setEditingState(_value);
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    var value = _value;
    for (final delta in textEditingDeltas) {
      value = delta.apply(value);
    }
    _take(value);
  }

  @override
  void updateEditingValue(TextEditingValue value) => _take(value);

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline && !_composing) {
      _c.key(VclKey.enter);
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    _composing = false;
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {}

  @override
  void showToolbar() {}

  @override
  bool onFocusReceived() {
    if (!_focus.hasFocus) _focus.requestFocus();
    return true;
  }

  // --------------------------------------------------------------- build

  MouseCursor get _cursor => switch (_c.mousePointer.toLowerCase()) {
    'text' => SystemMouseCursors.text,
    'hand' || 'refhand' => SystemMouseCursors.click,
    'move' => SystemMouseCursors.move,
    'nsize' ||
    'ssize' ||
    'rowresize' ||
    'vsplit' => SystemMouseCursors.resizeUpDown,
    'wsize' ||
    'esize' ||
    'colresize' ||
    'hsplit' => SystemMouseCursors.resizeLeftRight,
    'nwsize' || 'sesize' => SystemMouseCursors.resizeUpLeftDownRight,
    'nesize' || 'swsize' => SystemMouseCursors.resizeUpRightDownLeft,
    'cross' => SystemMouseCursors.precise,
    'wait' => SystemMouseCursors.wait,
    _ => SystemMouseCursors.basic,
  };

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final zoom = _zoomFor(viewport.width - 16);
        if (viewport != _viewport || zoom != _effectiveZoom) {
          _viewport = viewport;
          _effectiveZoom = zoom;
          _afterLayout();
        }
        final content = _contentSize;
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _cursor,
            onHover: _onHover,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerSignal: _onSignal,
              child: GestureDetector(
                onScaleStart: (_) =>
                    _pinchStartZoom = _effectiveZoom.toDouble(),
                onScaleEnd: (_) => _pinchStartZoom = null,
                onScaleUpdate: (d) {
                  final start = _pinchStartZoom;
                  if (start == null || d.pointerCount < 2) return;
                  final z = (start * d.scale).round().clamp(20, 400);
                  if (z != _effectiveZoom) widget.onZoom(z);
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('office-tiles'),
                          painter: OfficeDocumentPainter(
                            controller: _c,
                            zoom: _effectiveZoom,
                            vertical: _vertical,
                            horizontal: _horizontal,
                            content: content,
                            caretOn: _caretOn && _focus.hasFocus,
                            repaint: Listenable.merge([
                              _c.tileRevision,
                              _vertical,
                              _horizontal,
                            ]),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Scrollbar(
                        controller: _vertical,
                        thumbVisibility: true,
                        child: Scrollbar(
                          controller: _horizontal,
                          thumbVisibility: true,
                          notificationPredicate: (n) => n.depth == 1,
                          child: SingleChildScrollView(
                            controller: _vertical,
                            child: SingleChildScrollView(
                              controller: _horizontal,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: math.max(content.width, viewport.width),
                                height: math.max(
                                  content.height,
                                  viewport.height,
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
        );
      },
    );
  }
}

/// The edit commands the shell may send the view.
enum TomOfficeEditCommand { cut, copy, paste, selectAll }

/// Paints the tiles (the current zoom's over other zooms' scaled ones) and
/// LibreOffice's overlays.
class OfficeDocumentPainter extends CustomPainter {
  /// A painter.
  OfficeDocumentPainter({
    required this.controller,
    required this.zoom,
    required this.vertical,
    required this.horizontal,
    required this.content,
    required this.caretOn,
    super.repaint,
  });

  /// The document.
  final TomOfficeEditorController controller;

  /// The zoom in percent.
  final int zoom;

  /// The vertical scroll, read while painting.
  final ScrollController vertical;

  /// The horizontal scroll, read while painting.
  final ScrollController horizontal;

  /// The document's size in pixels.
  final Size content;

  /// Whether the caret is drawn (blinking).
  final bool caretOn;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paint(canvas, size);
    } catch (e, s) {
      officeReport(e, s, 'painting the document');
    }
  }

  void _paint(Canvas canvas, Size size) {
    final c = controller;
    final scale = zoom / 100 / kTwipsPerPixel;
    final scroll = Offset(
      horizontal.hasClients ? horizontal.offset : 0,
      vertical.hasClients ? vertical.offset : 0,
    );
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8E8E8),
    );
    final page = Rect.fromLTWH(
      -scroll.dx,
      -scroll.dy,
      content.width,
      content.height,
    );
    canvas.drawRect(page, Paint()..color = const Color(0xFFFFFFFF));
    final view = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final part = c.tilePart;
    // Other zooms' tiles first, scaled, so a zoom change never goes blank.
    final current = <TileKey>[];
    for (final key in c.tiles.keys) {
      if (key.part != part || key.zoom < 0) continue;
      if (key.zoom == zoom) {
        current.add(key);
        continue;
      }
      final twips = c.tileTwips(key.zoom);
      final dst = Rect.fromLTWH(
        key.column * twips * scale - scroll.dx,
        key.row * twips * scale - scroll.dy,
        twips * scale,
        twips * scale,
      );
      if (!dst.overlaps(view)) continue;
      _drawTile(canvas, c.tiles.peek(key)!.image, dst, paint);
    }
    const tile = kOfficeTileSize * 1.0;
    for (final key in current) {
      final dst = Rect.fromLTWH(
        key.column * tile - scroll.dx,
        key.row * tile - scroll.dy,
        tile,
        tile,
      );
      if (!dst.overlaps(view)) continue;
      _drawTile(canvas, c.tiles.peek(key)!.image, dst, paint);
    }
    // The overlays.
    Rect r(OfficeTwipRect t) => Rect.fromLTWH(
      t.x * scale - scroll.dx,
      t.y * scale - scroll.dy,
      math.max(t.w * scale, 1),
      math.max(t.h * scale, 1),
    );
    const selectionColour = Color(0x4D2F6FE0);
    final sel = Paint()..color = selectionColour;
    for (final t in c.selection) {
      canvas.drawRect(r(t), sel);
    }
    final handle = Paint()..color = const Color(0xFF2F6FE0);
    for (final t in [c.selectionStart, c.selectionEnd]) {
      if (t == null || c.selection.isEmpty) continue;
      final v = r(t);
      canvas.drawCircle(Offset(v.left, v.bottom + 6), 5, handle);
    }
    final cell = c.cellCursor;
    if (cell != null) {
      canvas.drawRect(
        r(cell.rect),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF1E5BC6),
      );
    }
    final graphic = c.graphicSelection;
    if (graphic != null) {
      final g = r(graphic);
      canvas.drawRect(
        g,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF1E5BC6),
      );
      for (final h in TomOfficeDocumentViewState._graphicHandles(g)) {
        canvas.drawRect(
          Rect.fromCenter(center: h, width: 7, height: 7),
          handle,
        );
      }
    }
    final cursor = c.cursor;
    if (cursor != null && caretOn) {
      final v = r(cursor);
      canvas.drawRect(
        Rect.fromLTWH(v.left, v.top, math.max(1.5, v.width), v.height),
        Paint()..color = const Color(0xFF000000),
      );
    }
  }

  void _drawTile(Canvas canvas, ui.Image image, Rect dst, Paint paint) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(OfficeDocumentPainter old) => true;
}
