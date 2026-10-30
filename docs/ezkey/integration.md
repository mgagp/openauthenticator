# EzKey integration — design notes

Living design document for #16. It records how Open Authenticator meets the EzKey client contract and what it changes in upstream files. Protocol and behaviour rules are **not** restated here: they live in the EzKey repository (`mgagp/ezkey`), linked below. Decisions with trade-offs are ADRs ([0001](../adr/0001-ezkey-integration-divergence.md), [0002](../adr/0002-ezkey-key-and-secret-storage.md), [0003](../adr/0003-ezkey-on-the-home-screen.md)).

## Sources (EzKey repo)

| Source | Canonical for |
| --- | --- |
| `docs/CLIENT_BEHAVIOUR_CONTRACT.md` | What any client MUST / SHOULD / MAY do between API calls |
| `ezkey_dart/README.md` | SDK API, storage hooks, integration pitfalls |
| `docs/MOBILE_DEVELOPER_GUIDE.md` | Wire protocol, signed payloads, problem types |
| `ezkey_mobile/docs/MOBILE_APP_STATE_MACHINE.md`, `MOBILE_SCREENS_AND_WIREFLOWS.md`, `MOBILE_POSITIONING.md` | Reference app behaviour, screens and naming vocabulary (inspiration for slices 2–3, not obligations) |
| `product-docs/global/architecture-decisions.md` ADR-0002 | User-initiated pending checks only: no push, no background or automatic polling (not stated in the contract, see findings) |
| `ezkey_mobile/docs/MOBILE_DATA_MODEL.md` § Installation Trust Zone, `ezkey_mobile/app/utils/{tenantGrouping,enrollmentDisplay}.ts` | Trust zones and enrollment grouping on the reference app's home screen (to adopt gradually, #26) |
| `sites/ezkey-org/technical-trace-ezkey-enrollment-authentication.html` | One complete real exchange (enroll, instance-info, pending, respond) with actual values |

## Layers

| Layer | Location | Owns |
| --- | --- | --- |
| SDK | `ezkey_dart` (git dependency, ADR-0001 D1) | Protocol, signatures and checks, decision lock, error classification, low-S normalization |
| Native key store | `packages/ezkey_keystore/` (ADR-0001 D2) | Android Keystore P-256 keys, StrongBox preference, tier, alias listing. Channel `org.ezkey.keystore`; no dependency on `ezkey_dart`, so it can move to EzKey as is |
| App integration | `lib/ezkey/` (ADR-0001 D3) | `device_key_store.dart` (adapter + app-owned alias format `ezkey-device-<id>-<random>`), `enrollment_store.dart` (one secure-storage entry per record, unreadable records reported), `orphan_keys.dart`; `providers.dart` (Riverpod wiring; orphan cleanup runs once when the authenticator is first built, before any enrollment), `messages.dart` (error copy), `pages/` (EzKey list with "check for requests", scan, confirm + code, approval), `local_confirmation.dart` (Approve-only prompt), `home_zone.dart` (home-screen EzKey zone, ADR-0003; collapsible, #36), `home_zone_state.dart` (remembered expanded / collapsed choice), `actions.dart` (add and check actions shared by the home zone and the EzKey page), `installations.dart` (enrollments grouped by installation), `widgets/enrollment_tile.dart` (the one enrollment row), `toast.dart` (EzKey toasts: blue success, 4 s), `about.dart` ("About EzKey": what it is, links to ezkey.org and the source code; EzKey is little known). Strings: `lib/i18n/{en,fr}/ezkey.json` (slang namespace `ezkey`; other locales fall back to English) |
| Upstream hooks | Ledger below | Entry points only |

## Contract conformance

One row per contract rule that applies to this app. "SDK" means `ezkey_dart` enforces it; "App" means our code must, with the test that proves it. Filled in as slices land.

| Contract rule | Level | Owner | How | Proof | Status |
| --- | --- | --- | --- | --- | --- |
| §1.1 Pending is a one-shot claim | MUST (server) | SDK + App | SDK returns the claimed attempt once; the app claims on user action only ("check for requests") and keeps it in memory on `EzkeyApprovalPage` until decided | Pixel pilot | Basic (#22) |
| EzKey ADR-0002: pending checks on explicit user action only | MUST (ADR; not in the contract) | App | `checkPending` runs only from a "check for requests" tap (home zone or EzKey page), which checks every enrollment in turn and opens the first claimed attempt; no `pollPending` / `watchPending`, no check on app resume, no notification | — | Done (#22) |
| §1.2 No context before the pending signature verifies; no refusal on fail-closed | MUST NOT | SDK + App | SDK throws `EzkeyIntegrityException`; the app shows a neutral error (`attempt.integrity`) and sends nothing | `test/ezkey/messages_test.dart` | Done (#22) |
| §1.3 No device countdown as a security control | MUST NOT | App | No timer UI; `isCertainlyExpired` only stops a decision on a stale prompt | — | Done (#22) |
| §2 Decision lock, unknown outcome | MUST / SHOULD | SDK | `PendingAuthAttempt.decisionState`, `EzkeyRespondOutcomeUnknownException` (SDK 0.3.0 tests) | SDK tests, `messages_test.dart` | Done in SDK; basic app UI (#22): buttons follow `canDecide`, uncertain outcome shown as such, page closes once locked |
| §3 Leave-as-deny, permanent line, no retry loop | SHOULD | App | `PopScope` on `EzkeyApprovalPage` sends `deny` once when the attempt is still `canDecide` (not when certainly expired); navigation is never held, a failure shows one toast and is not retried; the page always shows "leaving declines" | `test/ezkey/pages/approval_page_test.dart` | Done (#24) |
| §4 Local confirmation on Approve only | SHOULD | App | App-level prompt (ADR-0002 decision 2): `confirmEzkeyApproval` (`local_auth`, device credential or biometric) before Approve only; a cancelled prompt sends nothing and keeps the attempt open. Applies whenever the device has a screen lock (no per-enrollment policy in the protocol yet); without one, Approve proceeds | `approval_page_test.dart` | Done (#24) |
| §5 409 conflict / expired are final | MUST | SDK + App | `isAttemptNoLongerActionable` → neutral "no longer active" message, page closes | `messages_test.dart` | Done (#22) |
| §6 Result signature before showing the outcome | MUST | SDK | Integrity check; attempt locked | SDK tests | Done in SDK |
| §7 Error copy from `type` / status, never `detail` | MUST NOT | App | `ezkeyEnrollmentErrorMessage` maps exception type and `EzkeyProblemKind` to `ezkey` strings | `test/ezkey/messages_test.dart` | Done: enrollment (#20), approvals (`ezkeyAttemptErrorMessage`, #22) |
| §8 Lifetime bounds (15–120 s) | MUST (server) | SDK | `maxAuthAttemptTtl`, advisory expiry | SDK tests | Done in SDK |

## Upstream files touched

Cumulative ledger (ADR-0001 D3, refined by ADR-0003 D4). Every entry names the PR, why the change could not live in a new file, and is precise enough to re-apply. On an upstream sync that conflicts with an entry, take upstream's version, re-apply the entry, and run the checks.

| File | Change | PR |
| --- | --- | --- |
| `pubspec.yaml`, `pubspec.lock` | `ezkey_dart` git dependency (pinned commit), `ezkey_keystore` path dependency; the lock only gains `ezkey_dart`, `ezkey_keystore`, `cryptography`, `pointycastle`, `unorm_dart` | Slice 1 (#16) |
| `pubspec.yaml`, `pubspec.lock` | `integration_test` (`sdk: flutter`) in `dev_dependencies` for on-device tests; the lock gains SDK packages only (`integration_test`, `flutter_driver`, …) | Slice 1 (#16) |
| `lib/pages/settings/page.dart` | ~~One import and one Android-only tile (`EzkeySettingsEntryWidget`) in the Security group~~. Removed in #28: the file is identical to upstream again | Slice 2 (#20), removed #28 |
| `lib/pages/home/page.dart` | One import (`ezkey/home_zone.dart`), and the list returned by the `AppScaffold.asyncValue` builder wrapped in `ezkeyHomeZones([...])` (2 lines: `return [` → `return ezkeyHomeZones([`, `];` → `]);`). The builder's result is the only place that holds both the TOTP content and its floating button. **Re-apply:** take upstream's file, add the import, wrap the builder's returned list. Off Android the function returns the list unchanged | #28 (ADR-0003) |
| `assets/svg/ezkey_logo.svg` | New file (no upstream file changed): EzKey's `logo.svg`, compiled by upstream's `compile_svg` into the gitignored `assets/images/ezkey_logo.si`, a folder `pubspec.yaml` already declares | #28 |
| `lib/i18n/en/ezkey.json`, `lib/i18n/fr/ezkey.json` | New files (no upstream file changed): slang only reads translations from `lib/i18n/` | Slice 2 (#20) |

## Lab setup (Pixel against the local stack)

`scripts/ezkey_lab.dart` drives a running clean-start stack (#20):

```sh
scripts/with-env.sh dart scripts/ezkey_lab.dart invite                 # prints the QR content and the 6-digit code
scripts/with-env.sh dart scripts/ezkey_lab.dart attempt <enrollmentId> # creates an auth attempt, waits for the decision
scripts/with-env.sh dart scripts/ezkey_lab.dart e2e --test integration_test/ezkey/enrollment_ui_test.dart   # emulator, screenshots in build/ezkey-lab/screens/
```

- Admin API access: the script logs in as `admin.docker` and approves that login itself through the Demo Device web form (`localhost:8083`), then caches the token and one Integration API key per integration (the attempt command uses the key of the enrollment's own integration) under the gitignored `build/ezkey-lab/`. Lab only.
- It creates the integration `oa-lab` ("Open Authenticator Lab") on first use. Active enrollment names are unique per integration (`enrollment/active-verified-enrollment-exists`), so `e2e` names each run, and it revokes the enrollment on the server at the end: the app's "remove" is local only (the Auth API has no device-side unenroll).
- Clean-start QR codes carry no `authUrl` (`EZKEY_QR_AUTH_BASE_URL` is empty by default), so the app asks for the server address; on the emulator it is `http://10.0.2.2:8080`.

- The local EzKey stack exposes the Auth API on `localhost:8080` and the Admin API on `localhost:9080` (EzKey `docs/LOCAL_STACK_PORTS.md`).
- `adb reverse tcp:8080 tcp:8080` lets the phone reach the Auth API as `http://localhost:8080`. The SDK's default URL policy allows plain HTTP only for `localhost`, `127.0.0.1` and `10.0.2.2`, so no policy change is needed and none may ship.
- Invitation QR codes may carry an `authUrl` pointing at the public address; in the lab, enroll with `authApiBaseUrlOverride` (or a QR without `authUrl`) set to `http://localhost:8080`.
- `authApiPublicBaseUrl` from signed `instance-info` is display metadata. The EzKey trace shows it differing from the URL the device actually called (public ngrok URL vs `localhost`); the SDK never reroutes to it, and neither may the app.

### Pixel pilot (debug build, local stack through ngrok)

First run on 2026-10-28 (#22). The debug build replaces the app in place (same debug key, data kept); the user drives the screens, the logs give the root cause when something fails.

```sh
scripts/with-env.sh flutter build apk --debug --target-platform android-arm64
adb -s <pixel> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <pixel> logcat -c; adb -s <pixel> logcat -v threadtime > pixel-logcat.txt   # background; the app logs `I flutter : EzKey ...`
docker logs -f --since 1m ezkey-auth-api > auth-api.log                            # background; server side of the same calls
```

- Server address: the stack's public HTTPS tunnel (ngrok to `localhost:8080`) is the closest to production and needs no adb. `adb reverse` (above) is the fallback without a tunnel. A free ngrok tunnel shows a browser warning page only to browsers; the SDK's `dart:io` client gets the API answer.
- The app logs one line per claim, decision and failure (the SDK's `toString()`, which never contains tokens or keys). Keep the capture files outside the repository.
- StrongBox use shows in logcat as `keymint-service.citadel` / `citadeld` lines (Titan M2) when the key is created; a TEE key does not touch them.

## Device verification (record results here)

| Check | Expected | Result |
| --- | --- | --- |
| Key generation tier on the Pixel 7 Pro | `strong` (StrongBox) | Pixel 7 Pro (Android 17), 2026-10-28: key created through the Titan M2 (`keymint-service.citadel: Self-signed attestation requested`) during enrollment, so StrongBox. 2026-10-28 (#24): both enrollment tiles show "Isolation forte" (`strong`) |
| StrongBox unavailable path | Falls back to `standard` | Emulator `oa_api35` (Android 15, no StrongBox feature), 2026-10-27: `standard`; key generated, listed, deleted (`integration_test/ezkey/keystore_test.dart`) |
| Raw Keystore signatures | Verify with the public key; some are high-S, all normalize to low-S | Emulator, 2026-10-27: 16/16 verify, **8/16 high-S** (confirms G8), all normalized |
| Enroll + approve + deny against the local stack | Server accepts every device signature | Emulator, 2026-10-27 (#20): enroll + approve accepted (`ACCEPTED`) through the providers (`live_stack_test.dart`) and through the screens (`enrollment_ui_test.dart`, 8 screenshots); deny in slice 3. Pixel 7 Pro through ngrok HTTPS, 2026-10-28 (#22): enrollment by QR scan (`VERIFIED`), then one approval (`approved`) and one denial (`denied`) through the screens, attempts created from the Admin UI; no error in logcat or in the Auth API log |
| Approval refinements (#24) | Approve asks for a local confirmation; a cancelled confirmation sends nothing; leaving undecided denies once; challenge code checked by the server | Pixel 7 Pro through ngrok HTTPS, 2026-10-28, attempts from the Admin UI ("Test authentication"): fingerprint then `approved` with the right code (19) and `failed` with a wrong one (22, server: challenge validation failed); plain Deny without a prompt (20, 23); back without deciding sent one `denied` (21); fingerprint cancelled (`userCanceled`), nothing sent, then Deny sent `denied` (24) |
| Orphan key cleanup after storage recovery | `ezkey-device-*` aliases without a record are deleted | — |

## Findings fed back to EzKey

Kept in two lists so the EzKey follow-ups stay separate from this app's integration work. Documentation findings are about **discoverability**: a third-party integrator reads the contract and the SDK README first, so rules that live only in ADRs or in `ezkey_mobile` are easy to miss. Record them here; refactoring EzKey's documentation is out of scope for this fork.

### EzKey documentation

| Date | Finding | Suggested action | Status |
| --- | --- | --- | --- |
| 2026-10-27 | Clean-start invitations have no `authUrl`, so every third-party app must ask the user for the server address; the reference app has a global default instead | Document it in the SDK README §2.2, or default `EZKEY_QR_AUTH_BASE_URL` in clean-start | Open |
| 2026-10-29 | **No push by design** (ADR-0002, user-initiated pending only) is absent from `CLIENT_BEHAVIOUR_CONTRACT.md`. The SDK README contradicts it: it suggests checking "when the app returns to the foreground, or with `pollPending` / `watchPending` while an approvals screen is visible", says "no push channel *yet*", and lists it under limitations rather than as a security choice. This led this fork to propose notifications. | Add a MUST NOT to the contract citing ADR-0002 (as the integration-kit vision note already asks); align the README wording | Open |
| 2026-10-29 | Trust zones (installation = normalized Auth URL), tenant groups and the admin / regular distinction are documented only in `ezkey_mobile`; the contract, the SDK README and the vision note do not point a third-party app to them (#26) | A short "presenting enrollments" section in the SDK README linking to `MOBILE_DATA_MODEL.md` | Open |
| 2026-10-29 | `CLIENT_BEHAVIOUR_CONTRACT.md` § "Known gap" and `MOBILE_DEVELOPER_GUIDE.md` (known-gap note, `auth/internal-error` row) still say the Dart SDK does not lock on lost `respond` transport or ambiguous 5xx; SDK 0.3.0 does (decision lock, unknown outcome) | Update both once mgagp/ezkey#1068 merges | Open |

### EzKey SDK (`ezkey_dart`)

| Date | Finding | Suggested action | Status |
| --- | --- | --- | --- |
| 2026-10-27 | G8: Android Keystore high-S signatures rejected by the Auth API; the SDK did not normalize key-store output | — | Fixed in `ezkey_dart` 0.3.0 (mgagp/ezkey#1068 branch) |
| 2026-10-27 | G9: `EzkeyDeviceKeyStore.storageTier` is per store, but the tier is per key (StrongBox can be unavailable for one generation). Worked around by reporting the last generated key's tier, which the SDK reads right after generation | Return the tier from `generateKeyPair` | Open |
| 2026-10-27 | `EzkeyEnrollmentStore.list()` cannot report unreadable records, while the contract's reference behaviour shows them as unusable (MOB-015). Worked around with `SecureEzkeyEnrollmentStore.unreadableLocalIds()` | Let `list()` report unreadable records | Open (low) |
| 2026-10-29 | `pollPending` / `watchPending` offer automatic polling that EzKey ADR-0002 rejects for the mobile path | Restrict or document them as non-mobile (lab, CLI) helpers | Open |

## Open points (this app)

- Accessibility: with semantics enabled, the EzKey screens trigger a framework assertion (`node.isMergedIntoParent`) in debug, after which taps reach stale forui tappables. `enrollment_ui_test.dart` runs with `semanticsEnabled: false` until this is understood (#30).
- A claimed attempt lives only in memory: if the app dies before the decision, it simply expires (leave-as-deny cannot run).
- Home-screen entry: ADR-0003, phase 1 built in #28. Collapsible since #36, as a courtesy to upstream: collapsed to a thin bar (the upstream screen without a frame) until the first enrollment, then the user's last choice is remembered. Follow-ups: per-enrollment detail page and check (#33), adjustable split between the zones (#32), display concepts (#26).
- Difference from the EzKey reference app, kept on purpose (user, 2026-10-30): one "check for requests" tap checks **every** enrollment, since an EzKey user has few. The user may bring it to `ezkey_mobile`.
- Approval confirmation is always on since #24, beyond contract §4 and ADR-0002 D2 ("when enabled"); a Standard-by-default setting like the reference app is #34.
- Toasts: upstream toasts close after 1 s; EzKey toasts stay 4 s (Material guidance: 4–10 s). forui keeps every toast until closed while Android reports accessible navigation, e.g. with a dictation app's accessibility service on (Wispr Flow on the dev Pixel).
- `ezkey_dart` is pinned to a branch commit until mgagp/ezkey#1068 merges (#29).
- Each enrollment tile shows where its key lives, from the tier recorded at enrollment, with the Admin UI's platform-neutral labels ("Strong isolation", "Hardware-backed", "Not hardware-protected") (#24).
- `enrollment_ui_test.dart` approves through the screens (`ezkey-check-pending`, `ezkey-attempt-approve`); it passed on the emulator in #24 (`ACCEPTED`, 10 screenshots).
- The home-zone hook is verified by widget tests and on the Pixel only: the UI test opens `EzkeyPage` directly, because the upstream intro (master password) blocks a fresh install.
