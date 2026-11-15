/// Where an application keeps access tokens.
///
/// Where a token is kept is the application's decision: in an encrypted
/// settings container and for the session, or for the session only. Two
/// surfaces use it — the token prompt a storage command raises
/// ([withTomTokenFlow]) and a settings section that lists, replaces and
/// revokes tokens — so it is one port with three operations rather than a
/// store callback plus a second way in.
///
/// **No operation returns a secret.** A settings section lists hosts and
/// accounts and replaces a token without showing the one it replaces; the
/// type of [TomTokenKeeper.listTokens] cannot carry one.
library;

import 'package:tom_core_storage/tom_core_storage.dart';

import 'token_dialog.dart';

abstract interface class TomTokenKeeper {
  /// Whether a token kept here outlives the session. False on a build with no
  /// settings container — the Tokens section then says so.
  bool get keepsBeyondSession;

  /// The credentials held, by host and account.
  Future<List<TomTokenListing>> listTokens();

  /// Keeps [token], replacing any held for its host, and answers whether it
  /// was recorded beyond this session. Usable at once either way.
  Future<bool> storeToken(TomToken token);

  /// Forgets the credential for [host] — in the session and wherever it was
  /// recorded — and answers whether the removal was recorded.
  Future<bool> revokeToken(String host);
}

/// A keeper that holds tokens for the session only — for a build with no
/// settings container to record one in, such as a browser.
///
/// Every write answers false, because nothing was recorded beyond the
/// session; the token is usable at once all the same.
class TomSessionTokenKeeper implements TomTokenKeeper {
  final TomInMemoryTokenSource source;

  const TomSessionTokenKeeper(this.source);

  @override
  bool get keepsBeyondSession => false;

  @override
  Future<List<TomTokenListing>> listTokens() async =>
      source.listings..sort((a, b) => a.host.compareTo(b.host));

  @override
  Future<bool> storeToken(TomToken token) async {
    source.put(token);
    return false;
  }

  @override
  Future<bool> revokeToken(String host) async {
    source.remove(host);
    return false;
  }
}
