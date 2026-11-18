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
  });

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
  final _pending = <PdfTileKey, int>{}; // key → ticket
  var _nextTicket = 1;
  int _generation = -1;
  Size _viewport = Size.zero;
  final _focus = FocusNode(debugLabel: 'PdfPageView');

  // Rendering statistics, summarised once a second in the trail.
  int _requested = 0, _done = 0, _dropped = 0, _ms = 0;
  Timer? _stats;

  // Selection by drag.
  (int, Offset)? _dragStart;

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
    _c.addListener(_onController);
    _c.scrollRequest.addListener(_onScrollRequest);
    vertical.addListener(_schedule);
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
    for (final ticket in _pending.values) {
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
      if (!wanted.containsKey(key)) {
        engine.cancel(_pending.remove(key)!);
        _dropped++;
      }
    }
    final keep = wanted.keys.toSet();
    for (final MapEntry(:key, :value) in wanted.entries) {
      if (_cache.contains(key) || _pending.containsKey(key)) continue;
      final (tile, priority) = value;
      final ticket = _nextTicket++;
      _pending[key] = ticket;
      _requested++;
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
            if (_pending[key] == ticket) _pending.remove(key);
            if (r == null ||
                !mounted ||
                generation != _c.generation ||
                _c.info == null) {
              return; // cancelled, or the document closed meanwhile
            }
            _done++;
            _ms += watch.elapsedMilliseconds;
            final image = await widget.decoder(r.bgra, r.pxW, r.pxH);
            if (!mounted || generation != _c.generation || _c.info == null) {
              image.dispose();
              return;
            }
            _cache.put(key, image, tile.x, tile.y, keep: keep);
            if (key.scaleKey == (layout.scale * _dpr * 1000).round()) {
              // The page has its new images: the other zooms can go.
              final complete = planTiles(
                key.page,
                info.pages[key.page].width,
                info.pages[key.page].height,
                key.scale,
              ).every((t) => _cache.contains(t.key));
              if (complete) _cache.dropOtherScales(key.page, key.scaleKey);
            }
            setState(() {});
          })
          .catchError((Object e, StackTrace s) {
            _pending.remove(key);
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
    if (_taps >= 2) {
      unawaited(_c.selectAround(page, at.dx, at.dy, line: _taps >= 3));
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

  void _onPanStart(DragStartDetails d) {
    _focus.requestFocus();
    _dragStart = _hit(d.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    final end = _hit(d.localPosition);
    if (start == null || end == null) return;
    unawaited(
      _c.selectBetween(
        start.$1,
        (x: start.$2.dx, y: start.$2.dy),
        end.$1,
        (x: end.$2.dx, y: end.$2.dy),
      ),
    );
  }

  void _onHover(PointerHoverEvent e) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 60), () async {
      final hit = _hit(e.localPosition);
      var cursor = SystemMouseCursors.basic;
      if (hit != null) {
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
    if (key == LogicalKeyboardKey.escape) {
      if (_c.findVisible) {
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
          onFocusChange: (f) => pdfTrail('view focus $f'),
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
                        onTapUp: _onTapUp,
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
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
    ).every((t) => _cache.contains(t.key));
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
