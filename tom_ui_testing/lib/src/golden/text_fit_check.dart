/// Whether a label is drawn whole: not cut, and on no more lines than it may
/// take.
///
/// Measured here rather than in a package's unit tests because the unit tests
/// draw with the box test font, whose every glyph is a square one font size
/// wide, so a label's width there says nothing about its width on screen. The
/// golden harness loads the real fonts.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every paragraph under [finder] is drawn whole on at most [maxLines] lines.
void expectTomTextWhole(WidgetTester tester, Finder finder, {int maxLines = 1}) {
  final paragraphs = tester
      .renderObjectList<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      )
      .toList();
  expect(paragraphs, isNotEmpty, reason: '$finder draws no text');
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" is cut');
    // A paragraph that does not wrap may still be wider than its box and be
    // clipped rather than ellipsized.
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason: '"$text" is wider than the room it has',
    );
    final lines = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        )
        .map((box) => box.top.round())
        .toSet()
        .length;
    expect(lines, lessThanOrEqualTo(maxLines),
        reason: '"$text" is drawn on $lines lines');
  }
}
