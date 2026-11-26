# ADR-0004: EzKey multi-platform posture

- **Status:** Proposed (2026-10-30). D2 and D3 amended (2026-11-08, #108): the tier is read back from the key. D2 amended (2026-11-23, #134): the Windows key store on the TPM, and its per-user key boundary. D5 decided (2026-11-24, #133): pasting the invitation, built in #158. D4 window handling built (2026-11-25, #163).
- **Issue:** #48. Extends ADR-0001 D2 (native key store) and ADR-0002 (key storage, written for Android) to every platform upstream ships.

## Context

Upstream ships five platforms: Android (Google Play), iOS and macOS (App Store; Darwin projects on Swift Package Manager since 2026-07-08), Windows (Microsoft Store, MSIX) and Linux (Flathub, Snap). The EzKey integration started Android-only: its one native piece is the Android Keystore plugin, and the home hook shows EzKey only on Android. Off Android the app is exactly upstream's.

The user wants iOS / macOS (Xcode on a remote Mac, no iPhone yet) and Windows desktop (#49) next, and asked to firm up the posture first so those ports start without debt. An audit on 2026-10-30 found Android assumptions in shared code: the key store provider typed `AndroidEzkeyDeviceKeyStore`, a channel result `strongBox: bool`, Android-only prompt messages, an inline `currentPlatform == .android`. It also found a gap: desktop has no camera scanner and manual invitation entry is debug-only (#38), so a release desktop build could not enroll.

The SDK is pure Dart (`dart:io`, `cryptography`, `pointycastle`); the enrollment records live in upstream's secure storage (`simple_secure_storage`), which already runs everywhere. Only the device key needs native code.

## Decision

1. **One availability rule.** `ezkeySupportedPlatforms` (`lib/ezkey/availability.dart`) lists where EzKey is offered; every entry point checks `ezkeyAvailable`. Today: Android. A platform joins only when it has (a) a hardware key store behind the channel (D2), (b) a way to enroll in release builds (D5), and (c) a checked build that passes the key store contract test (D6). Elsewhere the app stays exactly upstream's.
2. **One plugin, one channel contract.** `packages/ezkey_keystore/` stays a single plugin package. Each platform implements the same `org.ezkey.keystore` channel: methods `generateKeyPair`, `sign`, `publicKey`, `keyTier`, `deleteKeyPair`, `aliases`; SPKI DER and ASN.1 DER signatures in standard Base64 (high-S allowed, the SDK normalizes); `tier` as `strong` / `standard` / `none`, as the platform reports it; error codes `key_not_found`, `invalid_arguments`, `keystore_error`, never carrying key material or payloads. The Dart client (`EzkeyKeystore`) and the adapter (`NativeEzkeyDeviceKeyStore`) are therefore the same on every platform. Native code per platform:
   - Android: Kotlin, Android Keystore (done).
   - iOS and macOS: one Swift implementation (`sharedDarwinSource`) with a `Package.swift`, since upstream's Darwin projects use SPM.
   - Windows: CNG with the Platform Crypto Provider (TPM), in C++ (#134). Calls run on a worker thread, as on Android. A PC whose TPM cannot be used gets a software key, reported `none` (D3).
     **Key boundary: per user (decided 2026-11-23).** A CNG key belongs to the Windows user, not to the app, even inside the MSIX package: any process of that user can ask it to sign, none can copy it off the device. Accepted because it is the boundary upstream already has for its own secrets on Windows (salt, password signature and derived key in the Credential Manager), and because parity with Android's per-app key comes from the app-level confirmation (D4; ADR-0002 already rejected binding the key to user authentication). Rejected: a CNG UI policy (a Windows consent or PIN dialog on every signature) and a Windows Hello key (RSA only and a Hello prompt per use, so a change to EzKey's protocol).
3. **Tier mapping.** `strong`: a discrete secure element (Android StrongBox). `standard`: the platform's main hardware key store (Android TEE, Apple Secure Enclave, a TPM), as the SDK's `DevicePrivateKeyStorageTier` defines it. A platform without a hardware key store is not enabled. That means Linux for now. On an enabled platform, every implementation reads the tier back from the key it generated, as the platform reports it (#108): `strong` only when the platform confirms the discrete secure element, otherwise the lower tier it can prove, down to `none` when the key is outside secure hardware or the platform cannot tell (an emulator). Such a key is not refused: best effort, verified, reported honestly; a minimum tier is the server's to enforce.
4. **Shared Dart stays platform-neutral.** Platform code lives only in the plugin. Shared code passes every platform's values where an API asks for them: local confirmation passes iOS, macOS, Android and Windows prompt messages, like upstream's `LocalAuthenticationDefault`. Around the device credential prompt it opens itself (no app unlock method chosen), `EzkeyDeviceConfirmation` does what upstream's `LocalAuthenticationDefault.authenticate` does on desktop (#163): it focuses the window and keeps it on top during the prompt, then restores its always-on-top state and, on Windows and macOS, blurs and refocuses it (flutter/flutter#122322); a second prompt while one is open is refused. With an app unlock method, the confirmation goes through upstream's code, which already does this. The guard cannot see a prompt opened by upstream's own local authentication without changing upstream code. The alias format and the debug / main namespace (#41) apply unchanged on every platform.
5. **Enrollment in release builds needs an input per platform.** Android, iOS and macOS have the camera scanner (`mobile_scanner`). Windows and Linux have none.
   **Decided with the maintainer (2026-11-24, #133): the user can paste the invitation, in release builds and on every platform.** The pasted text is the JSON the QR code holds: the proof token and the server address. Scanning stays the first choice where there is a camera. One path for every platform also covers a phone that shows its own invitation (#111). It is EzKey's own direction: mgagp/ezkey#1185 (paste in release builds, and a copy of the JSON in the Admin UI).
   Why a bearer token may go through the clipboard: bind is read-once, the invitation expires (7 days by default, set by the server), and the 6-digit challenge is required, is never in the JSON, and allows one attempt. Accepted residual risk: a clipboard manager, Windows clipboard history or its cloud sync may keep the text.
   The operator hands the JSON to the user, with the challenge through another channel. EzKey's invitation email carries the QR image only; adding the text to it is EzKey's later choice.
   Rejected:
   - **an EzKey invitation link:** a verified `https` link needs domains known at build time, while each adopter has its own; a custom scheme can be claimed by any app; and registering one touches upstream's link files on every platform;
   - **reading the QR code from an image or a screen capture:** not a desktop gesture, and the image keeps the token;
   - **leaving EzKey off desktop:** fails the goal of this ADR.

   The server address is optional in the invitation today (EzKey ADR-0019) and should become required (mgagp/ezkey#1300). Until then the app keeps asking for a missing address.
6. **Tests.** Shared logic is tested with a mocked channel, so the unit tests do not depend on the platform. `test/ezkey/availability_test.dart` pins D1. `integration_test/ezkey/keystore_test.dart` is the contract test every platform implementation must pass on a real key store. The iOS simulator has no Secure Enclave, so Apple needs a Mac with one or an iPhone.

## Alternatives considered

- **A Dart interface with one adapter class per platform.** Rejected for now: the channel is already the seam, and one Dart class stays in sync with all platforms for free. It becomes necessary if a platform is reached without a channel (for example Windows through FFI); introduce it then.
- **Software keys where no hardware store exists.** Rejected: the key would be extractable, and the SDK reserves `none` for tests and labs.
- **Federated plugin packages (one package per platform).** Heavier than needed at this size. Reconsider when the plugin moves to the EzKey repository (ADR-0001 D2).
- **Third-party Secure Enclave / TPM plugins.** Not chosen: different contracts, less control over the tier and the error mapping. Reconsider if one covers every platform with the same contract.

## Consequences

- Android behaviour is unchanged. Checked on the emulator with `keystore_test` and the e2e, plus the unit tests.
- A port is: native code behind the channel, the D5 paste entry where there is no camera, then the platform added to `ezkeySupportedPlatforms`, a build and the contract test. No shared Dart change is expected.
- Windows (#49) brought the build first, then the key store on the TPM (#134). The paste entry of D5 followed (#158). The window handling of D4 followed (#163). Turning EzKey on for Windows now waits for a full trial run on a PC and the maintainer's decision.
- Apple waits for remote Mac access and a device with a Secure Enclave.

## References

- `packages/ezkey_keystore/lib/ezkey_keystore.dart`: channel contract.
- `lib/ezkey/availability.dart`, `lib/ezkey/device_key_store.dart`, `lib/ezkey/local_confirmation.dart`.
- ADR-0001 D2, ADR-0002; `docs/ezkey/integration.md` § Layers.
