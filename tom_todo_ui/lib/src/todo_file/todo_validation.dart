/// a todo file checked against the schema it names.
///
/// The schema is the one the file's `# yaml-language-server: $schema=` comment
/// names, resolved against the file's own folder; a file naming none is held
/// to the D8 model's rules alone. Every finding carries the todo it belongs
/// to, so the editor shows it on that row.
library;

import 'package:tom_todo_model/tom_todo_model.dart';

import 'package:tom_file_editors/tom_file_editors.dart';

/// One finding: on todo [index], or on the file when [index] is null.
class TomTodoFileIssue {
  const TomTodoFileIssue(this.message, {this.index, this.path = ''});

  final String message;
  final int? index;

  /// Where in the item, as a JSON pointer below it (`/status`), or `''`.
  final String path;

  @override
  String toString() =>
      index == null ? message : 'todo ${index! + 1}$path: $message';
}

/// What validation found, and which schema it used.
class TomTodoFileValidation {
  const TomTodoFileValidation(this.issues, {this.schemaPath, this.note});

  final List<TomTodoFileIssue> issues;

  /// The schema that was applied, or null when the model's rules were.
  final String? schemaPath;

  /// Why the named schema was not applied, when it was not.
  final String? note;

  bool get valid => issues.isEmpty;

  List<TomTodoFileIssue> forTodo(int index) => [
    for (final i in issues)
      if (i.index == index) i,
  ];

  Iterable<TomTodoFileIssue> get fileIssues =>
      issues.where((i) => i.index == null);
}

/// Validates [file], whose absolute path is [filePath].
///
/// The schema is found and compiled by the shared [TomSchemaCache].
class TomTodoFileValidator {
  TomTodoFileValidator({required this.schemas});

  final TomSchemaCache schemas;

  Future<TomTodoFileValidation> validate(
    TomTodoFile file,
    String filePath,
  ) async {
    final issues = <TomTodoFileIssue>[
      for (final e in file.entries)
        if (e.error != null) TomTodoFileIssue(e.error!, index: e.index),
    ];
    final ids = <String, int>{};
    for (final e in file.entries) {
      if (e.id.isEmpty) continue;
      final first = ids[e.id];
      if (first != null) {
        issues.add(
          TomTodoFileIssue(
            'The id "${e.id}" is also todo ${first + 1}.',
            index: e.index,
          ),
        );
      } else {
        ids[e.id] = e.index;
      }
    }
    final resolution = await schemas.resolve(
      file.schemaRef,
      filePath,
      instead: 'the todo model\'s rules were',
    );
    final schema = resolution.schema;
    if (schema == null) {
      return TomTodoFileValidation(issues, note: resolution.note);
    }
    final schemaPath = resolution.path;
    final instance = <String, Object?>{
      ...file.header,
      'todos': [for (final e in file.entries) e.raw],
    };
    final result = schema.validate(tomJsonOf(instance));
    for (final error in result.errors) {
      final m = RegExp(r'^/todos/(\d+)(.*)$').firstMatch(error.instancePath);
      issues.add(
        m == null
            ? TomTodoFileIssue(
                '${error.instancePath.isEmpty ? '' : '${error.instancePath}: '}'
                '${error.message}',
              )
            : TomTodoFileIssue(
                error.message,
                index: int.parse(m.group(1)!),
                path: m.group(2)!,
              ),
      );
    }
    return TomTodoFileValidation(issues, schemaPath: schemaPath);
  }
}
