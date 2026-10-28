# EzKey integration — design notes

Living design document for #16. It records how Open Authenticator meets the EzKey client contract and what it changes in upstream files. Protocol and behaviour rules are **not** restated here: they live in the EzKey repository (`mgagp/ezkey`), linked below. Decisions with trade-offs are ADRs ([0001](../adr/0001-ezkey-integration-divergence.md), [0002](../adr/0002-ezkey-key-and-secret-storage.md)).

## Sources (EzKey repo)

| Source | Canonical for |
| --- | --- |
| `docs/CLIENT_BEHAVIOUR_CONTRACT.md` | What any client MUST / SHOULD / MAY do between API calls |
| `ezkey_dart/README.md` | SDK API, storage hooks, integration pitfalls |
| `docs/MOBILE_DEVELOPER_GUIDE.md` | Wire protocol, signed payloads, problem types |
| `ezkey_mobile/docs/MOBILE_APP_STATE_MACHINE.md`, `MOBILE_SCREENS_AND_WIREFLOWS.md`, `MOBILE_POSITIONING.md` | Reference app behaviour, screens and naming vocabulary (inspiration for slices 2–3, not obligations) |
| `sites/ezkey-org/technical-trace-ezkey-enrollment-authentication.html` | One complete real exchange (enroll, instance-info, pending, respond) with actual values |

## Layers

| Layer | Location | Owns |
| --- | --- | --- |
| SDK | `ezkey_dart` (git dependency, ADR-0001 D1) | Protocol, signatures and checks, decision lock, error classification, low-S normalization |
| Native key store | `packages/ezkey_keystore/` (ADR-0001 D2) | Android Keystore P-256 keys, StrongBox preference, tier, alias listing. Channel `org.ezkey.keystore`; no dependency on `ezkey_dart`, so it can move to EzKey as is |
| App integration | `lib/ezkey/` (ADR-0001 D3) | `device_key_store.dart` (adapter + app-owned alias format `ezkey-device-<id>-<random>`), `enrollment_store.dart` (one secure-storage entry per record, unreadable records reported), `orphan_keys.dart`; `providers.dart` (Riverpod wiring; orphan cleanup runs once when the authenticator is first built, before any enrollment), `messages.dart` (error copy), `pages/` (EzKey list, scan, confirm + code), `settings_entry.dart`. Strings: `lib/i18n/{en,fr}/ezkey.json` (slang namespace `ezkey`; other locales fall back to English) |
| Upstream hooks | Ledger below | Entry points only |

## Contract conformance

One row per contract rule that applies to this app. "SDK" means `ezkey_dart` enforces it; "App" means our code must, with the test that proves it. Filled in as slices land.

| Contract rule | Level | Owner | How | Proof | Status |
| --- | --- | --- | --- | --- | --- |
| §1.1 Pending is a one-shot claim | MUST (server) | SDK + App | SDK returns the claimed attempt once; the app keeps it in memory until decided | — | Slice 3 |
| §1.2 No context before the pending signature verifies; no refusal on fail-closed | MUST NOT | SDK + App | SDK throws `EzkeyIntegrityException`; the app shows a neutral error and sends nothing | — | Slice 3 |
| §1.3 No device countdown as a security control | MUST NOT | App | No timer UI; `isCertainlyExpired` only hides stale prompts | — | Slice 3 |
| §2 Decision lock, unknown outcome | MUST / SHOULD | SDK | `PendingAuthAttempt.decisionState`, `EzkeyRespondOutcomeUnknownException` (SDK 0.3.0 tests) | SDK tests | Done in SDK; app UI in slice 3 |
| §3 Leave-as-deny, permanent line, no retry loop | SHOULD | App | `deny` once on leave when `attempt.canDecide` | — | Slice 3 |
| §4 Local confirmation on Approve only | SHOULD | App | App-level prompt (ADR-0002 decision 2) | — | Slice 3 |
| §5 409 conflict / expired are final | MUST | SDK + App | `isAttemptNoLongerActionable`; Back only | — | Slice 3 |
| §6 Result signature before showing the outcome | MUST | SDK | Integrity check; attempt locked | SDK tests | Done in SDK |
| §7 Error copy from `type` / status, never `detail` | MUST NOT | App | `ezkeyEnrollmentErrorMessage` maps exception type and `EzkeyProblemKind` to `ezkey` strings | `test/ezkey/messages_test.dart` | Enrollment done (#20); approvals in slice 3 |
| §8 Lifetime bounds (15–120 s) | MUST (server) | SDK | `maxAuthAttemptTtl`, advisory expiry | SDK tests | Done in SDK |

## Upstream files touched

Cumulative ledger (ADR-0001 D3). Every entry names the PR and why the hook could not live in a new file.

| File | Change | PR |
| --- | --- | --- |
| `pubspec.yaml`, `pubspec.lock` | `ezkey_dart` git dependency (pinned commit), `ezkey_keystore` path dependency; the lock only gains `ezkey_dart`, `ezkey_keystore`, `cryptography`, `pointycastle`, `unorm_dart` | Slice 1 (#16) |
| `pubspec.yaml`, `pubspec.lock` | `integration_test` (`sdk: flutter`) in `dev_dependencies` for on-device tests; the lock gains SDK packages only (`integration_test`, `flutter_driver`, …) | Slice 1 (#16) |
| `lib/pages/settings/page.dart` | One import and one Android-only tile (`EzkeySettingsEntryWidget`) in the Security group: the settings list is a literal widget tree, so an entry cannot be added from outside it. Pages are pushed with `MaterialPageRoute`, so the route table is untouched | Slice 2 (#20) |
| `lib/i18n/en/ezkey.json`, `lib/i18n/fr/ezkey.json` | New files (no upstream file changed): slang only reads translations from `lib/i18n/` | Slice 2 (#20) |

## Lab setup (Pixel against the local stack)

`scripts/ezkey_lab.dart` drives a running clean-start stack (#20):

```sh
scripts/with-env.sh dart scripts/ezkey_lab.dart invite                 # prints the QR content and the 6-digit code
scripts/with-env.sh dart scripts/ezkey_lab.dart attempt <enrollmentId> # creates an auth attempt, waits for the decision
scripts/with-env.sh dart scripts/ezkey_lab.dart e2e --test integration_test/ezkey/enrollment_ui_test.dart   # emulator, screenshots in build/ezkey-lab/screens/
```

- Admin API access: the script logs in as `admin.docker` and approves that login itself through the Demo Device web form (`localhost:8083`), then caches the token and an Integration API key under the gitignored `build/ezkey-lab/`. Lab only.
- It creates the integration `oa-lab` ("Open Authenticator Lab") on first use. Active enrollment names are unique per integration (`enrollment/active-verified-enrollment-exists`), so `e2e` names each run, and it revokes the enrollment on the server at the end: the app's "remove" is local only (the Auth API has no device-side unenroll).
- Clean-start QR codes carry no `authUrl` (`EZKEY_QR_AUTH_BASE_URL` is empty by default), so the app asks for the server address; on the emulator it is `http://10.0.2.2:8080`.

- The local EzKey stack exposes the Auth API on `localhost:8080` and the Admin API on `localhost:9080` (EzKey `docs/LOCAL_STACK_PORTS.md`).
- `adb reverse tcp:8080 tcp:8080` lets the phone reach the Auth API as `http://localhost:8080`. The SDK's default URL policy allows plain HTTP only for `localhost`, `127.0.0.1` and `10.0.2.2`, so no policy change is needed and none may ship.
- Invitation QR codes may carry an `authUrl` pointing at the public address; in the lab, enroll with `authApiBaseUrlOverride` (or a QR without `authUrl`) set to `http://localhost:8080`.
- `authApiPublicBaseUrl` from signed `instance-info` is display metadata. The EzKey trace shows it differing from the URL the device actually called (public ngrok URL vs `localhost`); the SDK never reroutes to it, and neither may the app.

## Device verification (record results here)

| Check | Expected | Result |
| --- | --- | --- |
| Key generation tier on the Pixel 7 Pro | `strong` (StrongBox) | — |
| StrongBox unavailable path | Falls back to `standard` | Emulator `oa_api35` (Android 15, no StrongBox feature), 2026-10-27: `standard`; key generated, listed, deleted (`integration_test/ezkey/keystore_test.dart`) |
| Raw Keystore signatures | Verify with the public key; some are high-S, all normalize to low-S | Emulator, 2026-10-27: 16/16 verify, **8/16 high-S** (confirms G8), all normalized |
| Enroll + approve + deny against the local stack | Server accepts every device signature | Emulator, 2026-10-27 (#20): enroll + approve accepted (`ACCEPTED`) through the providers (`live_stack_test.dart`) and through the screens (`enrollment_ui_test.dart`, 8 screenshots); deny in slice 3 |
| Orphan key cleanup after storage recovery | `ezkey-device-*` aliases without a record are deleted | — |

## Findings fed back to EzKey

| Date | Finding | Where fixed |
| --- | --- | --- |
| 2026-10-27 | G8: Android Keystore high-S signatures rejected by the Auth API; SDK did not normalize key-store output | `ezkey_dart` 0.3.0 (mgagp/ezkey#1068 branch) |
| 2026-10-27 | G9: `EzkeyDeviceKeyStore.storageTier` is per store, but the tier is per key (StrongBox can be unavailable for one generation). Worked around by reporting the last generated key's tier, which the SDK reads right after generation. Suggested SDK change: return the tier from `generateKeyPair`. | Open (EzKey) |
| 2026-10-27 | Clean-start invitations have no `authUrl`, so every third-party app must ask the user for the server address; the reference app has a global default instead. Suggest documenting this in the SDK README §2.2 or defaulting `EZKEY_QR_AUTH_BASE_URL` in clean-start. | Open (EzKey, docs) |
| 2026-10-27 | `EzkeyEnrollmentStore.list()` cannot report unreadable records, while the contract's reference behaviour shows them as unusable (MOB-015). Worked around with `SecureEzkeyEnrollmentStore.unreadableLocalIds()`. | Open (EzKey, low) |

## Open points (this app)

- Accessibility: with semantics enabled, the EzKey screens trigger a framework assertion (`node.isMergedIntoParent`) in debug, after which taps reach stale forui tappables. `enrollment_ui_test.dart` runs with `semanticsEnabled: false` until this is understood (forui tile group / dialog, or our tree). To check with TalkBack before slice 4.
- The settings tile is verified by `flutter analyze` only: the UI test opens `EzkeyPage` directly, because the upstream intro (master password) blocks a fresh install.
