# ADR-0004: EzKey multi-platform posture

- **Status:** Proposed (2026-10-30)
- **Issue:** #48. Extends ADR-0001 D2 (native key store) and ADR-0002 (key storage, written for Android) to every platform upstream ships.

## Context

Upstream ships five platforms: Android (Google Play), iOS and macOS (App Store; Darwin projects on Swift Package Manager since 2026-07-08), Windows (Microsoft Store, MSIX) and Linux (Flathub, Snap). The EzKey integration started Android-only: its one native piece is the Android Keystore plugin, and the home hook shows EzKey only on Android. Off Android the app is exactly upstream's.

The user wants iOS / macOS (Xcode on a remote Mac, no iPhone yet) and Windows desktop (#49) next, and asked to firm up the posture first so those ports start without debt. An audit on 2026-10-30 found Android assumptions in shared code: the key store provider typed `AndroidEzkeyDeviceKeyStore`, a channel result `strongBox: bool`, Android-only prompt messages, an inline `currentPlatform == .android`. It also found a gap: desktop has no camera scanner and manual invitation entry is debug-only (#38), so a release desktop build could not enroll.

The SDK is pure Dart (`dart:io`, `cryptography`, `pointycastle`); the enrollment records live in upstream's secure storage (`simple_secure_storage`), which already runs everywhere. Only the device key needs native code.

## Decision

1. **One availability rule.** `ezkeySupportedPlatforms` (`lib/ezkey/availability.dart`) lists where EzKey is offered; every entry point checks `ezkeyAvailable`. Today: Android. A platform joins only when it has (a) a hardware key store behind the channel (D2), (b) a way to enroll in release builds (D5), and (c) a checked build that passes the key store contract test (D6). Elsewhere the app stays exactly upstream's.
2. **One plugin, one channel contract.** `packages/ezkey_keystore/` stays a single plugin package. Each platform implements the same `org.ezkey.keystore` channel: methods `generateKeyPair`, `sign`, `publicKey`, `deleteKeyPair`, `aliases`; SPKI DER and ASN.1 DER signatures in standard Base64 (high-S allowed, the SDK normalizes); `tier` as `strong` / `standard`; error codes `key_not_found`, `invalid_arguments`, `keystore_error`, never carrying key material or payloads. The Dart client (`EzkeyKeystore`) and the adapter (`NativeEzkeyDeviceKeyStore`) are therefore the same on every platform. Native code per platform:
   - Android: Kotlin, Android Keystore (done).
   - iOS and macOS: one Swift implementation (`sharedDarwinSource`) with a `Package.swift`, since upstream's Darwin projects use SPM.
   - Windows: CNG with the Platform Crypto Provider (TPM).
3. **Tier mapping.** `strong`: a discrete secure element (Android StrongBox). `standard`: the platform's main hardware key store (Android TEE, Apple Secure Enclave, a TPM), as the SDK's `DevicePrivateKeyStorageTier` defines it. Software keys (`none`) are never offered: a platform without a hardware key store is not enabled. That means Linux for now.
4. **Shared Dart stays platform-neutral.** Platform code lives only in the plugin. Shared code passes every platform's values where an API asks for them: local confirmation passes iOS, macOS, Android and Windows prompt messages, like upstream's `LocalAuthenticationDefault`. The desktop window-focus handling upstream adds around that prompt comes with the first desktop port. The alias format and the debug / main namespace (#41) apply unchanged on every platform.
5. **Enrollment in release builds needs an input per platform.** Android, iOS and macOS have the camera scanner (`mobile_scanner`). Windows and Linux have none. The choice is open and must be made, with the user, before a desktop platform joins D1:
   - accept the pasted invitation in release builds, since the code is one-time, short-lived and needs the 6-digit challenge;
   - read the QR code from an image or a screen capture;
   - leave EzKey off desktop.
6. **Tests.** Shared logic is tested with a mocked channel, so the unit tests do not depend on the platform. `test/ezkey/availability_test.dart` pins D1. `integration_test/ezkey/keystore_test.dart` is the contract test every platform implementation must pass on a real key store. The iOS simulator has no Secure Enclave, so Apple needs a Mac with one or an iPhone.

## Alternatives considered

- **A Dart interface with one adapter class per platform.** Rejected for now: the channel is already the seam, and one Dart class stays in sync with all platforms for free. It becomes necessary if a platform is reached without a channel (for example Windows through FFI); introduce it then.
- **Software keys where no hardware store exists.** Rejected: the key would be extractable, and the SDK reserves `none` for tests and labs.
- **Federated plugin packages (one package per platform).** Heavier than needed at this size. Reconsider when the plugin moves to the EzKey repository (ADR-0001 D2).
- **Third-party Secure Enclave / TPM plugins.** Not chosen: different contracts, less control over the tier and the error mapping. Reconsider if one covers every platform with the same contract.

## Consequences

- Android behaviour is unchanged. Checked on the emulator with `keystore_test` and the e2e, plus the unit tests.
- A port is: native code behind the channel, the D5 choice for desktop, then the platform added to `ezkeySupportedPlatforms`, a build and the contract test. No shared Dart change is expected.
- Windows (#49) brings the build first. EzKey on Windows waits for a TPM implementation and D5.
- Apple waits for remote Mac access and a device with a Secure Enclave.

## References

- `packages/ezkey_keystore/lib/ezkey_keystore.dart`: channel contract.
- `lib/ezkey/availability.dart`, `lib/ezkey/device_key_store.dart`, `lib/ezkey/local_confirmation.dart`.
- ADR-0001 D2, ADR-0002; `docs/ezkey/integration.md` § Layers.
