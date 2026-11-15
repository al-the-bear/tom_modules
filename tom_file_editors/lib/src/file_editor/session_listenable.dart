/// A file's editing session as something Flutter's builders listen to.
library;

import 'package:flutter/foundation.dart';
import 'package:tom_file_session/tom_file_session.dart';

/// A [ForgeFileSession] as the [Listenable] Flutter's builders listen to.
/// Two over one session are equal, so a rebuild keeps its subscription.
class TomFileSessionListenable implements Listenable {
  const TomFileSessionListenable(this.session);

  final ForgeFileSession session;

  @override
  void addListener(VoidCallback listener) => session.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      session.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is TomFileSessionListenable && other.session == session;

  @override
  int get hashCode => session.hashCode;
}
