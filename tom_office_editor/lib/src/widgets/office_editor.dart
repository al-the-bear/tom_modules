// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tom_office_protocol/tom_office_protocol.dart';
import 'package:tom_ui_support/tom_ui_support.dart';

import '../callbacks.dart';
import '../controller.dart';
import '../detection/installation.dart';
import '../office_editor_trail.dart';
import '../ribbon/ribbon.dart';
import '../ribbon/ribbon_model.dart';
import 'document_view.dart';
import 'panels.dart';

/// The office editor: one document served by its helper, with the panels
/// around it (`part-office-editor`). The ribbon and LibreOffice's dialogs
/// are added by later parts; until then a dialog LibreOffice opens is closed
/// with a notice.
class TomOfficeEditor extends StatefulWidget {
  /// The editor of [controller]'s document. The detection callbacks add
  /// their buttons to the view of a missing, old or quarantined
  /// LibreOffice.
  const TomOfficeEditor({
    super.key,
    required this.controller,
    this.onCheckAgain,
    this.onChooseLibreOffice,
    this.onOpenLibreOffice,
    this.focusNode,
    this.showRibbon = true,
  });

  /// The document.
  final TomOfficeEditorController controller;

  /// *Check again* (detection runs again; the host then reopens).
  final VoidCallback? onCheckAgain;

  /// *Choose LibreOffice…*.
  final VoidCallback? onChooseLibreOffice;

  /// *Open LibreOffice* for a quarantined copy.
  final VoidCallback? onOpenLibreOffice;

  /// The document view's focus node.
  final FocusNode? focusNode;

  /// Whether the ribbon is shown above the document.
  final bool showRibbon;

  @override
  State<TomOfficeEditor> createState() => TomOfficeEditorWidgetState();
}

/// The editor widget's state.
class TomOfficeEditorWidgetState extends State<TomOfficeEditor> {
  final _viewKey = GlobalKey<TomOfficeDocumentViewState>();
  StreamSubscription<TomOfficeNotice>? _notices;
  int? _zoom = 100;
  Timer? _heartbeat;
  FlutterExceptionHandler? _previousOnError;
  TomOfficeSheetHeaders? _headers;
  OfficeTwipRect? _visible;
  Timer? _headerTimer;

  TomOfficeEditorController get _c => widget.controller;

  /// The document view (for a host's tests).
  TomOfficeDocumentViewState? get documentView => _viewKey.currentState;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _notices = _c.notices.listen(_showNotice);
    if (kOfficeEditorDebug) {
      officeTrail('editor init ${_c.host.name}');
      _heartbeat = Timer.periodic(
        const Duration(seconds: 1),
        (_) => officeTrail('heartbeat ${_c.state.name}'),
      );
      _previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        officeTrail('FLUTTER ERROR ${details.exceptionAsString()}');
        (_previousOnError ?? FlutterError.presentError)(details);
      };
    }
  }

  @override
  void didUpdateWidget(TomOfficeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      unawaited(_notices?.cancel());
      _notices = widget.controller.notices.listen(_showNotice);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    unawaited(_notices?.cancel());
    _headerTimer?.cancel();
    _heartbeat?.cancel();
    if (_heartbeat != null) {
      FlutterError.onError = _previousOnError;
      officeTrail('editor dispose ${_c.host.name}');
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _showNotice(TomOfficeNotice notice) {
    if (!mounted) return;
    _c.host.notice(context, notice.message, kind: notice.kind);
  }

  // ------------------------------------------------------- the conflict

  Future<void> _keepMine() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep your version?'),
        content: Text(
          'The version of ${_c.host.name} on disk is replaced by yours; '
          'the changes made to it outside this editor are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('office-keep-mine-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (ok == true) await _c.keepMine();
  }

  Future<void> _saveAsCopy() async {
    if (_c.isPasswordProtected) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save a copy?'),
          content: Text(
            '${_c.host.name} is password-protected. The copy is written '
            'beside it as LibreOffice saves it, with the same password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('office-copy-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save copy'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _c.saveAsCopy();
  }

  // ------------------------------------------------------------ ribbon

  void _local(RibbonLocalAction action) {
    final view = _viewKey.currentState;
    switch (action) {
      case RibbonLocalAction.copy:
        view?.perform(TomOfficeEditCommand.copy);
      case RibbonLocalAction.cut:
        view?.perform(TomOfficeEditCommand.cut);
      case RibbonLocalAction.paste:
        view?.perform(TomOfficeEditCommand.paste);
      case RibbonLocalAction.zoomIn:
      case RibbonLocalAction.zoomOut:
        final now = _zoom ?? _c.zoom;
        final up = action == RibbonLocalAction.zoomIn;
        setState(
          () => _zoom = up
              ? kOfficeZoomSteps.firstWhere(
                  (z) => z > now,
                  orElse: () => kOfficeZoomSteps.last,
                )
              : kOfficeZoomSteps.lastWhere(
                  (z) => z < now,
                  orElse: () => kOfficeZoomSteps.first,
                ),
        );
      case RibbonLocalAction.insertImage:
        unawaited(_c.insertImage());
    }
  }

  // ----------------------------------------------------- sheet headers

  void _onVisible(OfficeTwipRect visible) {
    _visible = visible;
    if (_c.docType != OfficeDocType.spreadsheet) return;
    _headerTimer?.cancel();
    _headerTimer = Timer(const Duration(milliseconds: 100), () async {
      final v = _visible;
      if (v == null) return;
      // From the sheet's origin, so the sizes are absolute.
      final headers = await _c.sheetHeaders(
        OfficeTwipRect(0, 0, v.x + v.w, v.y + v.h),
      );
      if (mounted) setState(() => _headers = headers);
    });
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    switch (_c.state) {
      case TomOfficeEditorState.idle:
      case TomOfficeEditorState.opening:
        return _Loading(name: _c.host.name, progress: _c.progress);
      case TomOfficeEditorState.unavailable:
        return TomOfficeDetectionView(
          installation:
              _c.installation ??
              const LibreOfficeInstallation(state: LibreOfficeState.missing),
          onCheckAgain: widget.onCheckAgain,
          onChooseLibreOffice: widget.onChooseLibreOffice,
          onOpenLibreOffice: widget.onOpenLibreOffice,
          onOpenDownloadPage: () => _c.host.openLink(kLibreOfficeDownloadUrl),
        );
      case TomOfficeEditorState.password:
        return TomOfficePasswordPanel(
          name: _c.host.name,
          request: _c.passwordRequest!,
          onAnswer: _c.answerPassword,
        );
      case TomOfficeEditorState.stopped:
        return TomOfficeMessageView(
          key: const ValueKey('office-stopped'),
          message: 'LibreOffice stopped while showing this document.',
          detail: _c.stopDescription,
          actionLabel: 'Reopen',
          onAction: () => unawaited(_c.reopen()),
        );
      case TomOfficeEditorState.failed:
        return TomOfficeMessageView(
          key: const ValueKey('office-failed'),
          message: _c.error ?? '${_c.host.name} could not be opened.',
          actionLabel: 'Try again',
          onAction: () => unawaited(_c.reopen()),
        );
      case TomOfficeEditorState.closed:
        return const SizedBox.shrink();
      case TomOfficeEditorState.open:
      case TomOfficeEditorState.saving:
        return _document(context);
    }
  }

  Widget _document(BuildContext context) {
    final conflict = _c.conflict;
    final readOnly = _c.readOnlyReason;
    final sheet = _c.docType == OfficeDocType.spreadsheet;
    final slides =
        _c.hasPartSwitcher && _c.docType != OfficeDocType.spreadsheet;
    final view = TomEditingSurface(
      kind: TomEditingSurfaceKind.richText,
      perform: (command) =>
          _viewKey.currentState?.perform(switch (command) {
            TomEditingCommand.cut => TomOfficeEditCommand.cut,
            TomEditingCommand.copy => TomOfficeEditCommand.copy,
            TomEditingCommand.paste => TomOfficeEditCommand.paste,
            TomEditingCommand.selectAll => TomOfficeEditCommand.selectAll,
          }) ??
          false,
      child: _ViewWithHeaders(
        headers: sheet ? _headers : null,
        visible: _visible,
        zoom: _c.zoom,
        child: TomOfficeDocumentView(
          key: _viewKey,
          controller: _c,
          zoom: _zoom,
          focusNode: widget.focusNode,
          onZoom: (z) => setState(() => _zoom = z),
          onVisible: _onVisible,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showRibbon) TomOfficeRibbon(controller: _c, onLocal: _local),
        if (readOnly != null)
          TomOfficeBar(
            key: const ValueKey('office-read-only'),
            message: officeReadOnlyMessage(readOnly, lockedBy: _c.lockedBy),
            actions: [
              TextButton(
                key: const ValueKey('office-save-copy'),
                onPressed: () => unawaited(_saveAsCopy()),
                child: const Text('Save as copy'),
              ),
            ],
          ),
        if (conflict != null)
          TomOfficeBar(
            key: const ValueKey('office-conflict'),
            warning: true,
            message: conflict.deleted
                ? 'The file was deleted since it was opened.'
                : 'The file changed on disk since it was opened.',
            actions: [
              TextButton(
                key: const ValueKey('office-keep-mine'),
                onPressed: () => unawaited(_keepMine()),
                child: const Text('Keep mine'),
              ),
              TextButton(
                key: const ValueKey('office-take-theirs'),
                onPressed: () => unawaited(_c.takeTheirs()),
                child: const Text('Take theirs'),
              ),
              TextButton(
                key: const ValueKey('office-conflict-copy'),
                onPressed: () => unawaited(_c.saveAsCopy()),
                child: const Text('Save as copy'),
              ),
            ],
          )
        else if (_c.fileDeleted)
          const TomOfficeBar(
            key: ValueKey('office-deleted'),
            warning: true,
            message:
                'The file was deleted. Saving writes it again at the same '
                'path.',
          ),
        if (sheet)
          _FormulaLine(address: _c.cellAddress, formula: _c.cellFormula),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (slides) _SlideStrip(controller: _c),
              Expanded(child: view),
            ],
          ),
        ),
        if (sheet && _c.hasPartSwitcher) _SheetTabs(controller: _c),
        _StatusLine(
          controller: _c,
          zoom: _zoom,
          onZoom: (z) => setState(() => _zoom = z),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.name, required this.progress});

  final String name;
  final int? progress;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Opening $name…'),
        const SizedBox(height: 12),
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            key: const ValueKey('office-progress'),
            value: progress == null ? null : progress! / 100,
          ),
        ),
      ],
    ),
  );
}

class _FormulaLine extends StatelessWidget {
  const _FormulaLine({required this.address, required this.formula});

  final String address;
  final String formula;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              address,
              key: const ValueKey('office-cell-address'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const VerticalDivider(width: 12),
          Expanded(
            child: Text(
              formula,
              key: const ValueKey('office-cell-formula'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetTabs extends StatelessWidget {
  const _SheetTabs({required this.controller});

  final TomOfficeEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < c.parts; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                key: ValueKey('office-part-$i'),
                label: Text(
                  i < c.partNames.length ? c.partNames[i] : '${i + 1}',
                ),
                selected: c.currentPart == i,
                onSelected: (_) => c.setPart(i),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _SlideStrip extends StatelessWidget {
  const _SlideStrip({required this.controller});

  final TomOfficeEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      width: 180,
      child: ValueListenableBuilder<int>(
        valueListenable: c.tileRevision,
        builder: (context, _, _) => ListView.builder(
          itemCount: c.parts,
          itemBuilder: (context, i) {
            final image = c.thumbnail(i);
            final selected = c.currentPart == i;
            return InkWell(
              key: ValueKey('office-part-$i'),
              onTap: () => c.setPart(i),
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: AspectRatio(
                  aspectRatio: c.documentSize.height <= 0
                      ? 4 / 3
                      : c.documentSize.width / c.documentSize.height,
                  child: image == null
                      ? Center(child: Text('${i + 1}'))
                      : RawImage(image: image, fit: BoxFit.contain),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.controller,
    required this.zoom,
    required this.onZoom,
  });

  final TomOfficeEditorController controller;
  final int? zoom;
  final ValueChanged<int?> onZoom;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final progress = c.progress;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            const SizedBox(width: 8),
            if (c.state == TomOfficeEditorState.saving)
              const Text('Saving…', key: ValueKey('office-saving')),
            if (progress != null)
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  key: const ValueKey('office-progress'),
                  value: progress / 100,
                ),
              ),
            const Spacer(),
            PopupMenuButton<int?>(
              key: const ValueKey('office-zoom'),
              tooltip: 'Zoom',
              initialValue: zoom,
              onSelected: onZoom,
              itemBuilder: (context) => [
                for (final z in kOfficeZoomSteps)
                  PopupMenuItem(value: z, child: Text('$z %')),
                const PopupMenuItem(value: null, child: Text('Fit width')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  zoom == null ? 'Fit width (${c.zoom} %)' : '$zoom %',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The document view with a spreadsheet's row and column headers.
class _ViewWithHeaders extends StatelessWidget {
  const _ViewWithHeaders({
    required this.headers,
    required this.visible,
    required this.zoom,
    required this.child,
  });

  final TomOfficeSheetHeaders? headers;
  final OfficeTwipRect? visible;
  final int zoom;
  final Widget child;

  static const _rowWidth = 40.0;
  static const _columnHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final h = headers;
    final v = visible;
    if (h == null || v == null) return child;
    final style = Theme.of(context).textTheme.labelSmall;
    final line = Theme.of(context).dividerColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _columnHeight,
          child: Row(
            children: [
              const SizedBox(width: _rowWidth),
              Expanded(
                child: CustomPaint(
                  painter: _HeaderPainter(
                    entries: h.columns,
                    start: h.columnStart,
                    origin: v.x.toDouble(),
                    scale: zoom / 100 / kTwipsPerPixel,
                    horizontal: true,
                    style: style,
                    line: line,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _rowWidth,
                child: CustomPaint(
                  painter: _HeaderPainter(
                    entries: h.rows,
                    start: h.rowStart,
                    origin: v.y.toDouble(),
                    scale: zoom / 100 / kTwipsPerPixel,
                    horizontal: false,
                    style: style,
                    line: line,
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderPainter extends CustomPainter {
  _HeaderPainter({
    required this.entries,
    required this.start,
    required this.origin,
    required this.scale,
    required this.horizontal,
    required this.style,
    required this.line,
  });

  final List<TomOfficeSheetHeader> entries;
  final double start;
  final double origin;
  final double scale;
  final bool horizontal;
  final TextStyle? style;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final stroke = Paint()..color = line;
    var from = start;
    for (final e in entries) {
      final a = (from - origin) * scale;
      final b = (e.endTwips - origin) * scale;
      from = e.endTwips;
      if (b < 0) continue;
      if (a > (horizontal ? size.width : size.height)) break;
      final tp = TextPainter(
        text: TextSpan(text: e.text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (horizontal) {
        canvas.drawLine(Offset(b, 0), Offset(b, size.height), stroke);
        tp.paint(
          canvas,
          Offset((a + b - tp.width) / 2, (size.height - tp.height) / 2),
        );
      } else {
        canvas.drawLine(Offset(0, b), Offset(size.width, b), stroke);
        tp.paint(
          canvas,
          Offset((size.width - tp.width) / 2, (a + b - tp.height) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HeaderPainter old) => true;
}
