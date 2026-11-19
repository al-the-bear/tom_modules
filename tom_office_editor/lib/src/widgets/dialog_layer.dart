// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// LibreOffice's dialogs as windows (`part-lok-helper`, *LibreOffice's
/// dialogs*; DPLH-4's window mode): each window an overlay of its reported
/// size showing what `paintWindow` paints, its mouse, keys and text sent
/// back as `windowMouse`, `windowKey` and `windowTextInput`.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';

import '../controller.dart';
import '../input/vcl_keys.dart';
import '../office_editor_trail.dart';

/// The open windows over the document: a dialog modal (a barrier under it),
/// centred and draggable by its title bar; a child window (a combo box's
/// list) at its position in its parent.
class TomOfficeDialogLayer extends StatefulWidget {
  /// The windows of [controller].
  const TomOfficeDialogLayer({super.key, required this.controller});

  /// The document.
  final TomOfficeEditorController controller;

  @override
  State<TomOfficeDialogLayer> createState() => _TomOfficeDialogLayerState();
}

class _TomOfficeDialogLayerState extends State<TomOfficeDialogLayer> {
  /// Where the user dragged each dialog, from its centred place.
  final _moved = <int, Offset>{};

  static const _titleHeight = 28.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: widget.controller.windowRevision,
    builder: (context, _, _) => LayoutBuilder(
      builder: (context, constraints) {
        final windows = widget.controller.windows
            .where((w) => w.visible)
            .toList();
        if (windows.isEmpty) return const SizedBox.shrink();
        final area = constraints.biggest;
        // Where each window's pixels start, on screen.
        final origins = <int, Offset>{};
        final children = <Widget>[];
        final modal = windows.any((w) => w.isDialog);
        if (modal) {
          children.add(
            const Positioned.fill(
              child: ModalBarrier(
                key: ValueKey('office-dialog-barrier'),
                color: Color(0x33000000),
                dismissible: false,
              ),
            ),
          );
        }
        for (final w in windows) {
          final parent = w.parentId == null ? null : origins[w.parentId];
          final Offset origin;
          if (parent != null && !w.isDialog) {
            origin = parent + Offset(w.x.toDouble(), w.y.toDouble());
          } else {
            final centred = Offset(
              math.max(0, (area.width - w.width) / 2),
              math.max(_titleHeight, (area.height - w.height) / 2),
            );
            origin = centred + (_moved[w.id] ?? Offset.zero);
          }
          origins[w.id] = origin;
          children.add(
            Positioned(
              left: origin.dx,
              top: origin.dy - (w.isDialog ? _titleHeight : 0),
              child: _WindowFrame(
                key: ValueKey('office-window-${w.id}'),
                window: w,
                controller: widget.controller,
                titleHeight: w.isDialog ? _titleHeight : 0,
                // The newest window has the keyboard.
                autofocus: identical(w, windows.last),
                onDrag: (delta) => setState(
                  () => _moved[w.id] = (_moved[w.id] ?? Offset.zero) + delta,
                ),
              ),
            ),
          );
        }
        return Stack(children: children);
      },
    ),
  );
}

class _WindowFrame extends StatefulWidget {
  const _WindowFrame({
    super.key,
    required this.window,
    required this.controller,
    required this.titleHeight,
    required this.autofocus,
    required this.onDrag,
  });

  final TomOfficeWindow window;
  final TomOfficeEditorController controller;
  final double titleHeight;
  final bool autofocus;
  final ValueChanged<Offset> onDrag;

  @override
  State<_WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<_WindowFrame> {
  final _focus = FocusNode(debugLabel: 'office window');
  int _buttons = 0;
  int _count = 1;
  DateTime _lastDown = DateTime(0);
  Offset _lastAt = Offset.zero;
  DateTime _lastHover = DateTime(0);

  TomOfficeWindow get _w => widget.window;
  TomOfficeEditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_WindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _mods {
    final k = HardwareKeyboard.instance;
    var m = 0;
    if (k.isShiftPressed) m |= VclKey.shift;
    if (k.isMetaPressed) m |= VclKey.mod1;
    if (k.isAltPressed) m |= VclKey.mod2;
    if (k.isControlPressed) m |= VclKey.mod3;
    return m;
  }

  static int _lokButtons(int flutter) {
    var b = 0;
    if (flutter & kPrimaryButton != 0) b |= 1;
    if (flutter & kMiddleMouseButton != 0) b |= 2;
    if (flutter & kSecondaryButton != 0) b |= 4;
    return b == 0 ? 1 : b;
  }

  void _down(PointerDownEvent e) {
    _focus.requestFocus();
    final now = DateTime.now();
    _count =
        now.difference(_lastDown) < kDoubleTapTimeout &&
            (e.localPosition - _lastAt).distance < 4
        ? math.min(_count + 1, 3)
        : 1;
    _lastDown = now;
    _lastAt = e.localPosition;
    _buttons = _lokButtons(e.buttons);
    _send(OfficeMouseEventType.down, e.localPosition);
  }

  void _send(OfficeMouseEventType type, Offset at, {int? buttons}) {
    _c.windowMouse(
      _w.id,
      type,
      at.dx.round(),
      at.dy.round(),
      count: type == OfficeMouseEventType.move ? 1 : _count,
      buttons: buttons ?? _buttons,
      modifiers: _mods,
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final k = HardwareKeyboard.instance;
    final meaning = officeKeyMeaning(
      event.logicalKey,
      shift: k.isShiftPressed,
      meta: k.isMetaPressed,
      alt: k.isAltPressed,
      control: k.isControlPressed,
    );
    switch (meaning) {
      case OfficeVclKey(:final keyCode):
        _c.windowKey(_w.id, keyCode);
        return KeyEventResult.handled;
      case OfficeClipboardCommand():
        // The dialog's own clipboard keys (Cmd+C/X/V) as VCL keys.
        final letter = event.logicalKey.keyId - LogicalKeyboardKey.keyA.keyId;
        _c.windowKey(_w.id, (VclKey.a + letter) | _mods);
        return KeyEventResult.handled;
      case OfficeKeyIgnored():
        final text = event.character;
        if (text != null &&
            text.isNotEmpty &&
            !k.isMetaPressed &&
            !k.isControlPressed &&
            text.runes.every((r) => r >= 0x20 && r != 0x7f)) {
          officeTrail('window ${_w.id} text (${text.length})');
          _c.windowText(_w.id, text);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = _w;
    final body = SizedBox(
      width: w.width.toDouble(),
      height: w.height.toDouble(),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: MouseRegion(
          onHover: (e) {
            final now = DateTime.now();
            if (now.difference(_lastHover) < const Duration(milliseconds: 50)) {
              return;
            }
            _lastHover = now;
            _send(OfficeMouseEventType.move, e.localPosition, buttons: 0);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: (e) =>
                _send(OfficeMouseEventType.move, e.localPosition),
            onPointerUp: (e) {
              _send(OfficeMouseEventType.up, e.localPosition);
              _buttons = 0;
            },
            child: CustomPaint(
              key: ValueKey('office-window-pixels-${w.id}'),
              painter: _WindowPainter(w),
            ),
          ),
        ),
      ),
    );
    if (widget.titleHeight == 0) {
      return Material(elevation: 6, child: body);
    }
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onPanUpdate: (d) => widget.onDrag(d.delta),
            child: Container(
              width: w.width.toDouble(),
              height: widget.titleHeight,
              color: theme.colorScheme.surfaceContainerHigh,
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      w.title,
                      key: ValueKey('office-window-title-${w.id}'),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    key: ValueKey('office-window-close-${w.id}'),
                    tooltip: 'Close',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _c.closeWindow(w.id),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);

  final TomOfficeWindow window;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final img = window.image;
      if (img == null) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xFFF0F0F0),
        );
        return;
      }
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      final cursor = window.cursor;
      if (cursor != null && window.cursorVisible) {
        canvas.drawRect(
          Rect.fromLTWH(
            cursor.x.toDouble(),
            cursor.y.toDouble(),
            math.max(1, cursor.w.toDouble()),
            cursor.h.toDouble(),
          ),
          Paint()..color = const Color(0xFF000000),
        );
      }
    } catch (e, s) {
      officeReport(e, s, 'painting window ${window.id}');
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) => true;
}
