/// A `*.todo.yaml` file read into the shared todo model, and every change to
/// it made as a splice into the file's own text.
///
/// The file is never re-emitted. Each todo's YAML is located by the spans the
/// parser reports, and an edit rebuilds only the keys that changed, copying
/// every other key's text — its comments, its quoting, its block scalars —
/// verbatim. Every other todo, the header comments (an ACTIVE SET block, the
/// `yaml-language-server` line) and the line endings keep their bytes; a
/// structured edit is a text edit.
library;

import 'package:meta/meta.dart';
import 'package:tom_basics/utilities.dart';
import 'package:yaml/yaml.dart';

import 'todo.dart';

/// The file-level keys of the workspace schema, in the order a new one is
/// placed among them.
const List<String> tomTodoFileKeys = [
  'quest',
  'scope',
  'references',
  'created',
  'updated',
  'author',
];

/// One item of a todo file's `todos:` list.
class TomTodoFileEntry {
  TomTodoFileEntry._({
    required this.index,
    required this.raw,
    required this.todo,
    required this.error,
    required this.unknownKeys,
    required this.lineStart,
    required this.itemStart,
    required this.end,
    required this.keyColumn,
    required this.dashColumn,
    required List<_KeySpan> keys,
    required this.block,
  }) : _keys = keys;

  /// Position in `todos:`.
  final int index;

  /// The item as YAML gave it — unknown keys and nulls included.
  final Map<String, Object?> raw;

  /// The item in the shared model, or null when the model refuses it
  /// ([error] says why). A refused item is shown and never edited.
  final TomTodo? todo;
  final String? error;

  /// Keys the model does not know, kept in the file untouched.
  final Set<String> unknownKeys;

  /// Offset of the line holding the item's dash.
  final int lineStart;

  /// Offset of the item's first key, just after `- `.
  final int itemStart;

  /// Offset just past the item's last line.
  final int end;

  /// Column of the item's keys, and of its dash.
  final int keyColumn;
  final int dashColumn;

  /// The item's keys with the line-level extent of each entry.
  final List<_KeySpan> _keys;

  /// Whether the item is a block mapping — the only shape edited key by key.
  final bool block;

  /// The todo's id as written, or `''` when it has none.
  String get id => raw['id']?.toString() ?? '';
}

class _KeySpan {
  _KeySpan(this.key, this.start, this.valueEnd, this.segmentEnd);

  final String key;

  /// The entry's first offset: the key itself for the item's first key (it
  /// shares the dash line), else the start of the key's line.
  final int start;

  /// Just past the line the value ends on.
  final int valueEnd;

  /// Where the next entry starts; between [valueEnd] and here are only
  /// comment and blank lines, which belong to nobody and are kept.
  final int segmentEnd;
}

/// A todo file that cannot be read as one: not YAML, or YAML without a
/// `todos:` list.
class TomTodoFileFormatException implements Exception {
  TomTodoFileFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A parsed todo file over its text.
class TomTodoFile {
  TomTodoFile._({
    required this.text,
    required this.newline,
    required this.entries,
    required this.header,
    required this.schemaRef,
    required YamlMap root,
  }) : _root = root;

  final String text;

  /// The newline a key added to this file is written with.
  final String newline;

  final List<TomTodoFileEntry> entries;

  /// The file-level keys other than `todos`, as YAML gave them.
  final Map<String, Object?> header;

  /// The schema the `# yaml-language-server: $schema=` comment names, or
  /// null when the file names none.
  final String? schemaRef;

  final YamlMap _root;

  /// The todos the model can read, in file order.
  Iterable<TomTodo> get todos => [
    for (final e in entries)
      if (e.todo != null) e.todo!,
  ];

  TomTodoFileEntry? entryFor(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The `quest:` key, or null.
  String? get quest => header['quest']?.toString();

  /// Parses [text]. Throws [TomTodoFileFormatException] when it is not a
  /// todo file at all.
  static TomTodoFile parse(String text) {
    final YamlNode node;
    try {
      node = loadYamlNode(text);
    } on YamlException catch (e) {
      throw TomTodoFileFormatException(e.toString());
    }
    if (node is! YamlMap) {
      throw TomTodoFileFormatException(
        'A todo file is a mapping with a "todos" list.',
      );
    }
    final todosNode = node.nodes['todos'];
    if (todosNode != null &&
        todosNode is! YamlList &&
        !(todosNode is YamlScalar && todosNode.value == null)) {
      throw TomTodoFileFormatException('"todos" is not a list.');
    }
    final header = <String, Object?>{
      for (final e in node.nodes.entries)
        if ((e.key as YamlNode).value != 'todos')
          '${(e.key as YamlNode).value}': _plain(e.value),
    };
    final entries = <TomTodoFileEntry>[];
    if (todosNode is YamlList) {
      for (var i = 0; i < todosNode.nodes.length; i++) {
        entries.add(_entry(text, i, todosNode.nodes[i]));
      }
    }
    return TomTodoFile._(
      text: text,
      newline: tomNewlineOf(text),
      entries: entries,
      header: header,
      schemaRef: tomYamlSchemaRefOf(text),
      root: node,
    );
  }

  static TomTodoFileEntry _entry(String text, int index, YamlNode node) {
    final raw = <String, Object?>{};
    if (node is YamlMap) {
      for (final e in node.nodes.entries) {
        raw['${(e.key as YamlNode).value}'] = _plain(e.value);
      }
    }
    TomTodo? todo;
    String? error;
    final unknown = <String>{};
    if (node is! YamlMap) {
      error = 'This item is not a mapping.';
    } else {
      final known = <String, Object?>{};
      for (final e in raw.entries) {
        if (!TomTodo.fields.contains(e.key)) {
          unknown.add(e.key);
        } else if (e.value != null) {
          known[e.key] = e.value;
        }
      }
      // The schema makes `title` optional and `description` required; the
      // model is titled. An absent title reads as empty and is written only
      // when somebody gives it one.
      known.putIfAbsent('title', () => '');
      try {
        todo = TomTodo.fromMap(known);
      } on Object catch (e) {
        error = e is FormatException ? e.message : '$e';
      }
    }
    final itemStart = node.span.start.offset;
    final lineStart = _lineStart(text, itemStart);
    final dash = text.lastIndexOf('-', itemStart);
    final dashColumn = dash >= lineStart ? dash - lineStart : 0;
    final keys = <_KeySpan>[];
    var end = _lineEndAfter(text, node.span.end.offset);
    final block = node is YamlMap && node.style != CollectionStyle.FLOW;
    if (node is YamlMap && block) {
      final ordered = node.nodes.entries.toList()
        ..sort(
          (a, b) => (a.key as YamlNode).span.start.offset.compareTo(
            (b.key as YamlNode).span.start.offset,
          ),
        );
      for (var k = 0; k < ordered.length; k++) {
        final keyNode = ordered[k].key as YamlNode;
        final keyOffset = keyNode.span.start.offset;
        final start = k == 0 ? keyOffset : _lineStart(text, keyOffset);
        final valueEnd = _lineEndAfter(
          text,
          _contentEnd(text, keyNode, ordered[k].value),
        );
        keys.add(_KeySpan('${keyNode.value}', start, valueEnd, valueEnd));
      }
      for (var k = 0; k + 1 < keys.length; k++) {
        final next = keys[k + 1];
        keys[k] = _KeySpan(
          keys[k].key,
          keys[k].start,
          keys[k].valueEnd,
          next.start,
        );
      }
      if (keys.isNotEmpty) end = keys.last.valueEnd;
    }
    return TomTodoFileEntry._(
      index: index,
      raw: raw,
      todo: todo,
      error: error,
      unknownKeys: unknown,
      lineStart: lineStart,
      itemStart: itemStart,
      end: end,
      keyColumn: itemStart - lineStart,
      dashColumn: dashColumn,
      keys: keys,
      block: block,
    );
  }

  /// The last offset a value occupies. A block scalar's span runs on over the
  /// blank lines after it, which belong to whatever follows; the value ends
  /// at its last non-blank character.
  static int _contentEnd(String text, YamlNode key, YamlNode value) {
    var end = value.span.end.offset;
    if (end <= key.span.end.offset) return key.span.end.offset;
    while (end > 0 && ' \t\r\n'.contains(text[end - 1])) {
      end--;
    }
    return end;
  }

  static int _lineStart(String text, int offset) =>
      offset <= 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

  /// Just past the end of the line holding [offset] - 1.
  static int _lineEndAfter(String text, int offset) {
    if (offset > 0 && text[offset - 1] == '\n') return offset;
    final nl = text.indexOf('\n', offset);
    return nl == -1 ? text.length : nl + 1;
  }

  static Object? _plain(YamlNode node) => switch (node) {
    YamlMap() => {
      for (final e in node.nodes.entries)
        '${(e.key as YamlNode).value}': _plain(e.value),
    },
    YamlList() => [for (final n in node.nodes) _plain(n)],
    _ => node.value,
  };

  // ── Edits. Each returns the new text; the file itself is immutable. ──────

  /// The text with item [index] changed to [edited].
  ///
  /// Only keys whose stored form differs are written; a key the model does
  /// not know, or one whose value merely normalizes differently (a `null`, an
  /// empty list), is left as it is.
  String withTodo(int index, TomTodo edited) {
    final entry = entries[index];
    final before = entry.todo;
    if (before == null) {
      throw StateError('Item $index cannot be edited: ${entry.error}');
    }
    final oldMap = before.toMap();
    final newMap = edited.toMap();
    final set = <String, Object?>{};
    final remove = <String>{};
    for (final key in {...oldMap.keys, ...newMap.keys}) {
      if (_equal(oldMap[key], newMap[key])) continue;
      if (newMap.containsKey(key)) {
        set[key] = newMap[key];
      } else if (entry.raw.containsKey(key)) {
        remove.add(key);
      }
    }
    if (set.isEmpty && remove.isEmpty) return text;
    return _rewriteItem(entry, set, remove, TomTodo.fields.toList());
  }

  /// The text with file-level [key] set to [value], or removed when [value]
  /// is null.
  String withFileKey(String key, Object? value) {
    if (key == 'todos') throw ArgumentError('todos is edited through items');
    final current = header[key];
    if (value == null && !header.containsKey(key)) return text;
    if (value != null && _equal(current, value)) return text;
    final ordered = _root.nodes.entries.toList()
      ..sort(
        (a, b) => (a.key as YamlNode).span.start.offset.compareTo(
          (b.key as YamlNode).span.start.offset,
        ),
      );
    for (final e in ordered) {
      final keyNode = e.key as YamlNode;
      if (keyNode.value != key) continue;
      final start = _lineStart(text, keyNode.span.start.offset);
      final end = _lineEndAfter(text, _contentEnd(text, keyNode, e.value));
      final column = keyNode.span.start.offset - start;
      return text.replaceRange(
        start,
        end,
        value == null ? '' : tomYamlEntry(key, value, column, newline),
      );
    }
    // Absent: after the last header key that precedes `todos:` — never
    // between `todos:` and the comment block above it.
    var at = 0;
    var column = 0;
    for (final e in ordered) {
      final keyNode = e.key as YamlNode;
      if (keyNode.value == 'todos') {
        if (at == 0) {
          at = _lineStart(text, keyNode.span.start.offset);
          column = keyNode.span.start.offset - at;
        }
        break;
      }
      at = _lineEndAfter(text, _contentEnd(text, keyNode, e.value));
      column =
          keyNode.span.start.offset -
          _lineStart(text, keyNode.span.start.offset);
    }
    final prefix = at > 0 && text[at - 1] != '\n' ? newline : '';
    return text.replaceRange(
      at,
      at,
      prefix + tomYamlEntry(key, value, column, newline),
    );
  }

  /// The text with [todo] inserted at [at] (the end when null).
  String withInserted(TomTodo todo, {int? at}) =>
      withInsertedBlock(tomYamlListItem(todo.toMap(), 0, newline), at: at);

  /// The text with an already-written item [block] — its own text, dash
  /// included, at any indentation — inserted at [at] (the end when null).
  String withInsertedBlock(String block, {int? at}) {
    final position = at ?? entries.length;
    final todosKey = _root.nodes.keys.cast<YamlNode>().firstWhere(
      (k) => k.value == 'todos',
      orElse: () =>
          throw TomTodoFileFormatException('This file has no "todos" key.'),
    );
    final todosValue = _root.nodes['todos']!;
    if (entries.isEmpty ||
        todosValue is YamlList &&
            todosValue.style == CollectionStyle.FLOW &&
            todosValue.nodes.isEmpty) {
      // `todos:` with nothing, or `todos: []`: the list starts here.
      final keyLine = _lineStart(text, todosKey.span.start.offset);
      final column = todosKey.span.start.offset - keyLine;
      final end = _lineEndAfter(text, _contentEnd(text, todosKey, todosValue));
      return text.replaceRange(
        keyLine,
        end,
        '${' ' * column}todos:$newline'
        '${_reindent(block, column + 2)}',
      );
    }
    if (todosValue is YamlList && todosValue.style == CollectionStyle.FLOW) {
      throw TomTodoFileFormatException(
        'This file writes its todos as a flow list; edit it as text.',
      );
    }
    final dash = entries.first.dashColumn;
    final body = _reindent(block, dash);
    if (position >= entries.length) {
      final offset = entries.last.end;
      final prefix = offset > 0 && text[offset - 1] != '\n' ? newline : '';
      // A file without a final newline keeps having none.
      final tail = offset == text.length && prefix.isNotEmpty
          ? body.replaceFirst(RegExp(r'\r?\n$'), '')
          : body;
      return text.replaceRange(offset, offset, prefix + tail);
    }
    final offset = entries[position].lineStart;
    return text.replaceRange(offset, offset, body);
  }

  /// The text with item [index] removed. Comment lines around it stay.
  String withoutTodo(int index) {
    final entry = entries[index];
    return text.replaceRange(entry.lineStart, entry.end, '');
  }

  /// Item [index]'s own text, dash line to last line.
  @visibleForTesting
  String blockOf(int index) {
    final entry = entries[index];
    var block = text.substring(entry.lineStart, entry.end);
    if (!block.endsWith('\n')) block += newline;
    return block;
  }

  /// Item [index]'s text with [key] set to [value] — the archive and delete
  /// stamps, written into the block that moves.
  String blockWith(int index, String key, Object value) {
    final entry = entries[index];
    final rewritten = _rewriteItem(
      entry,
      {key: value},
      const {},
      TomTodo.fields.toList(),
    );
    final file = TomTodoFile.parse(rewritten);
    return file.blockOf(index);
  }

  /// The text with item [from] moved to position [to] (the index it has
  /// afterwards). The moved item keeps its own text.
  String withMoved(int from, int to) {
    if (from == to) return text;
    final block = blockOf(from);
    final without = TomTodoFile.parse(withoutTodo(from));
    return without.withInsertedBlock(block, at: to);
  }

  /// Rewrites [entry]'s keys: [set] replaces or adds, [remove] drops. Every
  /// key in neither keeps its text.
  String _rewriteItem(
    TomTodoFileEntry entry,
    Map<String, Object?> set,
    Set<String> remove,
    List<String> order,
  ) {
    final firstRemoved =
        entry._keys.isNotEmpty && remove.contains(entry._keys.first.key);
    if (!entry.block || entry._keys.isEmpty || firstRemoved) {
      // Not a shape a key can be edited in: write the item afresh. Its
      // unknown keys come with it, so nothing is dropped.
      final merged = {...entry.raw}..removeWhere((k, _) => remove.contains(k));
      merged.addAll(set);
      final item = tomYamlListItem(merged, entry.dashColumn, newline);
      return text.replaceRange(entry.lineStart, entry.end, item);
    }
    final present = {for (final k in entry._keys) k.key};
    final added = [
      for (final k in set.keys)
        if (!present.contains(k)) k,
    ];
    // Each absent key goes after the nearest key before it in [order] that
    // the item has; with none, after the last key.
    final insertAfter = <String, List<String>>{};
    for (final key in added) {
      final at = order.indexOf(key);
      String? anchor;
      for (var i = at - 1; i >= 0; i--) {
        if (present.contains(order[i]) && !remove.contains(order[i])) {
          anchor = order[i];
          break;
        }
      }
      anchor ??= entry._keys.last.key;
      (insertAfter[anchor] ??= []).add(key);
    }
    final out = StringBuffer(text.substring(0, entry._keys.first.start));
    for (var i = 0; i < entry._keys.length; i++) {
      final span = entry._keys[i];
      final first = i == 0;
      if (remove.contains(span.key)) {
        // dropped; the comments after it stay
      } else if (set.containsKey(span.key)) {
        final written = tomYamlEntry(
          span.key,
          set[span.key],
          entry.keyColumn,
          newline,
        );
        out.write(first ? written.substring(entry.keyColumn) : written);
      } else {
        out.write(text.substring(span.start, span.valueEnd));
      }
      final needsBreak = !out.toString().endsWith('\n');
      for (final key in insertAfter[span.key] ?? const <String>[]) {
        if (needsBreak) out.write(newline);
        out.write(tomYamlEntry(key, set[key], entry.keyColumn, newline));
      }
      out.write(text.substring(span.valueEnd, span.segmentEnd));
    }
    out.write(text.substring(entry._keys.last.segmentEnd));
    return out.toString();
  }

  /// [block] moved so its dash sits at [column].
  String _reindent(String block, int column) {
    final lines = block.split('\n');
    final first = lines.first;
    final current = first.length - first.trimLeft().length;
    final delta = column - current;
    if (delta == 0) return block;
    return [
      for (final line in lines)
        if (line.trim().isEmpty)
          line
        else if (delta > 0)
          '${' ' * delta}$line'
        else
          line.substring(
            (line.length - line.trimLeft().length).clamp(0, -delta),
          ),
    ].join('\n');
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_equal(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
