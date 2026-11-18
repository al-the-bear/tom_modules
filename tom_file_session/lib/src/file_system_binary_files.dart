import 'dart:typed_data';

import 'package:tom_file_system/tom_file_system.dart' as fs;

import 'binary_files.dart';

/// [TomBinaryFiles] whose files are read as bytes because they have no path
/// on the machine (a remote or virtual file system): a consumer that would
/// hand a path to a native library reads the bytes with [readBytes] instead.
abstract interface class TomBinaryFileBytes implements TomBinaryFiles {
  /// The bytes of the file at [path], or `null` when there is no file.
  Future<Uint8List?> readBytes(String path);
}

/// The binary save rules over a [fs.TomFileSystem] (`tom_file_system`): the
/// files of a file system that need not be the machine's — a remote one, an
/// in-memory one. Paths are the file system's (relative to its root).
///
/// The same rules as `TomBinaryFileAccess`: a revision taken when the file
/// was read, a temporary file `.<name>.tom-save-<n>` in the same folder, the
/// original replaced only while it is the revision read (else a conflict
/// that keeps the temporary file), *keep mine* replacing whatever is there.
/// The file system writes atomically; the replace checks the revision before
/// it writes and passes it to the write, so a change in between is still a
/// conflict.
class TomFileSystemBinaryFiles implements TomBinaryFileBytes {
  /// Binary files over [fileSystem].
  TomFileSystemBinaryFiles(this.fileSystem);

  /// The file system.
  final fs.TomFileSystem fileSystem;

  /// The infix of a temporary file's name.
  static const temporaryInfix = '.tom-save-';

  Uri _uri(String path) => fileSystem.uriOf(path);

  static TomFileRevision _revision(fs.TomFileRevision r) =>
      TomFileRevision(size: r.size, modified: r.modified, sha256: r.sha256);

  Future<fs.TomFileContent?> _read(String path) async {
    final uri = _uri(path);
    if (!await fileSystem.exists(uri)) return null;
    return fileSystem.read(uri);
  }

  @override
  Future<Uint8List?> readBytes(String path) async => (await _read(path))?.bytes;

  @override
  Future<TomFileRevision?> revisionOf(String path) async {
    final content = await _read(path);
    return content == null ? null : _revision(content.revision);
  }

  /// A file system says nothing of permissions: a file that exists is taken
  /// as writable, and a refused write is reported when it happens.
  @override
  Future<bool> isWritable(String path) => fileSystem.exists(_uri(path));

  (String folder, String name) _split(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0
        ? ('', path)
        : (path.substring(0, slash + 1), path.substring(slash + 1));
  }

  @override
  Future<String> temporaryTarget(String path) async {
    final (folder, name) = _split(path);
    for (var n = 1; ; n++) {
      final candidate = '$folder.$name$temporaryInfix$n';
      final uri = _uri(candidate);
      if (await fileSystem.exists(uri)) continue;
      await fileSystem.create(uri);
      return candidate;
    }
  }

  @override
  Future<TomBinaryReplaceResult> replace(
    String original,
    String temporary,
    TomFileRevision? expectedRevision, {
    bool force = false,
  }) async {
    final current = await _read(original);
    final now = current == null ? null : _revision(current.revision);
    final unchanged = expectedRevision == null
        ? now == null
        : now != null && now.sameContent(expectedRevision);
    if (!force && !unchanged) {
      return TomBinaryReplaceResult(
        TomBinaryReplaceOutcome.conflict,
        now,
        temporary,
      );
    }
    final bytes = (await fileSystem.read(_uri(temporary))).bytes;
    final fs.TomFileRevision written;
    try {
      written = await fileSystem.write(
        _uri(original),
        bytes,
        expected: force ? null : current?.revision,
      );
    } on fs.TomFileConflict catch (e) {
      return TomBinaryReplaceResult(
        TomBinaryReplaceOutcome.conflict,
        e.current == null ? null : _revision(e.current!),
        temporary,
      );
    }
    await fileSystem.delete(_uri(temporary));
    return TomBinaryReplaceResult(
      TomBinaryReplaceOutcome.replaced,
      _revision(written),
      temporary,
    );
  }

  @override
  Future<TomBinaryReplaceResult> save(
    String path,
    List<int> bytes,
    TomFileRevision? expectedRevision,
  ) async {
    final temporary = await temporaryTarget(path);
    try {
      await fileSystem.write(_uri(temporary), Uint8List.fromList(bytes));
    } catch (_) {
      await fileSystem.delete(_uri(temporary));
      rethrow;
    }
    return replace(path, temporary, expectedRevision);
  }

  @override
  Future<String> keepAsCopy(String temporary, String original) async {
    final (folder, name) = _split(original);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    for (var n = 1; ; n++) {
      final copy = '$folder$stem${n == 1 ? ' (copy)' : ' (copy $n)'}$ext';
      if (await fileSystem.exists(_uri(copy))) continue;
      await fileSystem.rename(_uri(temporary), _uri(copy));
      return copy;
    }
  }

  @override
  Future<List<String>> removeTemporaryFiles(String path) async {
    final (folder, name) = _split(path);
    final prefix = '.$name$temporaryInfix';
    final removed = <String>[];
    final dir = folder.isEmpty
        ? fileSystem.root
        : fileSystem.uriOf(folder.substring(0, folder.length - 1));
    if (!await fileSystem.exists(dir)) return removed;
    for (final entry in await fileSystem.list(dir)) {
      if (!entry.name.startsWith(prefix)) continue;
      if (int.tryParse(entry.name.substring(prefix.length)) == null) continue;
      await fileSystem.delete(entry.uri);
      removed.add('$folder${entry.name}');
    }
    return removed;
  }
}
