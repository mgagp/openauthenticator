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
| Native key store | `packages/ezkey_keystore/` (ADR-0001 D2) | Android Keystore P-256 keys, StrongBox preference, tier, orphan-key listing |
| App integration | `lib/ezkey/` (ADR-0001 D3) | `EzkeyDeviceKeyStore` / `EzkeyEnrollmentStore` adapters, providers, screens, local copy |
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
| §7 Error copy from `type` / status, never `detail` | MUST NOT | App | Map `EzkeyProblemKind` to `slang` strings | — | Slices 2–3 |
| §8 Lifetime bounds (15–120 s) | MUST (server) | SDK | `maxAuthAttemptTtl`, advisory expiry | SDK tests | Done in SDK |

## Upstream files touched

Cumulative ledger (ADR-0001 D3). Every entry names the PR and why the hook could not live in a new file.

| File | Change | PR |
| --- | --- | --- |
| `pubspec.yaml`, `pubspec.lock` | `ezkey_dart` git dependency, `ezkey_keystore` path dependency | Slice 1 |

## Lab setup (Pixel against the local stack)

- The local EzKey stack exposes the Auth API on `localhost:8080` and the Admin API on `localhost:9080` (EzKey `docs/LOCAL_STACK_PORTS.md`).
- `adb reverse tcp:8080 tcp:8080` lets the phone reach the Auth API as `http://localhost:8080`. The SDK's default URL policy allows plain HTTP only for `localhost`, `127.0.0.1` and `10.0.2.2`, so no policy change is needed and none may ship.
- Invitation QR codes may carry an `authUrl` pointing at the public address; in the lab, enroll with `authApiBaseUrlOverride` (or a QR without `authUrl`) set to `http://localhost:8080`.
- `authApiPublicBaseUrl` from signed `instance-info` is display metadata. The EzKey trace shows it differing from the URL the device actually called (public ngrok URL vs `localhost`); the SDK never reroutes to it, and neither may the app.

## Device verification (record results here)

| Check | Expected | Result |
| --- | --- | --- |
| Key generation tier on the Pixel 7 Pro | `strong` (StrongBox) | — |
| StrongBox unavailable path | Falls back to `standard`, enrollment succeeds | — |
| Enroll + approve + deny against the local stack | Server accepts every device signature | — |
| Orphan key cleanup after storage recovery | `ezkey-device-*` aliases without a record are deleted | — |

## Findings fed back to EzKey

| Date | Finding | Where fixed |
| --- | --- | --- |
| 2026-10-27 | G8: Android Keystore high-S signatures rejected by the Auth API; SDK did not normalize key-store output | `ezkey_dart` 0.3.0 (mgagp/ezkey#1068 branch) |
