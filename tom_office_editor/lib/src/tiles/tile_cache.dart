// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A tile's place: part, zoom, column and row.
@immutable
final class TileKey {
  /// A key from its parts. [zoom] is in percent (100 = 100 %).
  const TileKey(this.part, this.zoom, this.column, this.row);

  /// The part (sheet, slide, page of a drawing).
  final int part;

  /// The zoom in percent; tiles of different zooms never mix.
  final int zoom;

  /// The column, from 0 at the document's left edge.
  final int column;

  /// The row, from 0 at the top.
  final int row;

  @override
  bool operator ==(Object other) =>
      other is TileKey &&
      other.part == part &&
      other.zoom == zoom &&
      other.column == column &&
      other.row == row;

  @override
  int get hashCode => Object.hash(part, zoom, column, row);

  @override
  String toString() => 'tile($part, $zoom%, $column, $row)';
}

/// One cached tile.
final class TileEntry {
  TileEntry(this.image, this.bytes);

  /// The decoded tile.
  final ui.Image image;

  /// What it holds in memory (`w × h × 4`).
  final int bytes;

  /// Whether an invalidation touched it: still shown, requested again.
  bool stale = false;
}

/// The editor's tiles: least-recently used, bounded by memory (256 MiB by
/// default, about 1000 tiles of 256 × 256 at device pixel ratio 2).
class TileCache {
  /// A cache of at most [maxBytes].
  TileCache({this.maxBytes = 256 * 1024 * 1024});

  /// The bound.
  final int maxBytes;

  // LinkedHashMap keeps insertion order: re-inserting on use makes the first
  // entry the least recently used.
  final _entries = <TileKey, TileEntry>{};
  int _bytes = 0;

  /// What the cache holds in memory.
  int get bytes => _bytes;

  /// The number of tiles.
  int get length => _entries.length;

  /// The tile at [key], marked as used; `null` when there is none.
  TileEntry? get(TileKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry;
  }

  /// The tile at [key] without touching its use.
  TileEntry? peek(TileKey key) => _entries[key];

  /// Whether a tile is cached at [key].
  bool contains(TileKey key) => _entries.containsKey(key);

  /// Stores [image] at [key], replacing (and disposing) an older tile, then
  /// evicts the least recently used tiles over the bound. [keep] names keys
  /// never evicted now (the visible tiles).
  void put(TileKey key, ui.Image image, {Set<TileKey> keep = const {}}) {
    final old = _entries.remove(key);
    if (old != null) {
      _bytes -= old.bytes;
      old.image.dispose();
    }
    final entry = TileEntry(image, image.width * image.height * 4);
    _entries[key] = entry;
    _bytes += entry.bytes;
    _evict(keep);
  }

  void _evict(Set<TileKey> keep) {
    if (_bytes <= maxBytes) return;
    final victims = <TileKey>[];
    var bytes = _bytes;
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (bytes <= maxBytes) break;
      if (keep.contains(key)) continue;
      victims.add(key);
      bytes -= value.bytes;
    }
    for (final key in victims) {
      final entry = _entries.remove(key)!;
      _bytes -= entry.bytes;
      entry.image.dispose();
    }
  }

  /// Marks every tile of [part] (any zoom) that intersects the twip
  /// rectangle stale; [rect] `null` marks all of them (`EMPTY`). Returns the
  /// keys marked. [tileTwips] gives a zoom's tile size in twips.
  Set<TileKey> invalidate(
    int? part,
    ({int x, int y, int w, int h})? rect,
    double Function(int zoom) tileTwips,
  ) {
    final marked = <TileKey>{};
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (part != null && key.part != part) continue;
      if (rect != null) {
        final size = tileTwips(key.zoom);
        final left = key.column * size;
        final top = key.row * size;
        if (left >= rect.x + rect.w ||
            left + size <= rect.x ||
            top >= rect.y + rect.h ||
            top + size <= rect.y) {
          continue;
        }
      }
      value.stale = true;
      marked.add(key);
    }
    return marked;
  }

  /// Drops every tile of another zoom than [zoom] (once the new zoom's tiles
  /// have arrived).
  void dropOtherZooms(int zoom) {
    // A negative zoom is a whole-part thumbnail, kept across zoom changes.
    final victims = _entries.keys
        .where((k) => k.zoom != zoom && k.zoom >= 0)
        .toList();
    for (final key in victims) {
      final entry = _entries.remove(key)!;
      _bytes -= entry.bytes;
      entry.image.dispose();
    }
  }

  /// Every cached key (for tests and the zoom fallback).
  Iterable<TileKey> get keys => _entries.keys;

  /// Drops everything.
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }
}
