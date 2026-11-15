/// What a file editor asks of the application that shows it.
///
/// The editors in this package — plain text, `.env` and the todo file —
/// edit one file through its [ForgeFileSession] — the session carries the
/// bytes, the save and the history — and reach the rest of the application
/// only through a host: the undo and redo that the application routes (so
/// its own shortcuts and the editor's agree), a place to say something to the
/// user, and the protected clipboard.
library;

import 'package:flutter/widgets.dart';
import 'package:tom_file_session/tom_file_session.dart';

/// The host of a file editor: one file, shown in one place.
abstract interface class TomFileEditorHost {
  /// The editing session of the file shown.
  ForgeFileSession get session;

  /// The file's name, as history entries name it (`Edit notes.md`).
  String get name;

  /// The file's absolute path — what a schema reference in it is resolved
  /// against.
  String get filePath;

  /// Undoes the file's last entry, saying why when it cannot.
  Future<void> undo(BuildContext context);

  /// Redoes the file's last undone entry, saying why when it cannot.
  Future<void> redo(BuildContext context);

  /// Tells the user [message]; [kind] groups notices so a newer one replaces
  /// an older one of the same kind.
  void notice(BuildContext context, String message, {required String kind});

  /// Puts a secret on the clipboard so that it is cleared again after the
  /// configured timeout.
  Future<void> copyProtected(String value);
}
