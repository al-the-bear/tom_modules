/// The platform secret store for the desktop hosts.
///
/// A device holds **exactly one** secret here: the key of its encrypted
/// settings container. Everything else a device knows — tokens, document
/// keys — lives *inside* that container, so the platform keychain holds one
/// entry and losing it costs one file. The handle is minted by
/// `TomSettingsKeyBootstrap` and recorded in the plaintext device settings;
/// only the secret itself comes from here.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tom_core_storage/settings.dart';

/// [TomSecretStore] over the platform keychain (Keychain on macOS, libsecret
/// on Linux, DPAPI-backed credential storage on Windows).
class TomPlatformSecretStore implements TomSecretStore {
  /// Prefixed to every key this application stores, so a shared keychain
  /// namespace stays legible and a stray delete cannot reach another
  /// application's entries. Each application names its own, and keeps it:
  /// the entries already in a user's keychain are found by it.
  final String keyPrefix;

  final FlutterSecureStorage _storage;

  /// The plugin as this store configures it.
  ///
  /// **macOS uses the file-based login keychain, not the data-protection
  /// keychain** (`usesDataProtectionKeychain: false`). The data-protection
  /// keychain is reachable only with a `keychain-access-groups` entitlement,
  /// which requires signing with a development certificate — an ad-hoc signed
  /// build (`CODE_SIGN_IDENTITY = "-"`) refuses it at build time. Without the
  /// entitlement, the plugin's default fails every call with -34018 ("a
  /// required entitlement isn't present"). The login keychain needs no
  /// entitlement and is still encrypted at rest under the user's login. A
  /// build signed with a team identity may switch to the data-protection
  /// keychain together with the entitlement.
  static const _platformStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  const TomPlatformSecretStore({
    required this.keyPrefix,
    FlutterSecureStorage storage = _platformStorage,
  }) : _storage = storage;

  String _key(String handle) => '$keyPrefix$handle';

  @override
  Future<String?> read(String handle) => _storage.read(key: _key(handle));

  @override
  Future<void> write(String handle, String secret) =>
      _storage.write(key: _key(handle), value: secret);

  @override
  Future<void> delete(String handle) => _storage.delete(key: _key(handle));
}
