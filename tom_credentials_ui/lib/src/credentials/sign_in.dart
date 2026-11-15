/// A status line's sign-in: the host an application signs its session into,
/// and whether it is signed in.
///
/// An application that keeps its credential for the session only — a browser
/// build with no settings container — needs a way in that is not a storage
/// command: without one the only path to a token is to try to open something
/// and be asked. This is that capability. It **is** the application's
/// [TomTokenKeeper] as well, so the token prompt a storage command raises, a
/// settings section and the status line all keep a token through the same
/// object, and the item is never out of step with the credential the backend
/// holds.
///
/// No operation returns a secret: what is signed in is a [TomTokenListing],
/// host and account.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'token_keeper.dart';

class TomSignIn extends ChangeNotifier implements TomTokenKeeper {
  /// The host the item signs into, e.g. `github.com`.
  final String host;

  /// What the status line says about how long the credential lasts, shown
  /// beside the signed-in host and in the sign-in tooltip — e.g. "kept for
  /// this tab only; a reload signs you out". Null when there is nothing to
  /// warn about. Settable, for an application whose tokens start out held
  /// for the session and become kept once a settings store opens (the browser
  /// root, once its settings passphrase is typed); a change repaints the item.
  String? get sessionNote => _sessionNote;
  String? _sessionNote;
  set sessionNote(String? note) {
    if (note == _sessionNote) return;
    _sessionNote = note;
    notifyListeners();
  }

  final TomTokenKeeper _keeper;

  TomTokenListing? _signedIn;

  /// Wraps [keeper], the store the application keeps tokens in, and reads from
  /// it whether [host] is signed in already — an application may start with a
  /// credential.
  TomSignIn({
    required this.host,
    required TomTokenKeeper keeper,
    String? sessionNote,
  }) : _keeper = keeper,
       _sessionNote = sessionNote {
    unawaited(_refresh());
  }

  /// The credential held for [host] — host and account, never a secret — or
  /// null while signed out.
  TomTokenListing? get signedIn => _signedIn;

  @override
  bool get keepsBeyondSession => _keeper.keepsBeyondSession;

  @override
  Future<List<TomTokenListing>> listTokens() => _keeper.listTokens();

  /// Keeps [token] through the application's keeper and, when it is for [host],
  /// shows it as signed in.
  @override
  Future<bool> storeToken(TomToken token) async {
    final landed = await _keeper.storeToken(token);
    await _refresh();
    return landed;
  }

  /// Forgets the credential for [host] — the item's sign-out — or any other.
  @override
  Future<bool> revokeToken(String host) async {
    final landed = await _keeper.revokeToken(host);
    await _refresh();
    return landed;
  }

  /// Signs out of [host]: the backend's next request asks for a token again.
  Future<void> signOut() => revokeToken(host);

  Future<void> _refresh() async {
    final listings = await _keeper.listTokens();
    final held = [
      for (final l in listings)
        if (l.host == host) l,
    ].firstOrNull;
    if (held == _signedIn) return;
    _signedIn = held;
    notifyListeners();
  }
}
