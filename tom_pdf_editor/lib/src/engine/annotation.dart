// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/foundation.dart';

import 'engine.dart';

/// The annotation kinds the editor creates and edits; every other subtype is
/// [other]: shown as rendered, not editable, kept on save.
enum PdfAnnotationKind {
  /// `/Highlight` over text, with quad points.
  highlight,

  /// `/Text`: a note icon with `Contents`.
  note,

  /// `/Ink`: one stroke per drag.
  ink,

  /// Any other subtype (stamps, free text, shapes, links, …).
  other,
}

/// A point in view points.
typedef PdfPoint = ({double x, double y});

/// One annotation of a page, as the editor models it (for hit-testing and
/// undo). Geometry is in view points.
@immutable
final class PdfAnnotation {
  const PdfAnnotation({
    required this.id,
    required this.kind,
    required this.rect,
    this.subtype = 0,
    this.color = 0xFFFFEB3B,
    this.quads = const [],
    this.strokes = const [],
    this.width = 2,
    this.contents = '',
    this.author = '',
    this.modified = '',
  });

  /// `NM` (the unique name), or `#<index>` for an annotation of the file
  /// that has none (it gets one the first time it is edited).
  final String id;

  /// The kind.
  final PdfAnnotationKind kind;

  /// The PDF subtype number (`FPDF_ANNOT_*`).
  final int subtype;

  /// The annotation's rectangle.
  final PdfRect rect;

  /// Its colour, ARGB.
  final int color;

  /// A highlight's areas (one per line), from its quad points.
  final List<PdfRect> quads;

  /// An ink annotation's strokes.
  final List<List<PdfPoint>> strokes;

  /// An ink stroke's width in points.
  final double width;

  /// `Contents`: a note's text.
  final String contents;

  /// `T`: the author.
  final String author;

  /// `M`: the modification date, in PDF date form (`D:YYYYMMDDHHmmSS+HH'mm'`).
  final String modified;

  /// Whether the editor can select, move, recolour and delete it.
  bool get editable => kind != PdfAnnotationKind.other;

  /// Whether the file gives it no `NM` yet.
  bool get unnamed => id.startsWith('#');

  /// A copy with the given fields replaced.
  PdfAnnotation copyWith({
    String? id,
    PdfRect? rect,
    int? color,
    List<PdfRect>? quads,
    List<List<PdfPoint>>? strokes,
    String? contents,
    String? author,
    String? modified,
  }) => PdfAnnotation(
    id: id ?? this.id,
    kind: kind,
    subtype: subtype,
    rect: rect ?? this.rect,
    color: color ?? this.color,
    quads: quads ?? this.quads,
    strokes: strokes ?? this.strokes,
    width: width,
    contents: contents ?? this.contents,
    author: author ?? this.author,
    modified: modified ?? this.modified,
  );

  /// The annotation moved by ([dx], [dy]) points: its rectangle, quads and
  /// strokes alike.
  PdfAnnotation moved(double dx, double dy) => copyWith(
    rect: _shift(rect, dx, dy),
    quads: [for (final q in quads) _shift(q, dx, dy)],
    strokes: [
      for (final s in strokes) [for (final p in s) (x: p.x + dx, y: p.y + dy)],
    ],
  );

  /// The annotation scaled into [target] (a resize): every point keeps its
  /// relative place in the rectangle.
  PdfAnnotation resized(PdfRect target) {
    final sx = rect.width == 0 ? 1.0 : target.width / rect.width;
    final sy = rect.height == 0 ? 1.0 : target.height / rect.height;
    double x(double v) => target.left + (v - rect.left) * sx;
    double y(double v) => target.top + (v - rect.top) * sy;
    return copyWith(
      rect: target,
      quads: [
        for (final q in quads)
          PdfRect(x(q.left), y(q.top), x(q.right), y(q.bottom)),
      ],
      strokes: [
        for (final s in strokes) [for (final p in s) (x: x(p.x), y: y(p.y))],
      ],
    );
  }

  static PdfRect _shift(PdfRect r, double dx, double dy) =>
      PdfRect(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy);

  /// The annotation as a list for the engine isolate.
  List<Object?> toWire() => [
    id,
    kind.index,
    subtype,
    [rect.left, rect.top, rect.right, rect.bottom],
    color,
    [
      for (final q in quads) ...[q.left, q.top, q.right, q.bottom],
    ],
    [
      for (final s in strokes)
        [
          for (final p in s) ...[p.x, p.y],
        ],
    ],
    width,
    contents,
    author,
    modified,
  ];

  /// The annotation from [toWire]'s list.
  static PdfAnnotation fromWire(List<Object?> w) {
    final r = (w[3] as List).cast<double>();
    final q = (w[5] as List).cast<double>();
    return PdfAnnotation(
      id: w[0] as String,
      kind: PdfAnnotationKind.values[w[1] as int],
      subtype: w[2] as int,
      rect: PdfRect(r[0], r[1], r[2], r[3]),
      color: w[4] as int,
      quads: [
        for (var i = 0; i + 3 < q.length; i += 4)
          PdfRect(q[i], q[i + 1], q[i + 2], q[i + 3]),
      ],
      strokes: [
        for (final s in (w[6] as List).cast<List>())
          [
            for (var i = 0; i + 1 < s.length; i += 2)
              (x: (s[i] as num).toDouble(), y: (s[i + 1] as num).toDouble()),
          ],
      ],
      width: (w[7] as num).toDouble(),
      contents: w[8] as String,
      author: w[9] as String,
      modified: w[10] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfAnnotation &&
      listEquals(
        other.toWire().map((e) => '$e').toList(),
        toWire().map((e) => '$e').toList(),
      );

  @override
  int get hashCode => Object.hashAll(toWire().map((e) => '$e'));

  @override
  String toString() => 'PdfAnnotation(${kind.name} $id $rect)';
}

/// The PDF date form of [t]: `D:YYYYMMDDHHmmSS+HH'mm'`.
String pdfDate(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final h = offset.inHours.abs();
  final m = offset.inMinutes.abs() % 60;
  return 'D:${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}'
      "${two(t.minute)}${two(t.second)}$sign${two(h)}'${two(m)}'";
}

/// Thins a stroke with the Douglas–Peucker algorithm: points closer than
/// [tolerance] points to the line between kept neighbours are dropped.
List<PdfPoint> thinStroke(List<PdfPoint> points, {double tolerance = 0.5}) {
  if (points.length < 3) return List.of(points);
  final keep = List<bool>.filled(points.length, false)
    ..[0] = true
    ..[points.length - 1] = true;
  void simplify(int first, int last) {
    if (last <= first + 1) return;
    final a = points[first];
    final b = points[last];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    var worst = -1.0;
    var index = first;
    for (var i = first + 1; i < last; i++) {
      final p = points[i];
      double d2;
      if (len2 == 0) {
        d2 = (p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y);
      } else {
        final cross = (p.x - a.x) * dy - (p.y - a.y) * dx;
        d2 = cross * cross / len2;
      }
      if (d2 > worst) {
        worst = d2;
        index = i;
      }
    }
    if (worst > tolerance * tolerance) {
      keep[index] = true;
      simplify(first, index);
      simplify(index, last);
    }
  }

  simplify(0, points.length - 1);
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}
