/// archive and delete as **relocation** — a todo moves to the
/// file's `-archived` or `-deleted` sibling, stamped with the date, and a
/// completed todo's decisions are copied to the quest's decisions journal.
///
/// The order is the workspace tooling's: target first, then the journal, then
/// the source. A failure between them leaves the todo in both files, which a
/// second attempt reconciles because the target is keyed by id; source first
/// would fail the other way, with the todo in neither. Unlike the tooling,
/// the act is undoable: it is one entry in the source file's history, and the
/// undo puts all three files back — refusing, rather than guessing, when any
/// of them changed on disk since.
library;

import 'package:tom_basics/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:tom_file_system/tom_file_system.dart';
import 'package:tom_file_session/tom_file_session.dart';
import 'package:tom_todo_model/tom_todo_model.dart';


/// A relocation the file or the todo does not allow.
class TomTodoRelocationRefused implements Exception {
  TomTodoRelocationRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Moves todos out of a file into its siblings.
class TomTodoRelocator {
  TomTodoRelocator({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Why [index] of [file] (named [fileName]) cannot be relocated by
  /// [kind], or null when it can.
  static String? refusal(
    TomTodoFile file,
    String fileName,
    int index,
    TomTodoRelocationKind kind,
  ) =>
      tomTodoRelocationRefusal(file, fileName, index, kind);

  /// Relocates todo [index] of [session]'s file by [kind]. The session must
  /// hold no unsaved edits: the act writes the file. Records the act in the
  /// session's history.
  Future<void> relocate(
    ForgeFileSession session,
    int index,
    TomTodoRelocationKind kind,
  ) async {
    if (session.dirty) {
      throw StateError('Save or discard the unsaved edits first.');
    }
    final tree = session.fileSystem;
    final source = TomTodoFile.parse(session.text);
    final fileName = p.posix.basename(session.path);
    final refused = refusal(source, fileName, index, kind);
    if (refused != null) throw TomTodoRelocationRefused(refused);
    final entry = source.entries[index];
    final now = _clock();
    final dir = p.posix.dirname(session.path);
    String inDir(String name) => dir == '.' ? name : '$dir/$name';

    // Target: keyed by id, so a re-run after an interruption replaces.
    final targetPath = inDir(tomTodoSiblingName(fileName, kind));
    final targetBefore = await _readOrNull(tree, targetPath);
    var encoding = TomTextEncoding.utf8;
    String? target;
    if (targetBefore != null) {
      final decoded = tomDecodeTextBytes(targetBefore.bytes);
      if (!decoded.encoding.writable) {
        throw TomTodoRelocationRefused(
            '$targetPath is not UTF-8 or UTF-16; it is not written.');
      }
      encoding = decoded.encoding;
      target = decoded.text;
    }

    // The journal, for a completed todo with decisions (archive only).
    final journalName =
        tomTodoRelocationJournalName(source, fileName, index, kind);
    final journalPath = journalName == null ? null : inDir(journalName);
    final journalBefore =
        journalPath == null ? null : await _readOrNull(tree, journalPath);

    final plan = tomPlanTodoRelocation(
      source: source,
      fileName: fileName,
      index: index,
      kind: kind,
      now: now,
      target: target,
      journal: journalBefore == null
          ? null
          : tomDecodeTextBytes(journalBefore.bytes).text,
    );
    final targetText = plan.targetText;
    final journalText = plan.journalText;
    final sourceText = plan.sourceText;

    final sourceBefore = TomFileContent(
      tomEncodeText(session.text, session.encoding),
      session.revision!,
    );

    // The writes, target first.
    final targetAfter = await tree.write(
        tree.uriOf(targetPath), tomEncodeText(targetText, encoding),
        expected: targetBefore?.revision);
    TomFileRevision? journalAfter;
    if (journalPath != null) {
      journalAfter = await tree.write(
          tree.uriOf(journalPath), tomEncodeText(journalText!, TomTextEncoding.utf8),
          expected: journalBefore?.revision);
    }
    final sourceBytes = tomEncodeText(sourceText, session.encoding);
    final TomFileRevision sourceAfter;
    try {
      sourceAfter = await tree.write(tree.uriOf(session.path), sourceBytes,
          expected: session.revision);
    } on TomFileConflict {
      await _restore(tree, targetPath, targetBefore, targetAfter);
      if (journalPath != null) {
        await _restore(tree, journalPath, journalBefore, journalAfter!);
      }
      rethrow;
    }

    final targetBytes = tomEncodeText(targetText, encoding);
    final journalBytes = journalText == null
        ? null
        : tomEncodeText(journalText, TomTextEncoding.utf8);
    var sourceNow = sourceAfter;
    var targetNow = targetAfter;
    var journalNow = journalAfter;
    final label = '${kind.verb} `${entry.id}`';
    session.recordDiskAct(
      ForgeFileDiskAct(
        label,
        undo: () async {
          await _expect(tree, session.path, sourceNow);
          await _expect(tree, targetPath, targetNow);
          if (journalPath != null) await _expect(tree, journalPath, journalNow);
          await _restore(tree, targetPath, targetBefore, targetNow);
          if (journalPath != null) {
            await _restore(tree, journalPath, journalBefore, journalNow!);
          }
          final rev = await tree.write(tree.uriOf(session.path), sourceBefore.bytes,
              expected: sourceNow);
          sourceNow = rev;
          return TomFileContent(sourceBefore.bytes, rev);
        },
        redo: () async {
          await _expect(tree, session.path, sourceNow);
          targetNow = await tree.write(tree.uriOf(targetPath), targetBytes,
              expected: targetBefore?.revision);
          if (journalPath != null) {
            journalNow = await tree.write(tree.uriOf(journalPath), journalBytes!,
                expected: journalBefore?.revision);
          }
          final rev = await tree.write(tree.uriOf(session.path), sourceBytes,
              expected: sourceNow);
          sourceNow = rev;
          return TomFileContent(sourceBytes, rev);
        },
      ),
      TomFileContent(sourceBytes, sourceAfter),
    );
  }

  static Future<TomFileContent?> _readOrNull(
      TomFileSystem tree, String path) async {
    if (await tree.stat(tree.uriOf(path)) == null) return null;
    return tree.read(tree.uriOf(path));
  }

  /// Refuses when [path] is no longer the revision this act left it at.
  static Future<void> _expect(
      TomFileSystem tree, String path, TomFileRevision? revision) async {
    final now = await _readOrNull(tree, path);
    if (now?.revision != revision) {
      throw TomFileConflict(tree.uriOf(path), now?.revision);
    }
  }

  /// Puts [path] back as [before] — or removes it, when the act created it.
  static Future<void> _restore(
    TomFileSystem tree,
    String path,
    TomFileContent? before,
    TomFileRevision written,
  ) async {
    if (before == null) {
      await tree.delete(tree.uriOf(path));
    } else {
      await tree.write(tree.uriOf(path), before.bytes, expected: written);
    }
  }
}
