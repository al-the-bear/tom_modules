// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tom_office_editor/tom_office_editor.dart';

/// The payloads as LibreOffice 26.8.3.1 sent them (captured from the
/// helper on report.docx and sheet.xlsx).
void main() {
  test('OE-CB-1: rectangles, selections, the cell cursor, the size', () {
    expect(
      parseOfficeRect('11085, 1724, 0, 276'),
      const OfficeTwipRect(11085, 1724, 0, 276),
    );
    expect(parseOfficeRect('EMPTY'), isNull);
    expect(parseOfficeRects(''), isEmpty);
    expect(parseOfficeRects('10845, 1724, 239, 275; 0, 2000, 500, 275'), [
      const OfficeTwipRect(10845, 1724, 239, 275),
      const OfficeTwipRect(0, 2000, 500, 275),
    ]);
    final cell = parseCellCursor('0, 1425, 2547, 284, 0, 5')!;
    expect(
      (cell.rect, cell.column, cell.row),
      (const OfficeTwipRect(0, 1425, 2547, 284), 0, 5),
    );
    expect(parseCellCursor('EMPTY'), isNull);
    expect(parseDocumentSize('12808, 870980'), (width: 12808, height: 870980));
  });

  test('OE-CB-2: INVALIDATE_TILES with and without a part', () {
    final all = parseTileInvalidation('EMPTY');
    expect((all.rect, all.part), (null, null));
    final part = parseTileInvalidation('EMPTY, 2, 0');
    expect(part.part, 2);
    final rect = parseTileInvalidation('0, 0, 12240, 3000, 1, 0');
    expect(
      (rect.rect, rect.part),
      (const OfficeTwipRect(0, 0, 12240, 3000), 1),
    );
  });

  test('OE-CB-3: STATE_CHANGED, the context menu, links, results', () {
    expect(parseStateChanged('.uno:ModifiedStatus=true'), (
      command: '.uno:ModifiedStatus',
      value: 'true',
    ));
    expect(
      parseStateChanged(
        '.uno:StateWordCount=12,675 words, 81,831 characters',
      )?.value,
      '12,675 words, 81,831 characters',
    );
    expect(
      parseStateChanged('{ "commandName": "TableAutoFillInfo", "state": {}}'),
      isNull,
    );
    final menu = parseContextMenu('''
{ "menu": [
  { "text": "~Cut", "type": "command", "command": ".uno:Cut", "enabled": "true" },
  { "type": "separator" },
  { "text": "Para~graph", "type": "menu", "menu": [
    { "text": "~Left", "type": "command", "command": ".uno:LeftPara", "enabled": "false" }
  ]}
]}''');
    expect(menu.map((e) => (e.kind, e.text)), [
      ('command', 'Cut'),
      ('separator', ''),
      ('menu', 'Paragraph'),
    ]);
    expect(menu.last.children.single.enabled, isFalse);
    expect(parseContextMenu('not json'), isEmpty);
    expect(parseHyperlink('https://example.org/'), 'https://example.org/');
    expect(parseHyperlink('{"url": "https://a.b/"}'), 'https://a.b/');
    expect(
      parseUnoCommandResult(
        '{ "commandName": ".uno:FormatCellDialog", "success": false }',
      ),
      (command: '.uno:FormatCellDialog', success: false),
    );
  });

  test('OE-CB-4: the sheet headers become twips', () {
    final h = TomOfficeSheetHeaders.parse(
      '{ "commandName": ".uno:ViewRowColumnHeaders", "rows": [ { "text": 0, '
      '"size": 0}, { "text": "1", "size": 19}, { "text": "2", "size": 38}], '
      '"columns": [ { "text": 0, "size": 0}, { "text": "A", "size": 165}]}',
      zoom: 100,
    )!;
    expect(h.rows.map((r) => (r.text, r.endTwips)), [
      ('1', 285.0),
      ('2', 570.0),
    ]);
    expect(h.columns.single.endTwips, closeTo(2547, 1));
    expect(TomOfficeSheetHeaders.parse('{ }', zoom: 100), isNull);
  });

  test('OE-KEY-1: keys map to VCL codes; the shell keeps its own', () {
    OfficeKeyMeaning m(
      LogicalKeyboardKey k, {
      bool shift = false,
      bool meta = false,
    }) => officeKeyMeaning(
      k,
      shift: shift,
      meta: meta,
      alt: false,
      control: false,
    );
    expect(
      (m(LogicalKeyboardKey.arrowDown, shift: true) as OfficeVclKey).keyCode,
      VclKey.down | VclKey.shift,
    );
    expect(
      (m(LogicalKeyboardKey.keyB, meta: true) as OfficeVclKey).keyCode,
      (VclKey.a + 1) | VclKey.mod1,
    );
    expect(m(LogicalKeyboardKey.keyS, meta: true), isA<OfficeKeyIgnored>());
    expect(m(LogicalKeyboardKey.keyZ, meta: true), isA<OfficeKeyIgnored>());
    expect(m(LogicalKeyboardKey.keyA), isA<OfficeKeyIgnored>());
    expect(
      (m(LogicalKeyboardKey.keyV, meta: true) as OfficeClipboardCommand).key,
      OfficeClipboardKey.paste,
    );
  });

  testWidgets('OE-TILE-1: the cache evicts, invalidates and changes zoom', (
    tester,
  ) async {
    final images = await tester.runAsync(() async {
      final list = <ui.Image>[];
      for (var i = 0; i < 4; i++) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawRect(const ui.Rect.fromLTWH(0, 0, 16, 16), ui.Paint());
        list.add(await recorder.endRecording().toImage(16, 16));
      }
      return list;
    });
    // Room for three 16 × 16 tiles.
    final cache = TileCache(maxBytes: 3 * 16 * 16 * 4);
    double twips(int zoom) => 3840 * 100 / zoom;
    cache.put(const TileKey(0, 100, 0, 0), images![0]);
    cache.put(const TileKey(0, 100, 1, 0), images[1]);
    cache.put(const TileKey(0, 100, 0, 1), images[2]);
    cache.get(const TileKey(0, 100, 0, 0)); // used: not the oldest any more
    cache.put(const TileKey(0, 200, 0, 0), images[3]);
    expect(cache.contains(const TileKey(0, 100, 1, 0)), isFalse, reason: 'LRU');
    expect(cache.length, 3);
    final marked = cache.invalidate(0, (x: 0, y: 0, w: 100, h: 100), twips);
    expect(marked, {const TileKey(0, 100, 0, 0), const TileKey(0, 200, 0, 0)});
    cache.dropOtherZooms(200);
    expect(cache.keys, [const TileKey(0, 200, 0, 0)]);
    cache.clear();
  });

  testWidgets('OE-TILE-3: replaced and evicted tiles are disposed; visible '
      'ones are kept over the bound', (tester) async {
    final images = await tester.runAsync(() async {
      final list = <ui.Image>[];
      for (var i = 0; i < 5; i++) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawRect(const ui.Rect.fromLTWH(0, 0, 16, 16), ui.Paint());
        list.add(await recorder.endRecording().toImage(16, 16));
      }
      return list;
    });
    // Room for two 16 × 16 tiles.
    final cache = TileCache(maxBytes: 2 * 16 * 16 * 4);
    const a = TileKey(0, 100, 0, 0), b = TileKey(0, 100, 1, 0);
    const c = TileKey(0, 100, 2, 0);
    cache.put(a, images![0]);
    // A repaint of the same tile replaces it and disposes the old image.
    cache.put(a, images[1]);
    expect(images[0].debugDisposed, isTrue);
    expect(cache.length, 1);
    cache.put(b, images[2]);
    // Over the bound: the least recently used tile goes, unless it is kept.
    cache.put(c, images[3], keep: {a, b, c});
    expect(cache.length, 3, reason: 'visible tiles stay over the bound');
    expect(images[1].debugDisposed, isFalse);
    cache.put(const TileKey(0, 100, 3, 0), images[4], keep: {c});
    expect(cache.contains(a), isFalse);
    expect(cache.contains(b), isFalse);
    expect(images[1].debugDisposed, isTrue);
    expect(images[2].debugDisposed, isTrue);
    expect(cache.bytes, 2 * 16 * 16 * 4);
    cache.clear();
    expect(images[3].debugDisposed && images[4].debugDisposed, isTrue);
  });
}
