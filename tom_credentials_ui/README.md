# tom_credentials_ui

Asking for keys and access tokens the same way everywhere: the key fields and
key prompt, the token dialog and the flow that asks when a backend needs a
token, the status-line sign-in, and the platform keychain as a secret store.

License: BSD-3-Clause (see [LICENSE](LICENSE)).

## Components

| Component | Folder | What it does |
| --- | --- | --- |
| Credentials | `lib/src/credentials/` | Asking for a container key and an access token with the same dialogs everywhere. The key fields (`TomKeyFields`: passphrase with show/hide, a key file through the host's `TomKeyFilePicker`, "remember for this file") over a `TomKeyStepController`; the key step of creating or converting (`TomKeyStep`: the default key or one for this file); the key prompt when no configured key opens a container (`showTomKeyDialog`, answering a `TomKeyRequest` of `tom_core_storage`'s `TomKeyMaterial`). The token keeper port (`TomTokenKeeper`, `TomSessionTokenKeeper`), the token dialog (`showTomTokenDialog`) and the flow that asks when a backend needs a token and tries again (`withTomTokenFlow`); the status-line sign-in (`TomSignIn`, `TomSignInIndicator`). No operation returns a secret. |
| Secret store | `lib/src/secret_store/` | The platform keychain (Keychain, libsecret, Credential Manager) as `tom_core_storage`'s `TomSecretStore`, under a key prefix the application names (`TomPlatformSecretStore`); on macOS the login keychain, which needs no entitlement. |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_credentials_ui/tom_credentials_ui.dart` | the key fields, key step and key prompt, the token keeper, dialog and flow, the sign-in item | all |
| `package:tom_credentials_ui/desktop.dart` | the above, plus `TomPlatformSecretStore` | macOS, Linux, Windows |

## Dependencies

Flutter, `flutter_secure_storage`, `tom_core_storage`.

## Tests

`flutter test` from this folder.
