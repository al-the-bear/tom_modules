// A COPY of tom_basics' `lib/src/utilities/yaml_lines.dart` (tom_basics 3.3.0),
// held here so this package depends on no tom_basics.
//
// Why: inside the Tom workspace most packages take tom_basics by PATH while
// its shared packages are being extracted, and a published package that takes
// it from pub.dev cannot join such a dependency graph (pub refuses one package
// from two sources, and dependency overrides are not used). Without
// tom_basics, this model fits every graph, path or hosted.
//
// The copy is checked against the original: `test/yaml_lines_copy_test.dart`
// compares the two bodies whenever the workspace's tom_basics is next to this
// package, so a change to one cannot go unnoticed. Once tom_basics is taken
// from pub.dev throughout, this file goes and the package depends on
// tom_basics again.
//
// ---- tom_basics/lib/src/utilities/yaml_lines.dart below, unchanged ----
/// The few YAML shapes a todo file holds, written the way the workspace's own
/// tools write them — for the keys an edit changes, and nothing else.
///
/// Every value a todo carries is a string, a list of strings, a map of those,
/// or a list of such maps. Strings are where the care goes: the workspace's
/// validator reads YAML 1.1 (PyYAML), which turns an unquoted `2026-10-11`
/// into a date and an unquoted `yes` into a boolean, and the schema then
/// refuses a value nobody wrote. So a string is written plain only when no
/// YAML reader could take it for anything else.
library;

/// The newline a file uses: CRLF when most of its line breaks are CRLF.
String tomNewlineOf(String text) {
  final crlf = '\r\n'.allMatches(text).length;
  final lf = '\n'.allMatches(text).length;
  return crlf * 2 > lf ? '\r\n' : '\n';
}

final RegExp _numberLike = RegExp(
  r'^[-+]?(\.?[0-9]|0x|0o|\.inf|\.nan)',
  caseSensitive: false,
);

const Set<String> _reserved = {
  'true', 'false', 'yes', 'no', 'on', 'off', 'y', 'n', //
  'null', '~', '',
};

/// [value] as a one-line YAML scalar: plain when that reads back as the same
/// string in YAML 1.1 and 1.2, double-quoted otherwise.
String tomYamlScalar(String value) {
  final plain = value.isNotEmpty &&
      value.trim() == value &&
      !_reserved.contains(value.toLowerCase()) &&
      !_numberLike.hasMatch(value) &&
      !RegExp(r'''^[-?:,\[\]{}#&*!|>'"%@`]''').hasMatch(value) &&
      !value.contains(': ') &&
      !value.contains(' #') &&
      !value.endsWith(':') &&
      !value.codeUnits.any((c) => c < 0x20 || c == 0x7F);
  return plain ? value : _doubleQuoted(value);
}

String _doubleQuoted(String value) {
  final out = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (rune < 0x20 || rune == 0x7F) {
          out.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
        } else {
          out.writeCharCode(rune);
        }
    }
  }
  out.write('"');
  return out.toString();
}

/// Whether [value] can be a literal block: it has line breaks, and no line
/// would need an indentation indicator or trailing-space care.
bool _literalBlock(String value) {
  if (!value.contains('\n') || value.contains('\r')) return false;
  final lines = value.split('\n');
  if (lines.first.startsWith(' ') || lines.first.isEmpty) return false;
  return !lines.any((l) => l.endsWith(' ') || l.contains('\t'));
}

/// The text of `key: value`, at column [indent], ending in [nl].
///
/// [indent] is the key's own column; a nested collection is indented two
/// further, the shape the workspace's todo files already use.
String tomYamlEntry(String key, Object? value, int indent, String nl) {
  final pad = ' ' * indent;
  final out = StringBuffer('$key:');
  _value(out, value, indent, nl);
  return '$pad$out';
}

void _value(StringBuffer out, Object? value, int indent, String nl) {
  switch (value) {
    case null:
      out.write(' null$nl');
    case String() when _literalBlock(value):
      final chomp = value.endsWith('\n') ? '' : '-';
      final body = value.endsWith('\n')
          ? value.substring(0, value.length - 1)
          : value;
      out.write(' |$chomp$nl');
      for (final line in body.split('\n')) {
        out.write(line.isEmpty ? nl : '${' ' * (indent + 2)}$line$nl');
      }
    case String():
      out.write(' ${tomYamlScalar(value)}$nl');
    case List() when value.isEmpty:
      out.write(' []$nl');
    case List():
      out.write(nl);
      for (final item in value) {
        out.write(tomYamlListItem(item, indent + 2, nl));
      }
    case Map() when value.isEmpty:
      out.write(' {}$nl');
    case Map():
      out.write(nl);
      for (final e in value.entries) {
        out.write(tomYamlEntry('${e.key}', e.value, indent + 2, nl));
      }
    default:
      out.write(' ${tomYamlScalar('$value')}$nl');
  }
}

/// One `- item` of a block sequence whose dashes sit at column [indent].
///
/// A map item puts its first key on the dash line and the rest under it —
/// `- id: x` / `  title: y` — which is how every todo in the workspace is
/// written.
String tomYamlListItem(Object? item, int indent, String nl) {
  final pad = ' ' * indent;
  if (item is Map && item.isNotEmpty) {
    final out = StringBuffer();
    var first = true;
    for (final e in item.entries) {
      final entry = tomYamlEntry('${e.key}', e.value, indent + 2, nl);
      out.write(first ? '$pad- ${entry.substring(indent + 2)}' : entry);
      first = false;
    }
    return out.toString();
  }
  final out = StringBuffer('$pad-');
  _value(out, item, indent, nl);
  return out.toString();
}

final RegExp _schemaComment = RegExp(
  r'^#\s*yaml-language-server:\s*\$schema=(\S+)',
  multiLine: true,
);

/// The schema [text] names in a `# yaml-language-server: $schema=` comment,
/// or null when it names none. The reference is returned as written, to be
/// resolved against the file's own folder.
String? tomYamlSchemaRefOf(String text) =>
    _schemaComment.firstMatch(text)?.group(1);
