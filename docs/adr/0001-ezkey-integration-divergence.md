# ADR-0001: EzKey integration divergence from upstream

- **Status:** Accepted (2026-10-27, approved by the user in #16)
- **Issue:** #16 (tracer bullet), #17 (this record)

## Context

This fork follows upstream exactly (CLAUDE.md, "Upstream alignment", issue #8). The one planned exception is integrating the EzKey device SDK (`ezkey_dart`, from `mgagp/ezkey`) so that Open Authenticator can act as an EzKey authenticator: enroll with an EzKey invitation, then approve or deny sign-in requests. The integration needs new dependencies, native Android code (the SDK defines a key-store interface but ships no Flutter implementation) and UI entry points. Every change to an upstream file makes future upstream syncs harder, so the divergence has to be both explicit and small.

## Decision

- **D1, dependency reference.** `ezkey_dart` is a git dependency of `pubspec.yaml`, `url: https://github.com/mgagp/ezkey`, `path: ezkey_dart`, pinned with `ref:` to a commit. `pubspec.lock` records the resolved commit. Re-pin to `main` when mgagp/ezkey#1068 (SDK 0.3.0) merges, and re-pin deliberately on every SDK update (one PR, tests run).
- **D2, native key store as a local plugin.** The Android Keystore implementation lives in a small Flutter plugin package inside the fork (`packages/ezkey_keystore/`, Android only, Kotlin), referenced by path. Flutter registers plugins automatically, so `android/app/.../MainActivity.kt` (upstream) stays untouched.
- **D3, code placement.** EzKey Dart code goes in new files under `lib/ezkey/`. Upstream files only receive the hooks the UI needs (a route, an entry point). Each PR lists the upstream files it touches, and [`docs/ezkey/integration.md`](../ezkey/integration.md) keeps the cumulative ledger.
- **D4, new transitive packages.** The SDK brings `cryptography`, `pointycastle` and `unorm_dart`. `http` and `args` are already in the lock; no version conflict was found (2026-10-27).

## Alternatives considered

- **Path dependency** (`path: ../ezkey/ezkey_dart`): simplest locally, but machine-specific and unusable in CI. Rejected.
- **Vendoring the SDK** into the fork: decouples releases but forks the SDK too, so fixes found here would not flow back to EzKey, which defeats the purpose of the exercise (the integration is meant to harden the SDK and its guide). Rejected.
- **Method channel in `MainActivity.kt`**: fewer files, but edits an upstream file that upstream also changes (it already hosts two channels). Rejected in favour of D2.
- **Using an existing pub.dev plugin** for keystore signing: none found that offers non-exportable, sign-only P-256 keys with StrongBox preference in the shape the SDK's `EzkeyDeviceKeyStore` needs. Reconsider if one appears.

## Consequences

- Upstream syncs stay mechanical outside `pubspec.yaml`, `pubspec.lock` and the listed hooks.
- `flutter pub get` needs network access to GitHub for the git dependency (the lock pins the commit, so builds stay reproducible).
- The plugin package can later move to the EzKey repository as the reusable Android key store the EzKey vision note anticipates; D2 keeps that move cheap.
- Friction found during the integration is fixed in the SDK or the EzKey contract, not worked around in the fork (#16).

## References

- #8 (upstream alignment rule), #16 (tracer bullet and D1–D4), mgagp/ezkey#1068 (SDK 0.3.0).
- EzKey vision note `V-2026-10-27-third-party-authenticator-integration-kit` (step 4).
