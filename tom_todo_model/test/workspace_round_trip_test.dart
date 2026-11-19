/// Every workspace todo file through the codec: each item read into the item
/// model and written back changes not one byte, and its item carries exactly
/// what the file says.
///
/// The files are the workspace's own (`_ai/quests/*/*.todo.yaml`, the
/// `todos.<quest>.todo.yaml` files and their siblings), found by walking up
/// from this package to the folder holding `_ai/quests`. Outside a workspace
/// checkout the test skips and says so: it measures the workspace's files, not
/// fixtures.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_todo_model/tom_todo_model.dart';

/// The workspace's `_ai/quests` folder, or null when this checkout has none.
Directory? _questsFolder() {
  var dir = Directory.current.absolute;
  while (true) {
    final quests = Directory('${dir.path}/_ai/quests');
    if (quests.existsSync()) return quests;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

bool _empty(Object? value) =>
    value == null ||
    (value is String && value.isEmpty) ||
    (value is List && value.isEmpty) ||
    (value is Map && value.isEmpty);

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_same(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return '$a' == '$b';
}

void main() {
  final quests = _questsFolder();
  final files = quests == null
      ? <File>[]
      : [
          for (final dir in quests.listSync().whereType<Directory>())
            for (final f in dir.listSync().whereType<File>())
              if (f.path.endsWith('.todo.yaml')) f,
        ];
  final skip = quests == null
      ? 'no _ai/quests above ${Directory.current.path}: not in a workspace '
            'checkout, nothing to measure'
      : null;

  test('ITEM-R1: the workspace has todos.<quest>.todo.yaml files to '
      'measure', () {
    final main = files.where(
      (f) => RegExp(r'/todos\.[^/]+\.todo\.yaml$').hasMatch(f.path),
    );
    expect(main, isNotEmpty);
  }, skip: skip);

  test('ITEM-R2: every item of every workspace todo file is read, and '
      'writing it back changes no byte', () {
    var items = 0;
    final problems = <String>[];
    for (final f in files) {
      final text = f.readAsStringSync();
      final file = TomTodoFile.parse(text);
      for (final entry in file.entries) {
        final item = entry.item;
        if (item == null) {
          problems.add('${f.path} ${entry.id}: refused: ${entry.error}');
          continue;
        }
        items++;
        if (file.withItem(entry.index, item.copy()) != text) {
          problems.add('${f.path} ${entry.id}: written back differently');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.take(20).join('\n'));
    expect(items, greaterThan(0));
  }, skip: skip);

  test('ITEM-R3: each item holds exactly what its keys say: every non-empty '
      'key of the file is the item\'s, the item adds nothing, and it is a '
      'todo', () {
    final problems = <String>[];
    for (final f in files) {
      final file = TomTodoFile.parse(f.readAsStringSync());
      for (final entry in file.entries) {
        final item = entry.item;
        if (item == null) continue;
        final map = item.toMap();
        for (final e in entry.raw.entries) {
          if (_empty(e.value) || !TomItem.fields.contains(e.key)) continue;
          if (!_same(map[e.key], e.value)) {
            problems.add(
              '${f.path} ${entry.id} ${e.key}: not what the file says',
            );
          }
        }
        for (final key in map.keys) {
          if (!entry.raw.containsKey(key) &&
              key != 'status' &&
              key != 'title') {
            problems.add('${f.path} ${entry.id} $key: added by the model');
          }
        }
        if (!item.types().contains(TomItemType.todo)) {
          problems.add('${f.path} ${entry.id}: not a todo');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.take(20).join('\n'));
  }, skip: skip);
}
