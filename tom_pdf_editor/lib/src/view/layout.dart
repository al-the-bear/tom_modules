// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:math' as math;
import 'dart:ui';

import '../engine/engine.dart';

/// The zoom steps, in percent (WD: 50–400 %, plus fit width and fit page).
const kPdfZoomSteps = [50, 75, 100, 125, 150, 200, 300, 400];

/// Logical pixels per point at 100 %: 96 / 72, so a page shows at its
/// printed size on a 96-dpi screen.
const kPdfPixelsPerPoint = 96 / 72;

/// The gap between pages, in logical pixels.
const kPdfPageGap = 8.0;

/// The pages laid out in one vertical column at a zoom, in logical pixels;
/// known from the page sizes alone, without loading a page.
class PdfLayout {
  /// The layout of [pages] at [zoom] percent.
  PdfLayout(this.pages, this.zoom) {
    var y = kPdfPageGap;
    var width = 0.0;
    for (final p in pages) {
      final w = p.width * scale;
      final h = p.height * scale;
      _tops.add(y);
      y += h + kPdfPageGap;
      width = math.max(width, w);
    }
    height = y;
    this.width = width + 2 * kPdfPageGap;
  }

  /// Every page's size in view points.
  final List<PdfPageSize> pages;

  /// The zoom in percent.
  final double zoom;

  final _tops = <double>[];

  /// The column's height.
  late final double height;

  /// The widest page plus its margins.
  late final double width;

  /// Logical pixels per point.
  double get scale => zoom / 100 * kPdfPixelsPerPoint;

  /// [page]'s rectangle in the column, centred horizontally in a viewport
  /// [viewportWidth] wide (or in the column, when that is wider).
  Rect pageRect(int page, double viewportWidth) {
    final w = pages[page].width * scale;
    final h = pages[page].height * scale;
    final left = (math.max(viewportWidth, width) - w) / 2;
    return Rect.fromLTWH(left, _tops[page], w, h);
  }

  /// The pages that intersect the vertical span [top]–[bottom].
  List<int> pagesIn(double top, double bottom) {
    final out = <int>[];
    var i = _firstAtOrBelow(top);
    for (; i < pages.length && _tops[i] <= bottom; i++) {
      if (_tops[i] + pages[i].height * scale >= top) out.add(i);
    }
    return out;
  }

  /// The page whose band holds [y] (the nearest one at a gap).
  int pageAt(double y) {
    if (pages.isEmpty) return 0;
    final i = _firstAtOrBelow(y);
    return i.clamp(0, pages.length - 1);
  }

  int _firstAtOrBelow(double y) {
    // The last page whose top is at or above y (binary search).
    var lo = 0;
    var hi = pages.length - 1;
    var found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_tops[mid] <= y) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// The top of [page] in the column.
  double pageTop(int page) => _tops[page];

  /// A position in the column → (page, view points), or `null` when it is
  /// outside every page.
  (int, Offset)? hit(Offset position, double viewportWidth) {
    final page = pageAt(position.dy);
    if (page >= pages.length) return null;
    final rect = pageRect(page, viewportWidth);
    if (!rect.contains(position)) return null;
    return (
      page,
      Offset(
        (position.dx - rect.left) / scale,
        (position.dy - rect.top) / scale,
      ),
    );
  }

  /// A view-point rectangle of [page] → the column.
  Rect toColumn(int page, PdfRect r, double viewportWidth) {
    final rect = pageRect(page, viewportWidth);
    return Rect.fromLTRB(
      rect.left + r.left * scale,
      rect.top + r.top * scale,
      rect.left + r.right * scale,
      rect.top + r.bottom * scale,
    );
  }
}

/// The zoom that fits the widest page into [viewportWidth].
double fitWidthZoom(List<PdfPageSize> pages, double viewportWidth) {
  final widest = pages.fold<double>(1, (m, p) => math.max(m, p.width));
  return ((viewportWidth - 2 * kPdfPageGap) /
          (widest * kPdfPixelsPerPoint) *
          100)
      .clamp(10, 800);
}

/// The zoom that fits [page] whole into the viewport.
double fitPageZoom(PdfPageSize page, Size viewport) {
  final zw =
      (viewport.width - 2 * kPdfPageGap) / (page.width * kPdfPixelsPerPoint);
  final zh =
      (viewport.height - 2 * kPdfPageGap) / (page.height * kPdfPixelsPerPoint);
  return (math.min(zw, zh) * 100).clamp(10, 800);
}

/// The next zoom step up from [zoom] (or [zoom] at the top).
double zoomStepUp(double zoom) => kPdfZoomSteps
    .map((s) => s.toDouble())
    .firstWhere((s) => s > zoom + 0.5, orElse: () => zoom);

/// The next zoom step down from [zoom] (or [zoom] at the bottom).
double zoomStepDown(double zoom) => kPdfZoomSteps.reversed
    .map((s) => s.toDouble())
    .firstWhere((s) => s < zoom - 0.5, orElse: () => zoom);
