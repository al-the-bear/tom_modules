import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// What a file was when it was read: its size, modification time and the
/// SHA-256 of its bytes.
///
/// Two revisions are equal when all three agree. Whether a file changed for a
/// save is decided by [sameContent]: a file touched without a change to its
/// bytes is still the file that was read.
@immutable
final class TomFileRevision {
  /// A revision from its parts.
  const TomFileRevision({
    required this.size,
    required this.modified,
    required this.sha256,
  });

  /// The size in bytes.
  final int size;

  /// The modification time.
  final DateTime modified;

  /// The SHA-256 of the bytes, lower-case hexadecimal.
  final String sha256;

  /// Whether [other] has the same bytes: the same size and SHA-256.
  bool sameContent(TomFileRevision other) =>
      size == other.size && sha256 == other.sha256;

  @override
  bool operator ==(Object other) =>
      other is TomFileRevision &&
      other.size == size &&
      other.modified == modified &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(size, modified, sha256);

  @override
  String toString() =>
      'TomFileRevision($size bytes, ${modified.toIso8601String()}, '
      '${sha256.substring(0, 12)}…)';
}

/// How [TomBinaryFileAccess.replace] ended.
enum TomBinaryReplaceOutcome {
  /// The temporary file now is the original; [TomBinaryReplaceResult.revision]
  /// is its new revision.
  replaced,

  /// The original is not the one read: changed, deleted, or created where
  /// none was expected. Nothing was written; the temporary file is kept for
  /// the conflict choice, and [TomBinaryReplaceResult.revision] is what is on
  /// disk now (`null` when there is no file).
  conflict,
}

/// The result of [TomBinaryFileAccess.replace].
@immutable
final class TomBinaryReplaceResult {
  /// A result from its parts.
  const TomBinaryReplaceResult(this.outcome, this.revision, this.temporary);

  /// How it ended.
  final TomBinaryReplaceOutcome outcome;

  /// After [TomBinaryReplaceOutcome.replaced] the file's new revision; after
  /// [TomBinaryReplaceOutcome.conflict] the revision on disk, or `null` when
  /// the file does not exist.
  final TomFileRevision? revision;

  /// The temporary file: gone after a replace, kept after a conflict.
  final String temporary;

  /// Whether the original was replaced.
  bool get replaced => outcome == TomBinaryReplaceOutcome.replaced;

  @override
  String toString() => 'TomBinaryReplaceResult(${outcome.name}, $revision)';
}

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
class TomBinaryFileAccess {
  /// The file access. Stateless; one instance serves every file.
  const TomBinaryFileAccess();

  /// The infix of every temporary file's name, `.<name>.tom-save-<n>`.
  static const temporaryInfix = '.tom-save-';

  /// The revision of the file at [path], or `null` when there is no file.
  ///
  /// The SHA-256 is computed by streaming the file, so a large file is not
  /// read into memory at once.
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
  Future<TomBinaryReplaceResult> replace(
    String original,
    String temporary,
    TomFileRevision? expectedRevision,
  ) async {
    final current = await revisionOf(original);
    final unchanged = expectedRevision == null
        ? current == null
        : current != null && current.sameContent(expectedRevision);
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
