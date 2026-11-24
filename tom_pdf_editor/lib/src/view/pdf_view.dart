// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../engine/engine.dart';
import '../pdf_editor_trail.dart';
import 'layout.dart';
import 'note_dialog.dart';
import 'render_cache.dart';

/// Decodes BGRA pixels into an image (`ui.decodeImageFromPixels`); a test
/// may pass its own.
typedef PdfImageDecoder =
    Future<ui.Image> Function(Uint8List bgra, int width, int height);

/// The default decoder.
Future<ui.Image> decodeBgra(Uint8List bgra, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bgra,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

/// The scrolling column of pages: rendering, the cache, hits and the
/// selection, mouse and keys.
class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.controller,
    required this.zoom,
    required this.onZoom,
    required this.onCopy,
    this.decoder = decodeBgra,
    this.cache,
    this.onPosition,
    this.onFind,
  });

  /// Told where the view stands as it scrolls: the page at its top and how
  /// far into it (0–1).
  final void Function(int page, double offset)? onPosition;

  /// Cmd+F: the host's find bar instead of the editor's own.
  final VoidCallback? onFind;

  /// The controller of an open document.
  final TomPdfEditorController controller;

  /// The zoom in percent.
  final double zoom;

  /// Asks for another zoom (Cmd + / − / 0, Ctrl + wheel, pinch).
  final ValueChanged<double> onZoom;

  /// Puts copied text on the clipboard.
  final Future<void> Function(String text) onCopy;

  /// Decodes rendered pixels.
  final PdfImageDecoder decoder;

  /// The render cache (one per editor, so a zoom change keeps the images).
  final PdfRenderCache? cache;

  @override
  State<PdfPageView> createState() => PdfPageViewState();
}

/// The view's state; tests reach the scroll controller through it.
class PdfPageViewState extends State<PdfPageView> {
  /// The vertical scroll position.
  final vertical = ScrollController();

  /// The horizontal scroll position (a page wider than the view).
  final horizontal = ScrollController();

  late PdfRenderCache _cache = widget.cache ?? PdfRenderCache();
  // key → (ticket, version); tickets from nextPdfRenderTicket.
  final _pending = <PdfTileKey, (int, int)>{};
  int _generation = -1;
  Size _viewport = Size.zero;
  final _focus = FocusNode(debugLabel: 'PdfPageView');

  // Rendering statistics, summarised once a second in the trail.
  int _requested = 0, _done = 0, _dropped = 0, _ms = 0;
  Timer? _stats;

  // Selection by drag.
  (int, Offset)? _dragStart;
  Future<void>? _selecting;

  // Moving or resizing the selected annotation: its page, the annotation,
  // whether it resizes, where the drag started and is now (view points).
  ({int page, PdfAnnotation annotation, bool resize, Offset start})? _annDrag;
  Offset _annDragNow = Offset.zero;

  // Ink being drawn: its page and points.
  int? _inkPage;
  List<PdfPoint>? _ink;

  // Click counting.
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapAt = Offset.zero;
  int _taps = 0;

  MouseCursor _cursor = SystemMouseCursors.basic;
  Timer? _hoverTimer;

  // Pinch zoom.
  double _pinch = 1;

  TomPdfEditorController get _c => widget.controller;
  PdfDocumentInfo? get _info => _c.info;

  PdfLayout? _layoutCache;
  PdfLayout get layout {
    final info = _info!;
    final l = _layoutCache;
    if (l != null && l.zoom == widget.zoom && identical(l.pages, info.pages)) {
      return l;
    }
    return _layoutCache = PdfLayout(info.pages, widget.zoom);
  }

  double get _dpr => MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;

  @override
  void initState() {
    super.initState();
    // The cache may hold another document's images: start from the
    // controller's document, so its first notification does not cancel the
    // first renders again.
    _generation = _c.generation;
    _cache.clear();
    _c.addListener(_onController);
    _c.scrollRequest.addListener(_onScrollRequest);
    vertical.addListener(_schedule);
    vertical.addListener(_reportPosition);
    horizontal.addListener(_schedule);
    if (kPdfEditorDebug) {
      _stats = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_requested + _done + _dropped == 0) return;
        pdfTrail(
          'render: requested $_requested, done $_done, dropped $_dropped, '
          'avg ${_done == 0 ? 0 : _ms ~/ _done} ms',
        );
        _requested = _done = _dropped = _ms = 0;
      });
    }
  }

  @override
  void didUpdateWidget(PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _cancelAll();
      oldWidget.controller.removeListener(_onController);
      oldWidget.controller.scrollRequest.removeListener(_onScrollRequest);
      widget.controller.addListener(_onController);
      widget.controller.scrollRequest.addListener(_onScrollRequest);
      _generation = -1;
      _layoutCache = null;
      _cache.clear();
    }
    if (oldWidget.zoom != widget.zoom) {
      _cancelAll();
      _schedule();
    }
    if (widget.cache != null && !identical(widget.cache, _cache)) {
      _cache = widget.cache!;
    }
  }

  @override
  void dispose() {
    _cancelAll();
    _stats?.cancel();
    _hoverTimer?.cancel();
    _c.removeListener(_onController);
    _c.scrollRequest.removeListener(_onScrollRequest);
    vertical.dispose();
    horizontal.dispose();
    _focus.dispose();
    if (widget.cache == null) _cache.clear();
    super.dispose();
  }

  void _onController() {
    if (_c.info == null) _cancelAll(); // closed, or reopening
    if (_generation != _c.generation) {
      _generation = _c.generation;
      _cancelAll();
      _cache.clear();
      _layoutCache = null;
    }
    if (mounted) setState(() {});
    _schedule();
  }

  /// The page at the top of the view and how far into it.
  (int, double)? get position {
    if (_info == null || !vertical.hasClients) return null;
    final l = layout;
    final top = vertical.offset;
    final page = l.pageAt(top + 1).clamp(0, _info!.pageCount - 1);
    final rect = l.pageRect(page, _viewport.width);
    final offset = rect.height <= 0
        ? 0.0
        : ((top - rect.top) / rect.height).clamp(0.0, 1.0);
    return (page, offset);
  }

  void _reportPosition() {
    final p = position;
    if (p != null) widget.onPosition?.call(p.$1, p.$2);
  }

  /// Scrolls to [page] (clamped to the document), [offset] into it.
  void scrollToPosition(int page, double offset) {
    final info = _info;
    if (info == null || !vertical.hasClients || info.pageCount == 0) return;
    final p = page.clamp(0, info.pageCount - 1);
    final rect = layout.pageRect(p, _viewport.width);
    vertical.jumpTo(
      (rect.top + rect.height * offset.clamp(0.0, 1.0)).clamp(
        0,
        vertical.position.maxScrollExtent,
      ),
    );
    _schedule();
  }

  void _onScrollRequest() {
    final request = _c.scrollRequest.value;
    if (request == null || _info == null || !vertical.hasClients) return;
    final (page, rect) = request;
    if (page < 0 || page >= _info!.pageCount) return;
    final l = layout;
    var target = l.pageTop(page) - kPdfPageGap;
    if (rect != null) {
      // Bring the rectangle into view, a third from the top.
      target = l.pageTop(page) + rect.top * l.scale - _viewport.height / 3;
    }
    vertical.jumpTo(target.clamp(0, vertical.position.maxScrollExtent));
    if (rect != null && horizontal.hasClients) {
      final r = l.toColumn(page, rect, _viewport.width);
      if (r.left < horizontal.offset ||
          r.right > horizontal.offset + _viewport.width) {
        horizontal.jumpTo(
          (r.left - _viewport.width / 3).clamp(
            0,
            horizontal.position.maxScrollExtent,
          ),
        );
      }
    }
    _schedule();
  }

  bool _scheduled = false;

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _requestTiles();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _cancelAll() {
    if (_pending.isNotEmpty) {
      pdfTrail(
        'render cancel all: tickets '
        '${_pending.values.map((p) => p.$1).join(', ')}',
      );
    }
    for (final (ticket, _) in _pending.values) {
      _c.engine?.cancel(ticket);
      _dropped++;
    }
    _pending.clear();
  }

  /// Requests the visible tiles first, then the pages around the view as
  /// prefetch; cancels the requests that left the view.
  void _requestTiles() {
    final info = _info;
    final engine = _c.engine;
    if (info == null || engine == null || _viewport.isEmpty) return;
    final l = layout;
    final top = vertical.hasClients ? vertical.offset : 0.0;
    final left = horizontal.hasClients ? horizontal.offset : 0.0;
    final visible = l.pagesIn(top, top + _viewport.height);
    final scale = l.scale * _dpr;
    final wanted = <PdfTileKey, (PdfTile, PdfRenderPriority)>{};
    for (final page in visible) {
      if (_c.canAnnotate) unawaited(_c.loadAnnotations(page));
      final rect = l.pageRect(page, _viewport.width);
      // The visible part of the page, in its physical pixels.
      final vis = (
        left: (math.max(0.0, left - rect.left) * _dpr).floor(),
        top: (math.max(0.0, top - rect.top) * _dpr).floor(),
        right:
            ((math.min(rect.right, left + _viewport.width) - rect.left) * _dpr)
                .ceil(),
        bottom:
            ((math.min(rect.bottom, top + _viewport.height) - rect.top) * _dpr)
                .ceil(),
      );
      final size = info.pages[page];
      for (final t in planTiles(
        page,
        size.width,
        size.height,
        scale,
        visible: vis,
      )) {
        wanted[t.key] = (t, PdfRenderPriority.visible);
      }
    }
    if (visible.isNotEmpty) {
      for (final page in [visible.first - 1, visible.last + 1]) {
        if (page < 0 || page >= info.pageCount) continue;
        final size = info.pages[page];
        final tiles = planTiles(page, size.width, size.height, scale);
        // Prefetch whole pages only; tiled pages wait until they are seen.
        if (tiles.length == 1) {
          wanted.putIfAbsent(
            tiles.first.key,
            () => (tiles.first, PdfRenderPriority.prefetch),
          );
        }
      }
    }
    // Cancel what is no longer wanted.
    for (final key in _pending.keys.toList()) {
      if (!wanted.containsKey(key) ||
          _pending[key]!.$2 != _c.pageVersion(key.page)) {
        final ticket = _pending.remove(key)!.$1;
        pdfTrail('render cancel $key ticket $ticket (left the view)');
        engine.cancel(ticket);
        _dropped++;
      }
    }
    final keep = wanted.keys.toSet();
    for (final MapEntry(:key, :value) in wanted.entries) {
      final version = _c.pageVersion(key.page);
      if (_cache.isCurrent(key, version) || _pending.containsKey(key)) {
        continue;
      }
      final (tile, priority) = value;
      final ticket = nextPdfRenderTicket();
      _pending[key] = (ticket, version);
      _requested++;
      pdfTrail(
        'render request $key ticket $ticket ${priority.name} '
        'v$version gen ${_c.generation}',
      );
      final watch = Stopwatch()..start();
      final generation = _c.generation;
      engine
          .render(
            info.handle,
            key.page,
            scale: key.scale,
            x: tile.x,
            y: tile.y,
            pxW: tile.pxW,
            pxH: tile.pxH,
            priority: priority,
            ticket: ticket,
          )
          .then((r) async {
            // Still this key's request: the view did not cancel it.
            final own = _pending[key]?.$1 == ticket;
            if (own) _pending.remove(key);
            if (r == null &&
                own &&
                mounted &&
                generation == _c.generation &&
                _c.info != null) {
              // Dropped by the engine without the view cancelling it: the
              // tile is still wanted, so it is asked for again.
              pdfTrail(
                'render result $key ticket $ticket answered null without a '
                'cancel: requested again',
              );
              _dropped++;
              _schedule();
              return;
            }
            if (r == null ||
                !mounted ||
                generation != _c.generation ||
                _c.info == null) {
              pdfTrail(
                'render result $key ticket $ticket dropped: '
                '${r == null ? 'answered null' : 'outdated'}',
              );
              return; // cancelled, or the document closed meanwhile
            }
            _done++;
            _ms += watch.elapsedMilliseconds;
            final image = await widget.decoder(r.bgra, r.pxW, r.pxH);
            if (!mounted || generation != _c.generation || _c.info == null) {
              pdfTrail('render result $key ticket $ticket outdated on decode');
              image.dispose();
              return;
            }
            pdfTrail('render result $key ticket $ticket cached');
            _cache.put(
              key,
              image,
              tile.x,
              tile.y,
              keep: keep,
              version: version,
            );
            if (key.scaleKey == (layout.scale * _dpr * 1000).round()) {
              // The page has its new images: the other zooms can go.
              final complete = planTiles(
                key.page,
                info.pages[key.page].width,
                info.pages[key.page].height,
                key.scale,
              ).every((t) => _cache.isCurrent(t.key, version));
              if (complete) _cache.dropOtherScales(key.page, key.scaleKey);
            }
            setState(() {});
            if (version != _c.pageVersion(key.page)) _schedule();
          })
          .catchError((Object e, StackTrace s) {
            if (_pending[key]?.$1 == ticket) _pending.remove(key);
            // A render the document's closing overtook is no error.
            if (_c.info != null && generation == _c.generation) {
              pdfReport(e, s, 'rendering page ${key.page}');
            }
          });
    }
  }

  // ------------------------------------------------------------------ input

  /// A position in the scrolled content (where the gesture detector and the
  /// mouse region sit, so their positions already include the scroll
  /// offsets) → (page, view points).
  (int, Offset)? _hit(Offset content) => layout.hit(content, _viewport.width);

  void _onTapUp(TapUpDetails d) {
    _focus.requestFocus();
    final now = DateTime.now();
    if (now.difference(_lastTap) < const Duration(milliseconds: 400) &&
        (d.localPosition - _lastTapAt).distance < 6) {
      _taps++;
    } else {
      _taps = 1;
    }
    _lastTap = now;
    _lastTapAt = d.localPosition;
    final hit = _hit(d.localPosition);
    if (hit == null) {
      _c.clearSelection();
      return;
    }
    final (page, at) = hit;
    final taps = _taps;
    if (_c.tool == PdfAnnotationTool.select && _c.canFill) {
      // A fillable field takes the click (focus, caret, a checkbox).
      unawaited(() async {
        if (await _c.formClick(page, at.dx, at.dy)) return;
        if (mounted) _tapOn(page, at, taps);
      }());
      return;
    }
    _tapOn(page, at, taps);
  }

  /// A click that no form field took.
  void _tapOn(int page, Offset at, int taps) {
    switch (_c.tool) {
      case PdfAnnotationTool.note:
        unawaited(_newNote(page, at));
        return;
      case PdfAnnotationTool.ink:
        return;
      case PdfAnnotationTool.highlight:
        if (taps >= 2) {
          unawaited(() async {
            await _c.selectAround(page, at.dx, at.dy, line: taps >= 3);
            await _c.highlightSelection();
          }());
          return;
        }
      case PdfAnnotationTool.select:
        final a = _c.annotationAt(page, at.dx, at.dy);
        if (a != null) {
          _c.selectAnnotation(page, a.id);
          if (taps >= 2 && a.kind == PdfAnnotationKind.note) {
            unawaited(_editNote(page, a));
          }
          return;
        }
        _c.selectAnnotation(page, null);
    }
    if (taps >= 2) {
      unawaited(_c.selectAround(page, at.dx, at.dy, line: taps >= 3));
      return;
    }
    unawaited(() async {
      final link = await _c.linkAt(page, at.dx, at.dy);
      if (link != null) {
        _c.followLink(link);
      } else {
        _c.clearSelection();
      }
    }());
  }

  Future<void> _newNote(int page, Offset at) async {
    final text = await showPdfNoteDialog(context);
    if (text == null || !mounted) return;
    await _c.addNote(
      page,
      at.dx - kPdfNoteSize / 2,
      at.dy - kPdfNoteSize / 2,
      text,
    );
  }

  Future<void> _editNote(int page, PdfAnnotation note) async {
    final text = await showPdfNoteDialog(context, initial: note.contents);
    if (text == null || !mounted) return;
    await _c.setNoteText(page, note.id, text);
  }

  /// A content position as view points of [page] (also outside the page).
  Offset _onPage(int page, Offset content) {
    final rect = layout.pageRect(page, _viewport.width);
    return Offset(
      (content.dx - rect.left) / layout.scale,
      (content.dy - rect.top) / layout.scale,
    );
  }

  /// Whether [at] (view points) is on the resize handle of [a].
  bool _onHandle(PdfAnnotation a, Offset at) {
    final reach = 8 / layout.scale;
    return (at.dx - a.rect.right).abs() <= reach &&
        (at.dy - a.rect.bottom).abs() <= reach;
  }

  void _onPanStart(DragStartDetails d) {
    _focus.requestFocus();
    _dragStart = null;
    final hit = _hit(d.localPosition);
    if (hit == null) return;
    final (page, at) = hit;
    switch (_c.tool) {
      case PdfAnnotationTool.ink:
        setState(() {
          _inkPage = page;
          _ink = [(x: at.dx, y: at.dy)];
        });
        return;
      case PdfAnnotationTool.note:
        return;
      case PdfAnnotationTool.select:
        var a = _c.selectedAnnotation;
        if (a == null ||
            _c.selectedAnnotationPage != page ||
            !(_onHandle(a, at) || annotationContains(a, at.dx, at.dy))) {
          a = _c.annotationAt(page, at.dx, at.dy);
          if (a != null) _c.selectAnnotation(page, a.id);
        }
        if (a != null && a.kind != PdfAnnotationKind.highlight) {
          _annDrag = (
            page: page,
            annotation: a,
            resize: a.kind == PdfAnnotationKind.ink && _onHandle(a, at),
            start: at,
          );
          _annDragNow = at;
          return;
        }
        if (a != null) return; // a highlight is not moved
      case PdfAnnotationTool.highlight:
        break;
    }
    _dragStart = hit;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final ink = _ink;
    if (ink != null) {
      final at = _onPage(_inkPage!, d.localPosition);
      final size = _info!.pages[_inkPage!];
      setState(
        () => ink.add((
          x: at.dx.clamp(0.0, size.width),
          y: at.dy.clamp(0.0, size.height),
        )),
      );
      return;
    }
    final drag = _annDrag;
    if (drag != null) {
      setState(() => _annDragNow = _onPage(drag.page, d.localPosition));
      return;
    }
    final start = _dragStart;
    final end = _hit(d.localPosition);
    if (start == null || end == null) return;
    _selecting = _c.selectBetween(
      start.$1,
      (x: start.$2.dx, y: start.$2.dy),
      end.$1,
      (x: end.$2.dx, y: end.$2.dy),
    );
  }

  void _onPanEnd(DragEndDetails d) {
    final ink = _ink;
    if (ink != null) {
      final page = _inkPage!;
      setState(() {
        _ink = null;
        _inkPage = null;
      });
      unawaited(_c.addInk(page, [ink]));
      return;
    }
    final drag = _annDrag;
    if (drag != null) {
      _annDrag = null;
      final target = _dragTarget(drag, _annDragNow);
      setState(() {});
      if (target == null) return;
      final id = drag.annotation.id;
      unawaited(
        drag.resize
            ? _c.resizeAnnotation(drag.page, id, target.rect)
            : _c.moveAnnotation(
                drag.page,
                id,
                _annDragNow.dx - drag.start.dx,
                _annDragNow.dy - drag.start.dy,
              ),
      );
      return;
    }
    if (_c.tool == PdfAnnotationTool.highlight && _dragStart != null) {
      final selecting = _selecting;
      unawaited(() async {
        await selecting;
        await _c.highlightSelection();
      }());
    }
    _dragStart = null;
    _selecting = null;
  }

  /// Where a move or resize puts the annotation; `null` when it did not
  /// change.
  PdfAnnotation? _dragTarget(
    ({int page, PdfAnnotation annotation, bool resize, Offset start}) drag,
    Offset now,
  ) {
    final a = drag.annotation;
    final dx = now.dx - drag.start.dx;
    final dy = now.dy - drag.start.dy;
    if (dx.abs() < 0.5 && dy.abs() < 0.5) return null;
    if (!drag.resize) return a.moved(dx, dy);
    final r = a.rect;
    return a.resized(
      PdfRect(
        r.left,
        r.top,
        math.max(r.left + 4, r.right + dx),
        math.max(r.top + 4, r.bottom + dy),
      ),
    );
  }

  void _onHover(PointerHoverEvent e) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 60), () async {
      final hit = _hit(e.localPosition);
      var cursor = SystemMouseCursors.basic;
      final tool = _c.tool;
      final field =
          hit != null && tool == PdfAnnotationTool.select && _c.canFill
          ? await _c.formFieldAt(hit.$1, hit.$2.dx, hit.$2.dy)
          : null;
      if (field != null && field.fillable) {
        cursor = field.type == PdfFieldType.text
            ? SystemMouseCursors.text
            : SystemMouseCursors.click;
      } else if (hit != null &&
          (tool == PdfAnnotationTool.ink || tool == PdfAnnotationTool.note)) {
        cursor = SystemMouseCursors.precise;
      } else if (hit != null &&
          tool == PdfAnnotationTool.select &&
          _c.annotationAt(hit.$1, hit.$2.dx, hit.$2.dy) != null) {
        final a = _c.selectedAnnotation;
        cursor =
            a != null &&
                _c.selectedAnnotationPage == hit.$1 &&
                a.kind == PdfAnnotationKind.ink &&
                _onHandle(a, hit.$2)
            ? SystemMouseCursors.resizeDownRight
            : SystemMouseCursors.click;
      } else if (hit != null) {
        final link = await _c.linkAt(hit.$1, hit.$2.dx, hit.$2.dy);
        if (link != null) {
          cursor = SystemMouseCursors.click;
        } else if (_c.hasTextLayer ?? false) {
          cursor = SystemMouseCursors.text;
        }
      }
      if (mounted && cursor != _cursor) setState(() => _cursor = cursor);
    });
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        widget.onZoom(
          e.scrollDelta.dy < 0
              ? zoomStepUp(widget.zoom)
              : zoomStepDown(widget.zoom),
        );
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final key = e.logicalKey;
    if (_c.formFocus != null) {
      final handled = _formKey(e, meta);
      if (handled) return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyF) {
      final onFind = widget.onFind;
      if (onFind != null) {
        onFind();
      } else {
        _c.showFind();
      }
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyC) {
      unawaited(_copy());
      return KeyEventResult.handled;
    }
    if (meta &&
        (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.add ||
            key == LogicalKeyboardKey.numpadAdd)) {
      widget.onZoom(zoomStepUp(widget.zoom));
      return KeyEventResult.handled;
    }
    if (meta &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      widget.onZoom(zoomStepDown(widget.zoom));
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.digit0) {
      widget.onZoom(100);
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyZ) {
      unawaited(
        HardwareKeyboard.instance.isShiftPressed ? _c.redo() : _c.undo(),
      );
      return KeyEventResult.handled;
    }
    final selected = _c.selectedAnnotation;
    if (selected != null &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      unawaited(_c.deleteAnnotation(_c.selectedAnnotationPage!, selected.id));
      return KeyEventResult.handled;
    }
    final plain =
        !meta &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed;
    final toolKey = {
      LogicalKeyboardKey.keyV: PdfAnnotationTool.select,
      LogicalKeyboardKey.keyH: PdfAnnotationTool.highlight,
      LogicalKeyboardKey.keyN: PdfAnnotationTool.note,
      LogicalKeyboardKey.keyI: PdfAnnotationTool.ink,
    }[key];
    if (plain && toolKey != null && _c.canAnnotate) {
      _c.setTool(toolKey);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_c.tool != PdfAnnotationTool.select) {
        _c.setTool(PdfAnnotationTool.select);
      } else if (selected != null) {
        _c.selectAnnotation(0, null);
      } else if (_c.findVisible) {
        _c.hideFind();
      } else {
        _c.clearSelection();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.pageUp) {
      final d = key == LogicalKeyboardKey.pageDown ? 1 : -1;
      vertical.jumpTo(
        (vertical.offset + d * _viewport.height * 0.9).clamp(
          0,
          vertical.position.maxScrollExtent,
        ),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static final _formKeys = {
    LogicalKeyboardKey.backspace: PdfFormKey.backspace,
    LogicalKeyboardKey.delete: PdfFormKey.delete,
    LogicalKeyboardKey.arrowLeft: PdfFormKey.left,
    LogicalKeyboardKey.arrowRight: PdfFormKey.right,
    LogicalKeyboardKey.arrowUp: PdfFormKey.up,
    LogicalKeyboardKey.arrowDown: PdfFormKey.down,
    LogicalKeyboardKey.home: PdfFormKey.home,
    LogicalKeyboardKey.end: PdfFormKey.end,
    LogicalKeyboardKey.enter: PdfFormKey.enter,
    LogicalKeyboardKey.numpadEnter: PdfFormKey.enter,
    LogicalKeyboardKey.tab: PdfFormKey.tab,
  };

  /// A key while a form field has the focus: typed text, editing keys, Tab,
  /// Cmd+A, Cmd+Z (the field's own undo first), Escape (release).
  bool _formKey(KeyEvent e, bool meta) {
    final key = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (meta && key == LogicalKeyboardKey.keyZ) {
      unawaited(() async {
        if (await _c.formUndo(redo: shift)) return;
        await (shift ? _c.redo() : _c.undo());
      }());
      return true;
    }
    if (meta && key == LogicalKeyboardKey.keyA) {
      unawaited(_c.formKey(PdfFormKey.selectAll));
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      unawaited(_c.releaseFormFocus());
      return true;
    }
    final formKey = _formKeys[key];
    if (formKey != null && !meta) {
      unawaited(_c.formKey(formKey, shift: shift));
      return true;
    }
    final text = e.character;
    if (!meta &&
        !HardwareKeyboard.instance.isControlPressed &&
        text != null &&
        text.isNotEmpty &&
        text.codeUnitAt(0) >= 0x20 &&
        text.codeUnitAt(0) != 0x7F) {
      unawaited(_c.formText(text));
      return true;
    }
    return false;
  }

  Future<void> _copy() async {
    final text = await _c.selectedText();
    if (text != null && text.isNotEmpty) await widget.onCopy(text);
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _viewport) {
          _viewport = size;
          _schedule();
        }
        final l = layout;
        final contentWidth = math.max(l.width, size.width);
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          onFocusChange: (f) {
            pdfTrail('view focus $f');
            // The field's text is committed when the editor loses the focus.
            if (!f) unawaited(_c.releaseFormFocus());
          },
          child: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomUpdate: (e) => _pinch = e.scale,
            onPointerPanZoomEnd: (_) {
              if ((_pinch - 1).abs() > 0.05) {
                widget.onZoom((widget.zoom * _pinch).clamp(10, 800));
              }
              _pinch = 1;
            },
            child: Scrollbar(
              controller: vertical,
              child: SingleChildScrollView(
                controller: vertical,
                child: Scrollbar(
                  controller: horizontal,
                  notificationPredicate: (n) => n.depth == 0,
                  child: SingleChildScrollView(
                    controller: horizontal,
                    scrollDirection: Axis.horizontal,
                    child: MouseRegion(
                      cursor: _cursor,
                      onHover: _onHover,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapUp: _onTapUp,
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        child: SizedBox(
                          width: contentWidth,
                          height: l.height,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _PagesPainter(this, l, size.width),
                                ),
                              ),
                              ..._spinners(l, size),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Whether [page] has an image to show (any scale).
  @visibleForTesting
  bool hasImage(int page) {
    final scaleKey = (layout.scale * _dpr * 1000).round();
    return _hasAnyImage(page, scaleKey);
  }

  /// Whether [page] has every tile it needs at the current zoom.
  @visibleForTesting
  bool hasCurrentImages(int page) {
    final info = _info!;
    final scale = layout.scale * _dpr;
    final top = vertical.hasClients ? vertical.offset : 0.0;
    final rect = layout.pageRect(page, _viewport.width);
    final left = horizontal.hasClients ? horizontal.offset : 0.0;
    final vis = (
      left: (math.max(0.0, left - rect.left) * _dpr).floor(),
      top: (math.max(0.0, top - rect.top) * _dpr).floor(),
      right: ((math.min(rect.right, left + _viewport.width) - rect.left) * _dpr)
          .ceil(),
      bottom:
          ((math.min(rect.bottom, top + _viewport.height) - rect.top) * _dpr)
              .ceil(),
    );
    return planTiles(
      page,
      info.pages[page].width,
      info.pages[page].height,
      scale,
      visible: vis,
    ).every((t) => _cache.isCurrent(t.key, _c.pageVersion(page)));
  }

  /// A spinner over each visible page that has nothing to show yet.
  List<Widget> _spinners(PdfLayout l, Size size) {
    final top = vertical.hasClients ? vertical.offset : 0.0;
    final scaleKey = (l.scale * _dpr * 1000).round();
    return [
      for (final page in l.pagesIn(top, top + size.height))
        if (!_hasAnyImage(page, scaleKey))
          Positioned.fromRect(
            rect: Rect.fromCenter(
              center: l.pageRect(page, size.width).center,
              width: 24,
              height: 24,
            ),
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
    ];
  }

  bool _hasAnyImage(int page, int scaleKey) {
    final info = _info!;
    final tiles = planTiles(
      page,
      info.pages[page].width,
      info.pages[page].height,
      scaleKey / 1000,
    );
    return tiles.any((t) => _cache.contains(t.key)) ||
        _cache.otherScales(page, scaleKey).isNotEmpty;
  }
}

class _PagesPainter extends CustomPainter {
  _PagesPainter(this.state, this.layout, this.viewportWidth);

  final PdfPageViewState state;
  final PdfLayout layout;
  final double viewportWidth;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paint(canvas);
    } catch (e, s) {
      pdfReport(e, s, 'painting');
    }
  }

  void _paint(Canvas canvas) {
    final c = state._c;
    final info = c.info!;
    final top = state.vertical.hasClients ? state.vertical.offset : 0.0;
    final height = state._viewport.height;
    final dpr = state._dpr;
    final scaleKey = (layout.scale * dpr * 1000).round();
    final cache = state._cache;
    final paperPaint = Paint()..color = Colors.white;
    final shadow = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    for (final page in layout.pagesIn(top, top + height)) {
      final rect = layout.pageRect(page, viewportWidth);
      canvas.drawRect(rect.shift(const Offset(0, 1)), shadow);
      canvas.drawRect(rect, paperPaint);
      // The current zoom's images, else another zoom's scaled.
      final size = info.pages[page];
      final tiles = planTiles(page, size.width, size.height, scaleKey / 1000);
      final drawn = <PdfTileKey>{};
      for (final t in tiles) {
        final e = cache.get(t.key);
        if (e == null) continue;
        drawn.add(t.key);
        _drawEntry(canvas, rect, e, scaleKey / 1000, dpr, imagePaint);
      }
      if (drawn.length < tiles.length) {
        for (final (key, e) in cache.otherScales(page, scaleKey)) {
          _drawEntry(canvas, rect, e, key.scale, dpr, imagePaint);
        }
        // Then the current ones on top again.
        for (final t in tiles) {
          final e = cache.get(t.key);
          if (e != null) {
            _drawEntry(canvas, rect, e, scaleKey / 1000, dpr, imagePaint);
          }
        }
      }
      if (drawn.isEmpty && cache.otherScales(page, scaleKey).isEmpty) {
        canvas.drawRect(rect, Paint()..color = const Color(0xFFE6E6E6));
      }
    }
    // Search hits, then the selection.
    final hitPaint = Paint()..color = const Color(0x55FFD54F);
    final currentPaint = Paint()..color = const Color(0x88FF9800);
    final hits = c.hits;
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final r = layout.pageRect(hit.page, viewportWidth);
      if (r.bottom < top || r.top > top + height) continue;
      for (final rect in hit.rects) {
        canvas.drawRect(
          layout.toColumn(hit.page, rect, viewportWidth),
          i == c.currentHit ? currentPaint : hitPaint,
        );
      }
    }
    final selectionPaint = Paint()..color = const Color(0x553D7BFD);
    for (final s in c.selection) {
      for (final rect in s.rects) {
        canvas.drawRect(
          layout.toColumn(s.page, rect, viewportWidth),
          selectionPaint,
        );
      }
    }
    _paintAnnotationEditing(canvas, c);
  }

  /// The selected annotation's frame (where a move or resize puts it) and
  /// its resize handle; the ink being drawn.
  void _paintAnnotationEditing(Canvas canvas, TomPdfEditorController c) {
    final frame = Paint()
      ..color = const Color(0xFF3D7BFD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    var a = c.selectedAnnotation;
    final page = c.selectedAnnotationPage;
    final drag = state._annDrag;
    if (drag != null) {
      a = state._dragTarget(drag, state._annDragNow) ?? drag.annotation;
    }
    if (a != null && page != null) {
      final r = layout.toColumn(page, a.rect, viewportWidth).inflate(2);
      canvas.drawRect(r, frame);
      if (a.kind == PdfAnnotationKind.ink) {
        canvas.drawRect(
          Rect.fromCenter(center: r.bottomRight, width: 8, height: 8),
          Paint()..color = const Color(0xFF3D7BFD),
        );
      }
      if (drag != null && a.kind == PdfAnnotationKind.ink) {
        _paintStrokes(canvas, page, a.strokes, a.color, a.width);
      }
    }
    final ink = state._ink;
    if (ink != null) {
      _paintStrokes(
        canvas,
        state._inkPage!,
        [ink],
        c.toolColor(PdfAnnotationTool.ink),
        2,
      );
    }
  }

  void _paintStrokes(
    Canvas canvas,
    int page,
    List<List<PdfPoint>> strokes,
    int color,
    double width,
  ) {
    final rect = layout.pageRect(page, viewportWidth);
    final paint = Paint()
      ..color = Color(color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * layout.scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()
        ..moveTo(
          rect.left + s.first.x * layout.scale,
          rect.top + s.first.y * layout.scale,
        );
      for (final p in s.skip(1)) {
        path.lineTo(
          rect.left + p.x * layout.scale,
          rect.top + p.y * layout.scale,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Draws a cached image of a page rendered at [entryScale] physical
  /// pixels per point into the page's [rect].
  void _drawEntry(
    Canvas canvas,
    Rect rect,
    PdfCacheEntry e,
    double entryScale,
    double dpr,
    Paint paint,
  ) {
    // Physical pixels of the entry → points → logical pixels.
    final k = layout.scale / entryScale;
    final dst = Rect.fromLTWH(
      rect.left + e.x * k,
      rect.top + e.y * k,
      e.image.width * k,
      e.image.height * k,
    );
    canvas.drawImageRect(
      e.image,
      Rect.fromLTWH(0, 0, e.image.width.toDouble(), e.image.height.toDouble()),
      dst,
      paint,
    );
  }

  @override
  bool shouldRepaint(_PagesPainter old) => true;
}
