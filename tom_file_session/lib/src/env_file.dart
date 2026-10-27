/// A `.env` file read line by line, and every change made as a
/// splice into the one line it changes.
///
/// Quoting, `export` prefixes, inline comments, spacing, blank lines and
/// line endings are kept because nothing outside the edited token is
/// rewritten. Nothing here logs, and no message carries a value: an
/// unreadable line is named by its number.
library;

import 'package:meta/meta.dart';

/// What a line of a `.env` file is.
enum ForgeEnvLineKind {
  /// `KEY=value`, possibly `export KEY=value`.
  entry,

  /// `# KEY=value` — an entry switched off.
  commented,

  /// A comment that is not shaped like an entry: shown as a heading.
  section,

  blank,

  /// Not readable as any of the above.
  unreadable,
}

/// One line of a `.env` file.
class ForgeEnvLine {
  const ForgeEnvLine({
    required this.index,
    required this.kind,
    required this.start,
    required this.end,
    this.key = '',
    this.value = '',
    this.keyStart = 0,
    this.keyEnd = 0,
    this.valueStart = 0,
    this.valueEnd = 0,
    this.quote = '',
    this.hashStart = 0,
    this.hashEnd = 0,
    this.comment = '',
  });

  /// 0-based line number.
  final int index;
  final ForgeEnvLineKind kind;

  /// The line's extent in the text, line ending excluded.
  final int start;
  final int end;

  final String key;

  /// The value as the program reads it: quotes removed, escapes decoded.
  final String value;

  final int keyStart;
  final int keyEnd;

  /// The value token's extent — quotes included.
  final int valueStart;
  final int valueEnd;

  /// The quote the value was written in: `"`, `'` or nothing.
  final String quote;

  /// For a commented-out entry, the `#` and the one space after it.
  final int hashStart;
  final int hashEnd;

  /// For a section comment, its text without the `#`; for an entry, its
  /// inline comment (` # …` after the value) without the `#`, or `''`.
  final String comment;

  bool get isEntry =>
      kind == ForgeEnvLineKind.entry || kind == ForgeEnvLineKind.commented;
}

final RegExp _entry = RegExp(
  r'^(\s*)(export\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\s*=',
);
final RegExp _commented = RegExp(
  r'^(\s*)(#\s?)(\s*)(export\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\s*=',
);
final RegExp _key = RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$');

/// Whether [key] can be a `.env` key.
bool forgeIsEnvKey(String key) => _key.hasMatch(key);

/// A parsed `.env` file over its text.
class ForgeEnvFile {
  ForgeEnvFile._(this.text, this.lines, this.newline);

  final String text;
  final List<ForgeEnvLine> lines;
  final String newline;

  /// The entries, active and commented-out, in file order.
  Iterable<ForgeEnvLine> get entries => lines.where((l) => l.isEntry);

  /// The 1-based numbers of the lines that could not be read.
  List<int> get unreadableLines => [
    for (final l in lines)
      if (l.kind == ForgeEnvLineKind.unreadable) l.index + 1,
  ];

  static ForgeEnvFile parse(String text) {
    final crlf = '\r\n'.allMatches(text).length;
    final lf = '\n'.allMatches(text).length;
    final newline = crlf * 2 > lf ? '\r\n' : '\n';
    final lines = <ForgeEnvLine>[];
    var offset = 0;
    var index = 0;
    while (offset <= text.length) {
      var lineEnd = text.indexOf('\n', offset);
      final hasBreak = lineEnd != -1;
      if (!hasBreak) lineEnd = text.length;
      var contentEnd = lineEnd;
      if (contentEnd > offset && text[contentEnd - 1] == '\r') contentEnd--;
      if (!hasBreak && offset == text.length && index > 0) break;
      lines.add(_line(text, index, offset, contentEnd));
      index++;
      if (!hasBreak) break;
      offset = lineEnd + 1;
    }
    return ForgeEnvFile._(text, lines, newline);
  }

  static ForgeEnvLine _line(String text, int index, int start, int end) {
    final line = text.substring(start, end);
    if (line.trim().isEmpty) {
      return ForgeEnvLine(
        index: index,
        kind: ForgeEnvLineKind.blank,
        start: start,
        end: end,
      );
    }
    final commented = _commented.firstMatch(line);
    if (commented != null) {
      final hashStart = start + commented.group(1)!.length;
      return _withValue(
        text,
        index: index,
        kind: ForgeEnvLineKind.commented,
        start: start,
        end: end,
        keyStart:
            start +
            commented.group(1)!.length +
            commented.group(2)!.length +
            commented.group(3)!.length +
            (commented.group(4) ?? '').length,
        key: commented.group(5)!,
        afterEquals: start + commented.end,
        hashStart: hashStart,
        hashEnd: hashStart + commented.group(2)!.length,
      );
    }
    if (line.trimLeft().startsWith('#')) {
      return ForgeEnvLine(
        index: index,
        kind: ForgeEnvLineKind.section,
        start: start,
        end: end,
        comment: line.trimLeft().substring(1).trim(),
      );
    }
    final entry = _entry.firstMatch(line);
    if (entry != null) {
      return _withValue(
        text,
        index: index,
        kind: ForgeEnvLineKind.entry,
        start: start,
        end: end,
        keyStart:
            start + entry.group(1)!.length + (entry.group(2) ?? '').length,
        key: entry.group(3)!,
        afterEquals: start + entry.end,
      );
    }
    return ForgeEnvLine(
      index: index,
      kind: ForgeEnvLineKind.unreadable,
      start: start,
      end: end,
    );
  }

  static ForgeEnvLine _withValue(
    String text, {
    required int index,
    required ForgeEnvLineKind kind,
    required int start,
    required int end,
    required int keyStart,
    required String key,
    required int afterEquals,
    int hashStart = 0,
    int hashEnd = 0,
  }) {
    var i = afterEquals;
    while (i < end && (text[i] == ' ' || text[i] == '\t')) {
      i++;
    }
    final valueStart = i;
    var quote = '';
    var valueEnd = end;
    String value;
    if (i < end && (text[i] == '"' || text[i] == "'")) {
      quote = text[i];
      var j = i + 1;
      final out = StringBuffer();
      var closed = false;
      while (j < end) {
        final c = text[j];
        if (quote == '"' && c == r'\' && j + 1 < end) {
          final n = text[j + 1];
          out.write(switch (n) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            _ => n,
          });
          j += 2;
          continue;
        }
        if (c == quote) {
          closed = true;
          j++;
          break;
        }
        out.write(c);
        j++;
      }
      valueEnd = closed ? j : end;
      value = out.toString();
    } else {
      // An unquoted value runs to an inline comment (` #`) or the end.
      var j = i;
      while (j < end && !(text[j] == '#' && j > i && text[j - 1] == ' ')) {
        j++;
      }
      var k = j;
      while (k > i && (text[k - 1] == ' ' || text[k - 1] == '\t')) {
        k--;
      }
      valueEnd = k;
      value = text.substring(i, k);
    }
    final rest = text.substring(valueEnd, end).trimLeft();
    final comment = rest.startsWith('#') ? rest.substring(1).trim() : '';
    return ForgeEnvLine(
      index: index,
      kind: kind,
      start: start,
      end: end,
      key: key,
      value: value,
      keyStart: keyStart,
      keyEnd: keyStart + key.length,
      valueStart: valueStart,
      valueEnd: valueEnd,
      quote: quote,
      hashStart: hashStart,
      hashEnd: hashEnd,
      comment: comment,
    );
  }

  // ── Edits. Each returns the new text. ────────────────────────────────────

  /// [value] written the way the line wrote its value: in its own quotes, or
  /// plain when it needs none, else in double quotes.
  @visibleForTesting
  static String encodeValue(String value, String quote) {
    final needsQuotes =
        value.isNotEmpty &&
        (value.contains(' ') ||
            value.contains('\t') ||
            value.contains('#') ||
            value.contains('"') ||
            value.contains("'") ||
            value.contains('\n') ||
            value.contains(r'\'));
    if (quote == "'" && !value.contains("'") && !value.contains('\n')) {
      return "'$value'";
    }
    if (quote.isEmpty && !needsQuotes) return value;
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  /// The text with line [index]'s value set to [value].
  String withValue(int index, String value) {
    final line = lines[index];
    return text.replaceRange(
      line.valueStart,
      line.valueEnd,
      encodeValue(value, line.quote),
    );
  }

  /// The text with line [index]'s key renamed to [key].
  String withKey(int index, String key) {
    if (!forgeIsEnvKey(key)) {
      throw ArgumentError(
        'Not a key: letters, digits, _ . -, not first a digit',
      );
    }
    final line = lines[index];
    return text.replaceRange(line.keyStart, line.keyEnd, key);
  }

  /// The text with line [index] switched between active and commented-out.
  String withToggled(int index) {
    final line = lines[index];
    return switch (line.kind) {
      ForgeEnvLineKind.commented => text.replaceRange(
        line.hashStart,
        line.hashEnd,
        '',
      ),
      ForgeEnvLineKind.entry => text.replaceRange(
        line.keyStart - _prefixAfterIndent(line),
        line.keyStart - _prefixAfterIndent(line),
        '# ',
      ),
      _ => text,
    };
  }

  /// The length of `export ` before the key, which the `#` goes in front of.
  int _prefixAfterIndent(ForgeEnvLine line) {
    final lineText = text.substring(line.start, line.keyStart);
    return lineText.length - lineText.trimLeft().length == lineText.length
        ? 0
        : lineText.trimLeft().length;
  }

  /// The text without line [index] (and its line break).
  String withoutLine(int index) {
    final line = lines[index];
    var end = line.end;
    if (end < text.length && text[end] == '\r') end++;
    if (end < text.length && text[end] == '\n') end++;
    var start = line.start;
    if (end == line.end && start > 0) {
      // The last line has no break of its own: take the one before it.
      start = text.lastIndexOf('\n', start - 1);
      if (start > 0 && text[start - 1] == '\r') start--;
    }
    return text.replaceRange(start, end, '');
  }

  /// The text with `key=value` added at the end.
  String withAdded(String key, String value) {
    if (!forgeIsEnvKey(key)) {
      throw ArgumentError(
        'Not a key: letters, digits, _ . -, not first a digit',
      );
    }
    final entry = '$key=${encodeValue(value, '')}';
    if (text.isEmpty) return '$entry$newline';
    final endsWithBreak = text.endsWith('\n');
    return endsWithBreak ? '$text$entry$newline' : '$text$newline$entry';
  }

  /// The text with every value replaced by `•••` — the raw view while values
  /// are hidden.
  String masked() {
    final out = StringBuffer();
    var at = 0;
    for (final line in lines) {
      if (!line.isEntry) continue;
      out.write(text.substring(at, line.valueStart));
      out.write(line.valueEnd > line.valueStart ? '•••' : '');
      at = line.valueEnd;
    }
    out.write(text.substring(at));
    return out.toString();
  }
}
