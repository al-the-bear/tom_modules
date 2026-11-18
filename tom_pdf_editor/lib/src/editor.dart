// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'engine/engine.dart';
import 'pdf_editor_trail.dart';
import 'view/layout.dart';
import 'view/note_dialog.dart';
import 'view/pdf_view.dart';
import 'view/render_cache.dart';

/// The PDF editor widget: the page column, the page list (thumbnails and the
/// outline), the find bar, zoom, and the bars for read-only documents,
/// conflicts, passwords and failures. A host drives it through its
/// [controller].
class TomPdfEditor extends StatefulWidget {
  const TomPdfEditor({
    super.key,
    required this.controller,
    this.onCopy,
    this.decoder = decodeBgra,
    this.showPageList = true,
    this.onFind,
  });

  /// Cmd+F and the zoom bar's find button: the host's find bar (the Forge
  /// shell's) instead of the editor's own, which then stays hidden.
  final VoidCallback? onFind;

  /// The controller.
  final TomPdfEditorController controller;

  /// Puts copied text on the clipboard; default: Flutter's plain-text
  /// clipboard.
  final Future<void> Function(String text)? onCopy;

  /// Decodes rendered pixels (a test may pass its own).
  final PdfImageDecoder decoder;

  /// Whether the page list shows.
  final bool showPageList;

  @override
  State<TomPdfEditor> createState() => _TomPdfEditorState();
}

class _TomPdfEditorState extends State<TomPdfEditor> {
  TomPdfEditorController get _c => widget.controller;
  final _cache = PdfRenderCache();
  double _zoom = 100;
  bool _zoomSet = false;
  StreamSubscription<(String, String)>? _notices;
  Timer? _heartbeat;
  FlutterExceptionHandler? _previousOnError;
  final _viewKey = GlobalKey<PdfPageViewState>();

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _notices = _c.notices.listen((n) {
      if (mounted) _c.host.notice(context, n.$2, kind: n.$1);
    });
    if (kPdfEditorDebug) {
      _previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        pdfTrail('FlutterError: ${details.exceptionAsString()}');
        _previousOnError?.call(details);
      };
      _heartbeat = Timer.periodic(
        const Duration(seconds: 1),
        (_) => pdfTrail('heartbeat'),
      );
    }
  }

  @override
  void didUpdateWidget(TomPdfEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      unawaited(_notices?.cancel());
      widget.controller.addListener(_changed);
      _notices = widget.controller.notices.listen((n) {
        if (mounted) widget.controller.host.notice(context, n.$2, kind: n.$1);
      });
      _cache.clear();
      _zoomSet = false;
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    if (kPdfEditorDebug) FlutterError.onError = _previousOnError;
    unawaited(_notices?.cancel());
    _c.removeListener(_changed);
    _cache.clear();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _setZoom(double zoom) {
    pdfTrail('zoom ${zoom.round()} %');
    setState(() {
      _zoom = zoom.clamp(10, 800);
      _zoomSet = true;
    });
    final p = _viewKey.currentState?.position;
    _c.rememberView(
      PdfViewPosition(
        page: p?.$1 ?? _c.viewPosition?.page ?? 0,
        offset: p?.$2 ?? _c.viewPosition?.offset ?? 0,
        zoom: _zoom,
      ),
    );
  }

  void _onPosition(int page, double offset) =>
      _c.rememberView(PdfViewPosition(page: page, offset: offset, zoom: _zoom));

  /// A position the host asked for ([TomPdfEditorController.restoreView]):
  /// the zoom now, the scroll once the pages are laid out at it.
  void _applyPendingView() {
    final pending = _c.takePendingView();
    if (pending == null) return;
    pdfTrail('restore view $pending');
    _zoom = pending.zoom.clamp(10, 800).toDouble();
    _zoomSet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewKey.currentState?.scrollToPosition(pending.page, pending.offset);
      _c.rememberView(pending);
    });
  }

  Future<void> _copy(String text) async {
    final onCopy = widget.onCopy;
    if (onCopy != null) return onCopy(text);
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) => switch (_c.state) {
    TomPdfEditorState.idle || TomPdfEditorState.opening => const Center(
      child: CircularProgressIndicator(),
    ),
    TomPdfEditorState.password => _PasswordPanel(controller: _c),
    TomPdfEditorState.failed ||
    TomPdfEditorState.closed => _FailurePanel(controller: _c),
    TomPdfEditorState.open || TomPdfEditorState.saving => _open(context),
  };

  Widget _open(BuildContext context) {
    final info = _c.info!;
    _applyPendingView();
    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = widget.showPageList ? 168.0 : 0.0;
        if (!_zoomSet && info.pageCount > 0) {
          // Opens at fit width, at most 100 %.
          _zoom = fitWidthZoom(
            info.pages,
            constraints.maxWidth - listWidth,
          ).clamp(10, 100).toDouble();
        }
        return Column(
          children: [
            if (_c.isReadOnly) _ReadOnlyBar(controller: _c),
            if (info.encrypted) _EncryptedBar(controller: _c),
            if (_c.conflict != null) _ConflictBanner(controller: _c),
            if (_c.isDeleted && _c.conflict == null)
              _Bar(
                icon: Icons.delete_outline,
                text: 'This file was deleted on disk. Saving recreates it.',
              ),
            _ZoomBar(
              zoom: _zoom,
              onZoom: _setZoom,
              onFitWidth: () => _setZoom(
                fitWidthZoom(info.pages, constraints.maxWidth - listWidth),
              ),
              onFitPage: () {
                final view = _viewKey.currentState;
                final page = view == null || !view.vertical.hasClients
                    ? 0
                    : view.layout.pageAt(view.vertical.offset + 1);
                _setZoom(
                  fitPageZoom(
                    info.pages[page],
                    Size(
                      constraints.maxWidth - listWidth,
                      constraints.maxHeight - 40,
                    ),
                  ),
                );
              },
              onFind: widget.onFind ?? _c.showFind,
              pageCount: info.pageCount,
            ),
            _AnnotationBar(controller: _c),
            Expanded(
              child: Row(
                children: [
                  if (widget.showPageList)
                    SizedBox(
                      width: listWidth,
                      child: _PageList(controller: _c, decoder: widget.decoder),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: PdfPageView(
                            key: _viewKey,
                            controller: _c,
                            zoom: _zoom,
                            onZoom: _setZoom,
                            onCopy: _copy,
                            decoder: widget.decoder,
                            cache: _cache,
                            onPosition: _onPosition,
                            onFind: widget.onFind,
                          ),
                        ),
                        if (_c.findVisible)
                          Positioned(
                            top: 8,
                            right: 16,
                            child: _FindBar(controller: _c),
                          ),
                        if (_c.state == TomPdfEditorState.saving)
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------------------------- bars

class _Bar extends StatelessWidget {
  const _Bar({required this.icon, required this.text, this.actions = const []});

  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBar extends StatelessWidget {
  const _ReadOnlyBar({required this.controller});

  final TomPdfEditorController controller;

  @override
  Widget build(BuildContext context) => _Bar(
    icon: Icons.lock_outline,
    text: switch (controller.readOnlyReason!) {
      TomPdfReadOnlyReason.notWritable =>
        'Read-only: the file cannot be written.',
      TomPdfReadOnlyReason.hostAsked => 'Read-only.',
    },
    actions: [
      TextButton(
        onPressed: () => unawaited(controller.saveAsCopy()),
        child: const Text('Save as copy'),
      ),
    ],
  );
}

class _EncryptedBar extends StatelessWidget {
  const _EncryptedBar({required this.controller});

  final TomPdfEditorController controller;

  @override
  Widget build(BuildContext context) => _Bar(
    icon: Icons.enhanced_encryption_outlined,
    text:
        'Encrypted: view only — annotations and form filling are not '
        'available.',
    actions: [
      TextButton(
        key: const ValueKey('pdf-save-unencrypted'),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Save an unencrypted copy?'),
              content: const Text(
                'The copy is not encrypted: anyone who has the file can open '
                'it without the password, and its restrictions no longer '
                'apply. The original stays as it is.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('pdf-save-unencrypted-ok'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save unencrypted copy'),
                ),
              ],
            ),
          );
          if (ok ?? false) await controller.saveUnencryptedCopy();
        },
        child: const Text('Save as copy…'),
      ),
    ],
  );
}

/// The colours offered for annotations.
const kPdfAnnotationColors = [
  0xFFFFEB3B, // yellow
  0xFF66BB6A, // green
  0xFF42A5F5, // blue
  0xFFEC407A, // pink
  0xFFE53935, // red
  0xFF212121, // black
];

class _AnnotationBar extends StatelessWidget {
  const _AnnotationBar({required this.controller});

  final TomPdfEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled = c.canAnnotate;
    final selected = c.selectedAnnotation;
    final page = c.selectedAnnotationPage;
    final scheme = Theme.of(context).colorScheme;
    final current = selected?.color ?? c.toolColor(c.tool);
    Widget tool(PdfAnnotationTool t, IconData icon, String tip) => IconButton(
      key: ValueKey('pdf-tool-${t.name}'),
      tooltip: enabled ? tip : 'Annotations are not available',
      iconSize: 18,
      isSelected: c.tool == t,
      color: c.tool == t ? scheme.primary : null,
      icon: Icon(icon),
      onPressed: enabled ? () => c.setTool(t) : null,
    );
    final colorTarget =
        selected != null || (c.tool != PdfAnnotationTool.select);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 36,
        child: _ToolbarRow(
          children: [
            const SizedBox(width: 8),
            tool(
              PdfAnnotationTool.select,
              Icons.near_me_outlined,
              'Select (V)',
            ),
            tool(PdfAnnotationTool.highlight, Icons.highlight, 'Highlight (H)'),
            tool(
              PdfAnnotationTool.note,
              Icons.sticky_note_2_outlined,
              'Note (N)',
            ),
            tool(PdfAnnotationTool.ink, Icons.draw_outlined, 'Ink (I)'),
            const VerticalDivider(width: 16),
            for (final color in kPdfAnnotationColors)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  key: ValueKey('pdf-color-${color.toRadixString(16)}'),
                  onTap: enabled && colorTarget
                      ? () {
                          if (selected != null) {
                            unawaited(
                              c.recolorAnnotation(page!, selected.id, color),
                            );
                          } else {
                            c.setToolColor(c.tool, color);
                          }
                        }
                      : null,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Color(
                        enabled && colorTarget ? color : color & 0x55FFFFFF,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            (current & 0xFFFFFF) == (color & 0xFFFFFF) &&
                                colorTarget
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            if (selected != null) ...[
              const VerticalDivider(width: 16),
              if (selected.kind == PdfAnnotationKind.note)
                IconButton(
                  key: const ValueKey('pdf-edit-note'),
                  tooltip: 'Edit note',
                  iconSize: 18,
                  icon: const Icon(Icons.edit_note),
                  onPressed: () async {
                    final text = await showPdfNoteDialog(
                      context,
                      initial: selected.contents,
                    );
                    if (text != null) {
                      await c.setNoteText(page!, selected.id, text);
                    }
                  },
                ),
              IconButton(
                key: const ValueKey('pdf-delete-annotation'),
                tooltip: 'Delete (⌫)',
                iconSize: 18,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    unawaited(c.deleteAnnotation(page!, selected.id)),
              ),
            ],
            const Spacer(),
            IconButton(
              key: const ValueKey('pdf-undo'),
              tooltip: c.canUndo ? 'Undo ${c.undoLabel ?? ''}'.trim() : 'Undo',
              iconSize: 18,
              icon: const Icon(Icons.undo),
              onPressed: c.canUndo ? () => unawaited(c.undo()) : null,
            ),
            IconButton(
              key: const ValueKey('pdf-redo'),
              tooltip: 'Redo',
              iconSize: 18,
              icon: const Icon(Icons.redo),
              onPressed: c.canRedo ? () => unawaited(c.redo()) : null,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.controller});

  final TomPdfEditorController controller;

  @override
  Widget build(BuildContext context) {
    final deleted = controller.conflict!.deleted;
    return _Bar(
      icon: Icons.warning_amber,
      text: deleted
          ? 'The file was deleted on disk since it was opened.'
          : 'The file changed on disk since it was opened.',
      actions: [
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Keep mine?'),
                content: Text(
                  deleted
                      ? 'The file will be written again from this document.'
                      : 'The changes made to the file on disk will be lost.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Keep mine'),
                  ),
                ],
              ),
            );
            if (ok ?? false) await controller.keepMine();
          },
          child: const Text('Keep mine'),
        ),
        TextButton(
          onPressed: () => unawaited(controller.takeTheirs()),
          child: const Text('Take theirs'),
        ),
        TextButton(
          onPressed: () => unawaited(controller.saveAsCopy()),
          child: const Text('Save as copy'),
        ),
      ],
    );
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({
    required this.zoom,
    required this.onZoom,
    required this.onFitWidth,
    required this.onFitPage,
    required this.onFind,
    required this.pageCount,
  });

  final double zoom;
  final ValueChanged<double> onZoom;
  final VoidCallback onFitWidth;
  final VoidCallback onFitPage;
  final VoidCallback onFind;
  final int pageCount;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SizedBox(
      height: 36,
      child: _ToolbarRow(
        children: [
          const SizedBox(width: 8),
          Text('$pageCount ${pageCount == 1 ? 'page' : 'pages'}'),
          const Spacer(),
          IconButton(
            tooltip: 'Zoom out',
            iconSize: 18,
            icon: const Icon(Icons.zoom_out),
            onPressed: () => onZoom(zoomStepDown(zoom)),
          ),
          SizedBox(
            width: 48,
            child: Text('${zoom.round()} %', textAlign: TextAlign.center),
          ),
          IconButton(
            tooltip: 'Zoom in',
            iconSize: 18,
            icon: const Icon(Icons.zoom_in),
            onPressed: () => onZoom(zoomStepUp(zoom)),
          ),
          TextButton(onPressed: onFitWidth, child: const Text('Fit width')),
          TextButton(onPressed: onFitPage, child: const Text('Fit page')),
          IconButton(
            tooltip: 'Find',
            iconSize: 18,
            icon: const Icon(Icons.search),
            onPressed: onFind,
          ),
          const SizedBox(width: 8),
        ],
      ),
    ),
  );
}

// ----------------------------------------------------------------- find bar

class _FindBar extends StatefulWidget {
  const _FindBar({required this.controller});

  final TomPdfEditorController controller;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  late final _text = TextEditingController(text: widget.controller.findTerm);
  bool _case = false;
  bool _word = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search() =>
      widget.controller.find(_text.text, matchCase: _case, wholeWord: _word);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final count = c.hits.isEmpty
        ? (c.findTerm.isEmpty ? '' : (c.searching ? '…' : 'none'))
        : '${c.currentHit + 1} / ${c.hits.length}${c.searching ? '…' : ''}';
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                key: const ValueKey('pdf-find-field'),
                controller: _text,
                focusNode: _focus,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Find',
                ),
                onSubmitted: (_) =>
                    c.findTerm == _text.text && c.hits.isNotEmpty
                    ? c.nextHit()
                    : _search(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(count, key: const ValueKey('pdf-find-count')),
            ),
            Tooltip(
              message: 'Match case',
              child: Checkbox(
                value: _case,
                onChanged: (v) {
                  setState(() => _case = v ?? false);
                  _search();
                },
              ),
            ),
            const Text('Aa'),
            Tooltip(
              message: 'Whole word',
              child: Checkbox(
                value: _word,
                onChanged: (v) {
                  setState(() => _word = v ?? false);
                  _search();
                },
              ),
            ),
            const Text('W'),
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: c.previousHit,
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: c.nextHit,
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: c.hideFind,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- page list

class _PageList extends StatefulWidget {
  const _PageList({required this.controller, required this.decoder});

  final TomPdfEditorController controller;
  final PdfImageDecoder decoder;

  @override
  State<_PageList> createState() => _PageListState();
}

class _PageListState extends State<_PageList> {
  // Thumbnails 120 logical pixels wide, at most 200 kept.
  final _thumbs = <int, ui.Image>{};
  final _thumbVersions = <int, int>{};
  final _pending = <int, int>{};
  var _ticket = 1 << 30;
  int _generation = -1;
  bool _outline = false;

  TomPdfEditorController get _c => widget.controller;

  @override
  void didUpdateWidget(_PageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      for (final t in _pending.values) {
        oldWidget.controller.engine?.cancel(t);
      }
      _pending.clear();
      for (final i in _thumbs.values) {
        i.dispose();
      }
      _thumbs.clear();
      _generation = -1;
    }
  }

  @override
  void dispose() {
    for (final t in _pending.values) {
      _c.engine?.cancel(t);
    }
    for (final i in _thumbs.values) {
      i.dispose();
    }
    super.dispose();
  }

  void _need(int page, double dpr) {
    final info = _c.info;
    final engine = _c.engine;
    if (info == null || engine == null) return;
    final version = _c.pageVersion(page);
    if ((_thumbs.containsKey(page) && _thumbVersions[page] == version) ||
        _pending.containsKey(page)) {
      return;
    }
    final size = info.pages[page];
    final scale = 120 * dpr / size.width;
    final ticket = _ticket++;
    _pending[page] = ticket;
    final generation = _c.generation;
    unawaited(
      engine
          .render(
            info.handle,
            page,
            scale: scale,
            x: 0,
            y: 0,
            pxW: (size.width * scale).round().clamp(1, 4096),
            pxH: (size.height * scale).round().clamp(1, 4096),
            priority: PdfRenderPriority.thumbnail,
            ticket: ticket,
          )
          .then((r) async {
            _pending.remove(page);
            if (r == null ||
                !mounted ||
                generation != _c.generation ||
                _c.info == null) {
              return;
            }
            final image = await widget.decoder(r.bgra, r.pxW, r.pxH);
            if (!mounted) {
              image.dispose();
              return;
            }
            _thumbs.remove(page)?.dispose();
            _thumbs[page] = image;
            _thumbVersions[page] = version;
            while (_thumbs.length > 200) {
              _thumbs.remove(_thumbs.keys.first)!.dispose();
            }
            setState(() {});
          })
          .catchError((Object e, StackTrace s) {
            _pending.remove(page);
            pdfReport(e, s, 'thumbnail $page');
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _c.info!;
    if (_generation != _c.generation) {
      _generation = _c.generation;
      for (final i in _thumbs.values) {
        i.dispose();
      }
      _thumbs.clear();
      _pending.clear();
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final hasOutline = info.outline.isNotEmpty;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          if (hasOutline)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _outline = false),
                    child: Text(
                      'Pages',
                      style: TextStyle(
                        fontWeight: _outline ? null : FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _outline = true),
                    child: Text(
                      'Outline',
                      style: TextStyle(
                        fontWeight: _outline ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          Expanded(
            child: _outline && hasOutline
                ? ListView(children: _outlineTiles(info.outline, 0))
                : ListView.builder(
                    itemCount: info.pageCount,
                    itemExtent: null,
                    itemBuilder: (context, page) {
                      _need(page, dpr);
                      final size = info.pages[page];
                      final image = _thumbs[page];
                      return InkWell(
                        key: ValueKey('pdf-thumb-$page'),
                        onTap: () => _c.scrollRequest.value = (page, null),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120 * size.height / size.width,
                                child: image == null
                                    ? const ColoredBox(color: Color(0xFFE6E6E6))
                                    : RawImage(
                                        image: image,
                                        fit: BoxFit.contain,
                                      ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${page + 1}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _outlineTiles(List<PdfOutlineEntry> entries, int depth) => [
    for (final e in entries) ...[
      InkWell(
        onTap: e.page == null
            ? null
            : () => _c.scrollRequest.value = (e.page!, null),
        child: Padding(
          padding: EdgeInsets.only(
            left: 8.0 + depth * 12,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
      ..._outlineTiles(e.children, depth + 1),
    ],
  ];
}

// --------------------------------------------------------- password, failure

class _PasswordPanel extends StatefulWidget {
  const _PasswordPanel({required this.controller});

  final TomPdfEditorController controller;

  @override
  State<_PasswordPanel> createState() => _PasswordPanelState();
}

class _PasswordPanelState extends State<_PasswordPanel> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text;
    _text.clear();
    unawaited(widget.controller.answerPassword(value));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Center(
      child: SizedBox(
        width: 360,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.host.name} is protected by a password.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (c.passwordWrong)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'The password was wrong (attempt ${c.passwordAttempt} of 3).',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('pdf-password-field'),
                  controller: _text,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => unawaited(c.answerPassword(null)),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _submit, child: const Text('Open')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({required this.controller});

  final TomPdfEditorController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            controller.failure ?? 'The document is closed.',
            textAlign: TextAlign.center,
            key: const ValueKey('pdf-failure'),
          ),
          if (controller.state == TomPdfEditorState.failed) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => unawaited(controller.open()),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A toolbar's row: as wide as the editor, its [Spacer]s taking the room
/// left; scrolled sideways when the editor is narrower than its buttons (a
/// split pane).
class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: IntrinsicWidth(child: Row(children: children)),
      ),
    ),
  );
}
