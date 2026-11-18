// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Up to this width in physical pixels a page renders as one bitmap; above
/// it, as [kPdfTileSize] tiles.
const kPdfWholePageLimit = 2048;

/// The tile size, in physical pixels, above [kPdfWholePageLimit].
const kPdfTileSize = 512;

/// One piece of a page to render: its key and its pixel rectangle in the
/// page rendered at the key's scale.
@immutable
final class PdfTile {
  /// A tile from its parts.
  const PdfTile(this.key, this.x, this.y, this.pxW, this.pxH);

  /// Its cache key.
  final PdfTileKey key;

  /// The left edge, in physical pixels of the rendered page.
  final int x;

  /// The top edge.
  final int y;

  /// The width.
  final int pxW;

  /// The height.
  final int pxH;
}

/// A tile's place: page, scale (physical pixels per point, ×1000), column,
/// row. A page rendered whole is column 0, row 0 with [whole] set.
@immutable
final class PdfTileKey {
  /// A key from its parts.
  const PdfTileKey(
    this.page,
    this.scaleKey,
    this.column,
    this.row, {
    this.whole = false,
  });

  /// The page.
  final int page;

  /// Physical pixels per point × 1000, rounded: one zoom at one device
  /// pixel ratio.
  final int scaleKey;

  /// The column.
  final int column;

  /// The row.
  final int row;

  /// Whether the tile is the whole page.
  final bool whole;

  /// The scale as physical pixels per point.
  double get scale => scaleKey / 1000;

  @override
  bool operator ==(Object other) =>
      other is PdfTileKey &&
      other.page == page &&
      other.scaleKey == scaleKey &&
      other.column == column &&
      other.row == row &&
      other.whole == whole;

  @override
  int get hashCode => Object.hash(page, scaleKey, column, row, whole);

  @override
  String toString() =>
      'tile(p$page, ${scale.toStringAsFixed(3)}, $column, $row${whole ? ', whole' : ''})';
}

/// The tiles of a page of [pageWidth] × [pageHeight] points at [scale]
/// physical pixels per point that intersect [visible] (physical pixels of the
/// rendered page; `null`: all of it).
List<PdfTile> planTiles(
  int page,
  double pageWidth,
  double pageHeight,
  double scale, {
  ({int left, int top, int right, int bottom})? visible,
}) {
  final scaleKey = (scale * 1000).round();
  final w = math.max(1, (pageWidth * scale).round());
  final h = math.max(1, (pageHeight * scale).round());
  if (w <= kPdfWholePageLimit) {
    return [PdfTile(PdfTileKey(page, scaleKey, 0, 0, whole: true), 0, 0, w, h)];
  }
  final c0 = visible == null ? 0 : math.max(0, visible.left ~/ kPdfTileSize);
  final r0 = visible == null ? 0 : math.max(0, visible.top ~/ kPdfTileSize);
  final c1 = visible == null
      ? (w - 1) ~/ kPdfTileSize
      : math.min((w - 1) ~/ kPdfTileSize, visible.right ~/ kPdfTileSize);
  final r1 = visible == null
      ? (h - 1) ~/ kPdfTileSize
      : math.min((h - 1) ~/ kPdfTileSize, visible.bottom ~/ kPdfTileSize);
  return [
    for (var r = r0; r <= r1; r++)
      for (var c = c0; c <= c1; c++)
        PdfTile(
          PdfTileKey(page, scaleKey, c, r),
          c * kPdfTileSize,
          r * kPdfTileSize,
          math.min(kPdfTileSize, w - c * kPdfTileSize),
          math.min(kPdfTileSize, h - r * kPdfTileSize),
        ),
  ];
}

/// One cached image.
final class PdfCacheEntry {
  PdfCacheEntry(this.image, this.x, this.y);

  /// The image.
  final ui.Image image;

  /// Its left edge in physical pixels of the rendered page.
  final int x;

  /// Its top edge.
  final int y;

  /// What it holds in memory.
  int get bytes => image.width * image.height * 4;
}

/// The rendered images: least-recently used, bounded by memory (256 MiB by
/// default). Images of another zoom stay until the new zoom's have arrived,
/// so a zoom change shows the old images scaled.
class PdfRenderCache {
  /// A cache of at most [maxBytes].
  PdfRenderCache({this.maxBytes = 256 * 1024 * 1024});

  /// The bound.
  final int maxBytes;

  final _entries = <PdfTileKey, PdfCacheEntry>{};
  int _bytes = 0;

  /// What the cache holds.
  int get bytes => _bytes;

  /// The number of images.
  int get length => _entries.length;

  /// The image at [key], marked as used.
  PdfCacheEntry? get(PdfTileKey key) {
    final e = _entries.remove(key);
    if (e != null) _entries[key] = e;
    return e;
  }

  /// Whether [key] is cached.
  bool contains(PdfTileKey key) => _entries.containsKey(key);

  /// Stores an image, evicting the least recently used over the bound
  /// (never one in [keep]).
  void put(
    PdfTileKey key,
    ui.Image image,
    int x,
    int y, {
    Set<PdfTileKey> keep = const {},
  }) {
    final old = _entries.remove(key);
    if (old != null) {
      _bytes -= old.bytes;
      old.image.dispose();
    }
    final entry = PdfCacheEntry(image, x, y);
    _entries[key] = entry;
    _bytes += entry.bytes;
    if (_bytes <= maxBytes) return;
    final victims = <PdfTileKey>[];
    var bytes = _bytes;
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (bytes <= maxBytes) break;
      if (keep.contains(key)) continue;
      victims.add(key);
      bytes -= value.bytes;
    }
    for (final k in victims) {
      final e = _entries.remove(k)!;
      _bytes -= e.bytes;
      e.image.dispose();
    }
  }

  /// The images of [page] at any scale other than [scaleKey] (the fallback
  /// while the current scale's images are rendered).
  Iterable<(PdfTileKey, PdfCacheEntry)> otherScales(int page, int scaleKey) =>
      _entries.entries
          .where((e) => e.key.page == page && e.key.scaleKey != scaleKey)
          .map((e) => (e.key, e.value));

  /// Drops the images of [page] at scales other than [scaleKey].
  void dropOtherScales(int page, int scaleKey) {
    final victims = _entries.keys
        .where((k) => k.page == page && k.scaleKey != scaleKey)
        .toList();
    for (final k in victims) {
      final e = _entries.remove(k)!;
      _bytes -= e.bytes;
      e.image.dispose();
    }
  }

  /// Drops everything (a reopened document).
  void clear() {
    for (final e in _entries.values) {
      e.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }
}
