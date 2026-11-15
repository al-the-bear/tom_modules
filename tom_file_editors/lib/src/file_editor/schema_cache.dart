/// The schema a YAML file names, found and compiled once.
///
/// A file names its schema in a `# yaml-language-server: $schema=` comment,
/// resolved against the file's own folder. The todo editor and the YAML
/// editor both validate against it, on every edit, so the compiled schema is
/// kept per path and source text.
library;

import 'dart:convert';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;

/// Reads a schema file by absolute path; null when it is not there.
typedef TomSchemaReader = Future<String?> Function(String absolutePath);

/// What looking for a file's schema found.
class TomSchemaResolution {
  const TomSchemaResolution({this.schema, this.path, this.note});

  /// The compiled schema, or null when none applies.
  final JsonSchema? schema;

  /// The schema's absolute path, when it was found.
  final String? path;

  /// Why the named schema was not applied, when it was not.
  final String? note;
}

/// Finds and compiles schemas, once per path and text.
class TomSchemaCache {
  TomSchemaCache({required this.read});

  final TomSchemaReader read;
  final Map<String, (String, JsonSchema)> _compiled = {};

  /// The schema [ref] names for the file at [filePath]. [instead] says what
  /// applies when it cannot be used ("the todo model's rules").
  Future<TomSchemaResolution> resolve(
    String? ref,
    String filePath, {
    required String instead,
  }) async {
    if (ref == null) return const TomSchemaResolution();
    if (Uri.tryParse(ref)?.hasScheme ?? false) {
      return TomSchemaResolution(
        note:
            'The schema $ref is not a local file; $instead applied '
            'instead.',
      );
    }
    final path = p.normalize(p.join(p.dirname(filePath), ref));
    final source = await read(path);
    if (source == null) {
      return TomSchemaResolution(
        note:
            'The schema the file names, $path, was not found; $instead '
            'applied instead.',
      );
    }
    try {
      final cached = _compiled[path];
      if (cached != null && cached.$1 == source) {
        return TomSchemaResolution(schema: cached.$2, path: path);
      }
      final schema = JsonSchema.create(jsonDecode(source));
      _compiled[path] = (source, schema);
      return TomSchemaResolution(schema: schema, path: path);
    } on Object catch (e) {
      return TomSchemaResolution(
        note:
            'The schema $path could not be read ($e); $instead applied '
            'instead.',
      );
    }
  }
}

/// YAML values as the JSON a schema validates: maps keyed by strings.
Object? tomJsonOf(Object? value) => switch (value) {
  Map() => {for (final e in value.entries) '${e.key}': tomJsonOf(e.value)},
  List() => [for (final v in value) tomJsonOf(v)],
  _ => value,
};
