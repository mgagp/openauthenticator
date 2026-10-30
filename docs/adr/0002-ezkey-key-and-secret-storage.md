# ADR-0002: EzKey device key and enrollment secrets on Android

- **Status:** Accepted (2026-10-27)
- **Issue:** #17; applies to #16 slice 1

## Context

An EzKey enrollment puts two different kinds of material on the phone:

| Material | Nature | Must stay | Used for |
| --- | --- | --- | --- |
| Device private key (EC P-256, one per enrollment) | Signing key | Non-exportable; never in app memory | Signing `verify`, every `pending` poll, and `respond` |
| Enrollment record (`EzkeyEnrollment`): enrollment proof token, integration public key, display metadata | Data | Confidential (the proof token is a bearer secret) and untampered (the integration key is the trust anchor for every server answer) | Sent or used in plain on every call, so it must be readable by the app |

Android offers two mechanisms, often confused:

- **Android Keystore** holds keys and runs operations in secure hardware: the **TEE** (an isolated zone of the main processor, present on almost all devices) or **StrongBox** (a dedicated secure chip, Android 9+, e.g. Titan M2 on the Pixel 7 Pro). The app sends data and receives a signature; it never sees the private key.
- **Secure storage** (here `simple_secure_storage`, i.e. EncryptedSharedPreferences) is an encrypted file whose AES key lives in the Keystore. It protects data at rest; the value is decrypted into app memory when used.

The Flutter ↔ Kotlin bridge (platform channel) carries only public material for signing: an alias, the canonical string, the signature, the public key. It adds no security limit; its costs are writing Kotlin and running Keystore calls off the main thread.

## Decision

1. **Device key: Android Keystore, StrongBox when available.** P-256, `PURPOSE_SIGN`, `DIGEST_SHA256`, non-exportable. Generation first requests StrongBox (`setIsStrongBoxBacked(true)`) and falls back to the TEE on `StrongBoxUnavailableException`. The tier is reported honestly through `EzkeyDeviceKeyStore.storageTier` (`strong` / `standard`). Keystore calls run on a background thread (StrongBox signatures take tens to hundreds of milliseconds). The SDK chooses the alias and deletes the key on failed enrollment and on `forget`.
2. **No user-authentication binding on the key.** `pending` signs with the same key on every poll, so a key that requires biometrics would prompt on every check. Local confirmation, when enabled, is an app-level prompt on **Approve only**, as the EzKey contract §4 (Q11) prescribes. It is enabled by the user's "Confirm before approvals" setting, off by default like the EzKey reference app (#34). This is honest-client protection, not a server-verifiable proof (same wording boundary as EzKey's `MOBILE_CRYPTO_REFERENCE.md`).
3. **Signatures returned as the Keystore produces them.** Android Keystore emits high-S ECDSA signatures about half of the time and the Auth API rejects them (SEC-012); `ezkey_dart` 0.3.0 normalizes every key-store signature to low-S (EzKey finding G8, found while preparing this ADR). The plugin does not re-implement that.
4. **Enrollment records: the app's existing secure storage** (`secureStorageProvider`, AES-256-GCM, master key in the TEE). Upstream already excludes this storage from cloud backup and device transfer.
5. **No attestation.** The protocol does not carry Android Key Attestation, so the tier stays self-reported, as in EzKey's reference app. Do not describe the result as attested, StrongBox-guaranteed or FIDO2-equivalent.

## Alternatives considered

- **StrongBox for the storage key too.** It would change upstream's storage initialization (alignment rule) and slow every read; the TEE already makes the AES key non-extractable. Rejected.
- **A dedicated seal key per EzKey installation**, like EzKey's reference app (`ADR-MOB-0006`): defense in depth between several EzKey servers on one phone. More native code for a case the tracer bullet does not exercise. Deferred; revisit if several installations become a real use case.
- **Encrypting records with Open Authenticator's master-password `CryptoStore`.** Would tie EzKey approvals to the TOTP vault password and to its re-encryption flow, mixing two security models. Rejected for now; the app-unlock gate already protects UI access.
- **Key bound to user authentication** (`setUserAuthenticationRequired` + `BiometricPrompt.CryptoObject`): stronger binding, but prompts on every `pending` poll and needs a protocol change to be meaningful to the server (EzKey `MOBILE_LOCAL_AUTH_POLICY_AND_AUDIT_FUTURE_WORK.md`). Rejected.

## Consequences

- **Enrollments do not survive a phone change or reinstall**: the Keystore key never leaves the device and the records are excluded from backup. The user re-enrolls (the protocol has no key rotation or transfer).
- **Storage recovery edge case.** When the encrypted preferences cannot be decrypted (e.g. restored from an old backup), upstream clears them (`_StorageRecovery` in `lib/model/secure_storage.dart`). EzKey records then disappear while their Keystore keys remain. Slice 1 handles both directions: orphan keys (an `ezkey-device-*` alias with no record) are deleted, and a record whose key is missing surfaces as `EzkeyLocalStateException` and is shown as unusable with a remove action (as in EzKey's MOB-015 behaviour).
- **Testing split.** Dart tests use the SDK's `SoftwareDeviceKeyStore` and fake server; Keystore behaviour (StrongBox tier, fallback, signatures accepted by the server) is verified on the device and recorded in [`docs/ezkey/integration.md`](../ezkey/integration.md).
- The enrollment proof token passes through Dart memory on every call; this is inherent to the protocol in any stack and is mitigated by never logging records (SDK redaction, app code review).

## References

- EzKey repo: `ezkey_dart/README.md` §4.2–4.3 and §5; `ezkey_mobile/docs/MOBILE_CRYPTO_REFERENCE.md` (Secure storage vs Keystore, app-enforced guarantee boundary); `ezkey_mobile/docs/MOBILE_DATA_MODEL.md` (Cornerstone, enrollment rehydration outcomes); `docs/CLIENT_BEHAVIOUR_CONTRACT.md` §4.
- This repo: `lib/model/secure_storage.dart`; `android/app/src/main/res/xml/data_extraction_rules.xml`, `backup_rules.xml`; ADR-0001.
