import 'dart:io';

import 'package:crypto/crypto.dart';

import '../binary_files.dart';

/// The save rules of `ForgeFileSession`, for files an editor never holds as
/// text: office documents and PDFs, written by a helper process or received
/// as bytes.
///
/// A save never writes into the original. It writes a temporary file in the
/// same folder ([temporaryTarget]), then [replace] renames it over the
/// original — one atomic step on the same volume — only if the original is
/// still the one read, keeping its permissions. Otherwise the result is a
/// conflict and the temporary file is kept for the user's choice (keep mine,
/// take theirs, save as copy). [removeTemporaryFiles] clears what is left.
///
/// The check and the rename are two steps: a write by another program in
/// between is not seen. The window is the time of one `stat` and one hash.
class TomBinaryFileAccess implements TomBinaryFiles {
  /// The file access. Stateless; one instance serves every file.
  const TomBinaryFileAccess();

  /// The infix of every temporary file's name, `.<name>.tom-save-<n>`.
  static const temporaryInfix = '.tom-save-';

  /// The revision of the file at [path], or `null` when there is no file.
  ///
  /// The SHA-256 is computed by streaming the file, so a large file is not
  /// read into memory at once.
  @override
  Future<TomFileRevision?> revisionOf(String path) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return null;
    final digest = await sha256.bind(file.openRead()).first;
    return TomFileRevision(
      size: stat.size,
      modified: stat.modified,
      sha256: digest.toString(),
    );
  }

  /// A new, empty temporary file for a save of [path], in the same folder:
  /// `.<name>.tom-save-<n>` with the smallest free `<n>` from 1.
  ///
  /// The file is created (exclusively) so that two saves never share one.
  /// Throws a [FileSystemException] when the folder cannot be written.
  @override
  Future<String> temporaryTarget(String path) async {
    final file = File(path);
    final folder = file.parent.path;
    final name = file.uri.pathSegments.last;
    for (var n = 1; ; n++) {
      final candidate =
          '$folder${Platform.pathSeparator}.$name$temporaryInfix$n';
      try {
        await File(candidate).create(exclusive: true);
        return candidate;
      } on FileSystemException {
        if (await FileSystemEntity.type(candidate) ==
            FileSystemEntityType.notFound) {
          rethrow; // not a name clash: the folder is not writable
        }
      }
    }
  }

  /// Renames [temporary] over [original] when the original is still the one
  /// read at [expectedRevision] (the same bytes, [TomFileRevision.sameContent]),
  /// keeping the original's permissions, and returns the new revision.
  ///
  /// [expectedRevision] `null` means no file was there when the save began
  /// (a new file): a file that appeared since is a conflict too.
  ///
  /// On a conflict nothing is written and [temporary] is kept.
  @override
  Future<TomBinaryReplaceResult> replace(
    String original,
    String temporary,
    TomFileRevision? expectedRevision, {
    bool force = false,
  }) async {
    final current = await revisionOf(original);
    final unchanged =
        force ||
        (expectedRevision == null
            ? current == null
            : current != null && current.sameContent(expectedRevision));
    if (!unchanged) {
      return TomBinaryReplaceResult(
        TomBinaryReplaceOutcome.conflict,
        current,
        temporary,
      );
    }
    if (current != null) {
      await _copyMode(original, temporary);
    }
    await File(temporary).rename(original);
    return TomBinaryReplaceResult(
      TomBinaryReplaceOutcome.replaced,
      await revisionOf(original),
      temporary,
    );
  }

  /// Writes [bytes] to [path] by the same rules: a temporary target, flushed,
  /// then [replace]. A failed write removes the temporary file and rethrows.
  @override
  Future<TomBinaryReplaceResult> save(
    String path,
    List<int> bytes,
    TomFileRevision? expectedRevision,
  ) async {
    final temporary = await temporaryTarget(path);
    try {
      await File(temporary).writeAsBytes(bytes, flush: true);
    } catch (_) {
      await _deleteQuietly(temporary);
      rethrow;
    }
    return replace(path, temporary, expectedRevision);
  }

  /// Deletes the temporary files left beside [path] (`.<name>.tom-save-<n>`)
  /// and returns their paths. Other files are never touched.
  @override
  Future<List<String>> removeTemporaryFiles(String path) async {
    final file = File(path);
    final prefix = '.${file.uri.pathSegments.last}$temporaryInfix';
    final removed = <String>[];
    if (!await file.parent.exists()) return removed;
    await for (final entry in file.parent.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.startsWith(prefix)) continue;
      if (int.tryParse(name.substring(prefix.length)) == null) continue;
      await entry.delete();
      removed.add(entry.path);
    }
    return removed;
  }

  @override
  Future<String> keepAsCopy(String temporary, String original) async {
    final file = File(original);
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    final folder = file.parent.path;
    for (var n = 1; ; n++) {
      final suffix = n == 1 ? ' (copy)' : ' (copy $n)';
      final candidate = '$folder${Platform.pathSeparator}$stem$suffix$ext';
      if (await FileSystemEntity.type(candidate) ==
          FileSystemEntityType.notFound) {
        await File(temporary).rename(candidate);
        return candidate;
      }
    }
  }

  @override
  Future<bool> isWritable(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (Platform.isWindows) {
      try {
        final raf = await file.open(mode: FileMode.append);
        await raf.close();
        return true;
      } on FileSystemException {
        return false;
      }
    }
    // access(2) through test(1): permissions, ACLs and read-only volumes.
    final result = await Process.run('test', ['-w', path]);
    return result.exitCode == 0;
  }

  /// Gives [to] the permission bits of [from]. `dart:io` has no `chmod`, so
  /// POSIX systems run the `chmod` tool; on Windows the rename keeps the
  /// folder's inherited permissions.
  static Future<void> _copyMode(String from, String to) async {
    if (Platform.isWindows) return;
    final mode = (await File(from).stat()).mode & 0xFFF;
    final result = await Process.run('chmod', [mode.toRadixString(8), to]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'could not set the permissions of the temporary file: '
                '${result.stderr}'
            .trim(),
        to,
      );
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
