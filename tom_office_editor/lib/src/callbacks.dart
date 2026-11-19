// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The payloads of LibreOfficeKit's callbacks as LibreOffice 26.8.3.1 sends
/// them (`OfficeCallback.payload`), parsed. Pure Dart.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A rectangle in document twips (1440 per inch).
@immutable
final class OfficeTwipRect {
  /// A rectangle from its parts.
  const OfficeTwipRect(this.x, this.y, this.w, this.h);

  /// Left edge.
  final int x;

  /// Top edge.
  final int y;

  /// Width.
  final int w;

  /// Height.
  final int h;

  @override
  bool operator ==(Object other) =>
      other is OfficeTwipRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => '($x, $y, $w × $h)';
}

/// The numbers of a `x, y, w, h[, …]` payload, or `null` for `EMPTY`, an
/// empty payload or one that is not numbers.
List<int>? _numbers(String payload) {
  final text = payload.trim();
  if (text.isEmpty || text == 'EMPTY') return null;
  final parts = text.split(',');
  final values = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null) return null;
    values.add(v);
  }
  return values;
}

/// `INVALIDATE_VISIBLE_CURSOR`, `TEXT_SELECTION_START` / `_END`,
/// `CELL_AUTO_FILL_AREA`: one rectangle `x, y, w, h`. `null` for `EMPTY`.
OfficeTwipRect? parseOfficeRect(String payload) {
  final v = _numbers(payload);
  if (v == null || v.length < 4) return null;
  return OfficeTwipRect(v[0], v[1], v[2], v[3]);
}

/// `TEXT_SELECTION`: rectangles separated by `;`; empty when nothing is
/// selected.
List<OfficeTwipRect> parseOfficeRects(String payload) => [
  for (final part in payload.split(';')) ?parseOfficeRect(part),
];

/// What `INVALIDATE_TILES` asks to repaint.
@immutable
final class OfficeTileInvalidation {
  /// An invalidation from its parts.
  const OfficeTileInvalidation({this.rect, this.part});

  /// The area, or `null` for everything (`EMPTY`).
  final OfficeTwipRect? rect;

  /// The part, or `null` when the payload names none (every part).
  final int? part;
}

/// `INVALIDATE_TILES`: `EMPTY` (everything), `EMPTY, <part>[, <mode>]`, or
/// `x, y, w, h[, part, mode]`.
OfficeTileInvalidation parseTileInvalidation(String payload) {
  final text = payload.trim();
  if (text.startsWith('EMPTY')) {
    final rest = text.substring(5).split(',').map((p) => p.trim());
    final part = rest.where((p) => p.isNotEmpty).map(int.tryParse).firstOrNull;
    return OfficeTileInvalidation(part: part);
  }
  final v = _numbers(text);
  if (v == null || v.length < 4) return const OfficeTileInvalidation();
  return OfficeTileInvalidation(
    rect: OfficeTwipRect(v[0], v[1], v[2], v[3]),
    part: v.length > 4 ? v[4] : null,
  );
}

/// `CELL_CURSOR`: `x, y, w, h, column, row`, or `EMPTY`.
@immutable
final class OfficeCellCursor {
  /// A cell cursor from its parts.
  const OfficeCellCursor(this.rect, this.column, this.row);

  /// The cell's rectangle.
  final OfficeTwipRect rect;

  /// Its column (0 = A).
  final int column;

  /// Its row (0 = 1).
  final int row;
}

/// Parses `CELL_CURSOR`; `null` for `EMPTY`.
OfficeCellCursor? parseCellCursor(String payload) {
  final v = _numbers(payload);
  if (v == null || v.length < 4) return null;
  return OfficeCellCursor(
    OfficeTwipRect(v[0], v[1], v[2], v[3]),
    v.length > 4 ? v[4] : 0,
    v.length > 5 ? v[5] : 0,
  );
}

/// `DOCUMENT_SIZE_CHANGED`: `width, height` in twips.
({int width, int height})? parseDocumentSize(String payload) {
  final v = _numbers(payload);
  if (v == null || v.length < 2) return null;
  return (width: v[0], height: v[1]);
}

/// `STATE_CHANGED` in its plain form `.uno:<Command>=<value>`: the command
/// with its `.uno:` prefix and the value. `null` for the JSON form
/// (`{ "commandName": …, "state": … }`), which the core editor does not use.
({String command, String value})? parseStateChanged(String payload) {
  if (!payload.startsWith('.uno:')) return null;
  final eq = payload.indexOf('=');
  if (eq < 0) return (command: payload, value: '');
  return (command: payload.substring(0, eq), value: payload.substring(eq + 1));
}

/// One entry of LibreOffice's context menu (`CONTEXT_MENU`).
@immutable
final class OfficeContextMenuEntry {
  /// An entry from its parts.
  const OfficeContextMenuEntry({
    required this.kind,
    this.text = '',
    this.command,
    this.enabled = true,
    this.checked = false,
    this.children = const [],
  });

  /// `command`, `separator` or `menu` (a submenu).
  final String kind;

  /// The label without LibreOffice's `~` mnemonic marks.
  final String text;

  /// The UNO command of a `command` entry, e.g. `.uno:Cut`.
  final String? command;

  /// Whether it can be chosen.
  final bool enabled;

  /// Whether it shows a check mark (`checktype` with `checked`).
  final bool checked;

  /// A submenu's entries.
  final List<OfficeContextMenuEntry> children;

  /// Whether it is a separator.
  bool get isSeparator => kind == 'separator';
}

/// Parses `CONTEXT_MENU` (`{"menu": [...]}`); empty when it cannot be read.
List<OfficeContextMenuEntry> parseContextMenu(String payload) {
  try {
    final json = jsonDecode(payload);
    if (json is! Map || json['menu'] is! List) return const [];
    return _entries(json['menu'] as List);
  } on FormatException {
    return const [];
  }
}

List<OfficeContextMenuEntry> _entries(List<Object?> list) => [
  for (final item in list)
    if (item is Map)
      OfficeContextMenuEntry(
        kind: '${item['type'] ?? 'command'}',
        text: '${item['text'] ?? ''}'.replaceAll('~', ''),
        command: item['command'] as String?,
        enabled: '${item['enabled'] ?? 'true'}' == 'true',
        checked: '${item['checked'] ?? 'false'}' == 'true',
        children: item['menu'] is List
            ? _entries(item['menu'] as List)
            : const [],
      ),
];

/// `HYPERLINK_CLICKED`: a URL, or JSON `{"url": …}` in newer builds.
String parseHyperlink(String payload) {
  final text = payload.trim();
  if (text.startsWith('{')) {
    try {
      final json = jsonDecode(text);
      if (json is Map && json['url'] is String) return json['url'] as String;
    } on FormatException {
      return text;
    }
  }
  return text;
}

/// `UNO_COMMAND_RESULT`: the command and whether it succeeded.
({String command, bool success})? parseUnoCommandResult(String payload) {
  try {
    final json = jsonDecode(payload);
    if (json is! Map) return null;
    return (
      command: '${json['commandName'] ?? ''}',
      success: json['success'] == true,
    );
  } on FormatException {
    return null;
  }
}
