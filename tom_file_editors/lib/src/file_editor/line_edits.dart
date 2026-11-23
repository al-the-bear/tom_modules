/// The line edits of a source editor as functions of the text and the
/// selection: delete, duplicate and move the caret's line, and comment it
/// out or in. Each answers the new text with the caret where the edit leaves
/// it, or null when there is nothing to do (the caret outside the text, the
/// first line moved up, the last one down).
///
/// [TomTextSourceState] applies them to what it shows; an application binds
/// them to its own keys and menus (Tom Forge's YAML editor does, through its
/// action integration).
library;

import 'package:flutter/services.dart';

/// The line edits of a source editor.
abstract final class TomLineEdits {
  /// The start and end (without the line break) of the line holding
  /// [offset].
  static ({int start, int end}) lineRange(String text, int offset) {
    final clamped = offset.clamp(0, text.length);
    var start = clamped;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    var end = clamped;
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    return (start: start, end: end);
  }

  static int? _caret(TextEditingValue value) {
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    return cursor;
  }

  /// The caret's line removed, with its line break; the caret at the start
  /// of where it was.
  static TextEditingValue? deleteLine(TextEditingValue value) {
    final cursor = _caret(value);
    if (cursor == null) return null;
    final text = value.text;
    final range = lineRange(text, cursor);
    var deleteStart = range.start;
    var deleteEnd = range.end;
    if (deleteEnd < text.length && text[deleteEnd] == '\n') {
      deleteEnd++;
    } else if (deleteStart > 0 && text[deleteStart - 1] == '\n') {
      deleteStart--;
    }
    final result = text.substring(0, deleteStart) + text.substring(deleteEnd);
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(
        offset: deleteStart.clamp(0, result.length),
      ),
    );
  }

  /// The caret's line repeated below it; the caret on the copy, in the same
  /// column.
  static TextEditingValue? duplicateLine(TextEditingValue value) {
    final cursor = _caret(value);
    if (cursor == null) return null;
    final text = value.text;
    final range = lineRange(text, cursor);
    final line = text.substring(range.start, range.end);
    final column = cursor - range.start;
    final result =
        '${text.substring(0, range.end)}\n$line${text.substring(range.end)}';
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(
        offset: (range.end + 1 + column).clamp(0, result.length),
      ),
    );
  }

  /// The caret's line swapped with the one above; the caret moves with it.
  static TextEditingValue? moveLineUp(TextEditingValue value) {
    final cursor = _caret(value);
    if (cursor == null) return null;
    final text = value.text;
    final current = lineRange(text, cursor);
    if (current.start == 0) return null;
    final previous = lineRange(text, current.start - 1);
    final currentLine = text.substring(current.start, current.end);
    final previousLine = text.substring(previous.start, previous.end);
    final column = cursor - current.start;
    final result =
        '${text.substring(0, previous.start)}$currentLine\n$previousLine'
        '${text.substring(current.end)}';
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(
        offset: (previous.start + column).clamp(0, result.length),
      ),
    );
  }

  /// The caret's line swapped with the one below; the caret moves with it.
  static TextEditingValue? moveLineDown(TextEditingValue value) {
    final cursor = _caret(value);
    if (cursor == null) return null;
    final text = value.text;
    final current = lineRange(text, cursor);
    if (current.end >= text.length) return null;
    final next = lineRange(text, current.end + 1);
    final currentLine = text.substring(current.start, current.end);
    final nextLine = text.substring(next.start, next.end);
    final column = cursor - current.start;
    final result =
        '${text.substring(0, current.start)}$nextLine\n$currentLine'
        '${text.substring(next.end)}';
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(
        offset: (current.start + nextLine.length + 1 + column).clamp(
          0,
          result.length,
        ),
      ),
    );
  }

  /// The caret's line commented out with [prefix] after its indentation, or
  /// back in when it starts with [prefix] (or [prefix] without its trailing
  /// space); the caret keeps its place in the text.
  static TextEditingValue? toggleLineComment(
    TextEditingValue value, {
    String prefix = '# ',
  }) {
    final cursor = _caret(value);
    if (cursor == null) return null;
    final text = value.text;
    final range = lineRange(text, cursor);
    final line = text.substring(range.start, range.end);
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;
    final String newLine;
    if (trimmed.startsWith(prefix)) {
      newLine = line.substring(0, indent) + trimmed.substring(prefix.length);
    } else if (prefix.endsWith(' ') && trimmed.startsWith(prefix.trimRight())) {
      newLine =
          line.substring(0, indent) +
          trimmed.substring(prefix.trimRight().length);
    } else {
      newLine = '${line.substring(0, indent)}$prefix$trimmed';
    }
    final result =
        text.substring(0, range.start) + newLine + text.substring(range.end);
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(
        offset: (cursor + newLine.length - line.length).clamp(0, result.length),
      ),
    );
  }
}
