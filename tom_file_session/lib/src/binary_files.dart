import 'package:meta/meta.dart';
import 'package:tom_file_system/tom_file_system.dart' show TomFileRevision;

export 'package:tom_file_system/tom_file_system.dart' show TomFileRevision;

/// The revision of a binary file is `tom_file_system`'s [TomFileRevision]
/// (size, modification time, SHA-256), the same type the editing session and
/// every file system use, so a library that imports both packages sees one
/// declaration.
///
/// Whether a file changed for a save is decided by
/// [TomFileRevisionContent.sameContent]: a file touched without a change to
/// its bytes is still the file that was read.
extension TomFileRevisionContent on TomFileRevision {
  /// Whether [other] has the same bytes: the same size and SHA-256.
  bool sameContent(TomFileRevision other) =>
      size == other.size && sha256 == other.sha256;
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

/// The save rules for binary files, as the main library sees them: a
/// [TomFileRevision] taken when the file was read, a temporary target in the
/// same folder, and a replace of the original only while it is unchanged.
///
/// `TomBinaryFileAccess` (`package:tom_file_session/io.dart`) is the
/// `dart:io` implementation; a host on the web, or a test, gives its own.
abstract interface class TomBinaryFiles {
  /// The revision of the file at [path], or `null` when there is no file.
  Future<TomFileRevision?> revisionOf(String path);

  /// Whether the file at [path] can be written (permissions, read-only
  /// volumes); false when it does not exist.
  Future<bool> isWritable(String path);

  /// A new, empty temporary file for a save of [path], in the same folder:
  /// `.<name>.tom-save-<n>`.
  Future<String> temporaryTarget(String path);

  /// Renames [temporary] over [original] when the original is still the one
  /// read at [expectedRevision] (`null`: no file was there), keeping its
  /// permissions; otherwise a conflict that keeps [temporary]. [force]
  /// replaces whatever is there (the user chose *keep mine*).
  Future<TomBinaryReplaceResult> replace(
    String original,
    String temporary,
    TomFileRevision? expectedRevision, {
    bool force = false,
  });

  /// Writes [bytes] to [path] by the same rules.
  Future<TomBinaryReplaceResult> save(
    String path,
    List<int> bytes,
    TomFileRevision? expectedRevision,
  );

  /// Renames [temporary] to `<name> (copy).<ext>` beside [original] (the
  /// first free `(copy n)`), and returns the copy's path.
  Future<String> keepAsCopy(String temporary, String original);

  /// Deletes the temporary files left beside [path] and returns their paths.
  Future<List<String>> removeTemporaryFiles(String path);
}
