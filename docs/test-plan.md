# Test plan — Open Authenticator (fork)

Status: **draft v1 (2026-10-26)**, absolute angle only (the project for itself). A second pass will adjust it for the EzKey SDK integration, which gets its own plan.

## 1. Principles

- **Risk first.** In an authenticator, the worst failures are silent: a wrong code locks the user out of an account, and a broken decryption, backup or migration loses secrets. Tests go where a bug would be both likely and costly. UI polish comes last.
- **Proportional.** About 9.8k lines in `lib/model`, ~6k in `lib/widgets` + `lib/pages`. We aim for a small number of high-value tests per critical module, not coverage numbers.
- **Upstream alignment.** We test upstream code as it is, through its public API, without changing it to make it testable (see `CLAUDE.md`). When a seam is missing, the test is adapted or the gap is recorded here (§5).
- **Deterministic, host-only by default.** Tests run with `flutter test` on the dev machine (and later in CI): no network, no device, no real clock where it matters.
- **Accessibility through tests.** Screen-reader behaviour is checked with semantics-enabled widget tests (labels, actions, values), not by manual passes with TalkBack or VoiceOver.
- **No new test dependencies by default.** We use what is already resolved: `flutter_test`, `package:http/testing.dart` (`MockClient`), `fake_async`, `clock`, drift's in-memory database (`sqlite3` 3.x bundles its native library), and `SharedPreferences.setMockInitialValues`. Adding `mocktail` or similar is a decision to take with the user.

## 2. Test levels

| Level | Tooling | Used for |
|---|---|---|
| Unit (pure Dart) | `test`, `group`, `expect` | Value types, parsing, crypto, serialization |
| Integration (host) | drift `NativeDatabase.memory()`, fakes, `MockClient`, `ProviderContainer` with overrides | Repository, database, sync queue, settings, backend client |
| Widget | `testWidgets`, `pumpWidget` | A few critical screens/components (TOTP tile, add-TOTP form) |
| Device (manual for now) | debug build on the Pixel (`CLAUDE.md`, "Android device build") | Smoke test: launch, navigate, add a TOTP |

## 3. Map and priorities

Legend for effort: S < ½ day, M ≈ 1 day, L > 1 day.

### P1 — Core correctness (silent failures, pure logic)

| # | Target (`lib/…`) | What to test | Level | Effort |
|---|---|---|---|---|
| 1 | `model/totp/decrypted.dart` (`generator`, `generateCode`), `model/totp/algorithm.dart`, `model/totp/totp.dart` (defaults) | Our parameter mapping into `hashlib.TOTP`: base32 secret decoding, algorithm mapping (SHA1/256/512), digits, period, defaults. Code values against RFC 6238 vectors. | Unit | S |
| 2 | `model/app_links/otpauth_totp.dart` | `otpauth://totp/` parsing and building: issuer in label vs. `issuer=` param, URL encoding, missing/invalid secret, unknown algorithm, defaults, build → parse round trip. This is the import path for every QR code. | Unit | S |
| 3 | `model/crypto/` (`CryptoStore`, `DerivedKey`, `Salt`, `CryptoKey`) | AES-GCM encrypt → decrypt round trip; wrong key / tampered data → `null` (GCM authentication); `canDecrypt`; `checkPasswordValidity`; Argon2 derivation is deterministic for the same password + salt and differs otherwise. | Unit | S |
| 4 | `model/totp/json.dart`, `model/totp/totp.dart` | JSON round trip of `Totp` / `EncryptedData`; `tryFromJson` on malformed input; key names stable (shared with the backend and the backup format). | Unit | S |

### P2 — Persistence and data safety

| # | Target | What to test | Level | Effort |
|---|---|---|---|---|
| 5 | `model/database/` | Schema migration v1 → v2 with drift's schema tools (`drift_schemas/app/*.json` already exist; `drift_dev make-migrations` can generate the test scaffolding). Basic TOTP CRUD on an in-memory DB. | Integration | M |
| 6 | `model/backup/` (`store.dart`, `backup.dart`) | Create → restore round trip; wrong password → `InvalidBackupPasswordException`; corrupted file rejected; **a committed fixture backup file still restores**, which guards users' existing backups against format regressions. Note: `_create`/`_read` are private, so test through the store API with a temporary directory. | Integration | M |
| 7 | `model/totp/repository.dart` | Add / update / delete reach the DB; master-password change re-encrypts every TOTP, after which old-key decryption fails and new-key decryption works. Local storage only (no backend). | Integration | M |
| 8 | `model/settings/` | A primitive `SettingsEntry` load/save with mocked `SharedPreferences`; one non-primitive override; storage-type (local ↔ shared) migration logic in `storage_type.dart`, as far as it can run without a backend. | Integration | S–M |

### P3 — Synchronization and backend client

| # | Target | What to test | Level | Effort |
|---|---|---|---|---|
| 9 | `model/backend/synchronization/` (`queue.dart`, `push/operation.dart`, `push/result.dart`, `status.dart`) | Push queue: enqueue, ordering, persistence in the DB, retry/clear after a result. Pull merge behavior if it is isolated enough. | Integration | M–L |
| 10 | `model/backend/request/` (`request.dart`, `response.dart`, `error.dart`) | Request building and response/error parsing against `MockClient`: success, typed errors, HTTP failures, malformed JSON. | Unit/Integration | M |
| 11 | `model/backend/authentication/` (`session.dart`, providers) | Session persistence and refresh decisions, with a mocked HTTP layer. Native web auth flows are out of scope. | Integration | M |

### P4 — App behavior and UI (few, targeted)

| # | Target | What to test | Level | Effort |
|---|---|---|---|---|
| 12 | `model/app_links/` (`openauthenticator.dart`, `listener.dart`) | Deep-link routing: which handler a URI goes to. | Unit | S |
| 13 | `model/app_unlock/`, `model/password_verification/` | Unlock state machine for the master-password method; password-signature verification. `local_auth` is platform-bound and out of scope. | Unit/Integration | S–M |
| 14 | `utils/` (`uri_builder.dart`, `debounce.dart`, `result/handler.dart`) | Small utilities. Use `fake_async` for debounce. | Unit | S |
| 15 | `widgets/totp/` | The TOTP tile shows the code and the countdown for a known secret; the add-TOTP form validates its input. | Widget | M |

### Out of scope for now

- `model/purchases/` (RevenueCat, platform SDKs and REST client).
- `model/migrator/` (legacy Firebase migration, slated for removal upstream).
- Pages and dialogs beyond #15, golden-image tests, platform plugins (`local_auth`, `window_manager`, camera scanning).
- Device automation (`integration_test`, Maestro): revisit after P2. The manual device smoke test covers launch and navigation meanwhile.

## 4. Sequencing

1. **Lot 1 — P1 (#1–#4)**: four test files, pure Dart, fast. Each can be a test-only PR (Claude-mergeable when green).
2. **CI**: done in #75 (`.github/workflows/ci.yml`, described in `CLAUDE.md`). It runs the checks and the tests, and builds every platform.
3. **Lot 2 — P2 (#5–#8)**: introduces the shared test helpers (in-memory DB, fake secure storage, `ProviderContainer` setup) under `test/helpers/`.
4. **Lot 3 — P3**, then **P4** as needed.

## 5. Known constraints and open points

- **TOTP time is not injectable.** `hashlib.TOTP` reads `DateTime.now()`, and `DecryptedTotp` exposes no time parameter. Plan: test our mapping into the generator, and check codes against RFC 6238 vectors using hashlib's lower-level primitives at a fixed counter. `hashlib`'s own correctness is its maintainers' responsibility.
- **Generated `lib/app.dart`** (e.g. `Argon2Parameters`) must exist before tests compile. CI and fresh clones need the codegen steps first.
- **Argon2 cost.** If the production parameters make key derivation slow, crypto tests derive a key once per file (`setUpAll`).
- **Secure storage** (`simple_secure_storage`) is a platform plugin. Repository-level tests need a fake through provider overrides, which needs confirming in Lot 2.
- **Private APIs** (`Backup._create/_read`, …) are tested through their public callers only.
- **Backups, two upstream quirks pinned or noted, not fixed** (#55): `BackupStore.import` fails with a `FileSystemException` while no backup was ever made, because `BackupPath.create` does not create the backups directory (pinned in `test/model/backup/backup_test.dart`). The backup file-name regex is not anchored, so a file such as `1700000000000.bak.tmp` in the backups directory makes the listing throw in `int.parse`, and Riverpod keeps retrying it (noted only: a test would hang).
- **Deep-link routing** lives in the private `_RouteWidgetState` in `lib/main.dart`: it handles `openauthenticator://` and `otpauth://totp/` links, once each through `consumeLink`, and ignores the others. It cannot be reached without the whole app, so `test/model/app_links/` pins the link types and the listener only (#55).
- **QR scanner** (`pages/scan.dart`): the camera is out of scope, but the page's decision is not. `test/pages/scan_test.dart` calls the `QrCodeScanner.onScan` callback with the scanned content and pins what follows: a valid `otpauth` URI opens the TOTP page (its label keeps the `Issuer:` prefix of the URI path), anything else shows `error.scan.noUri` and resumes scanning, EzKey invitations included (#64, before harmonization H6). Without a camera the scanner placeholder spins forever, so these tests pump fixed durations instead of `pumpAndSettle`.
- **Core upstream tests, seams used** (#76): the database and repository tests open upstream's own `AppDatabase()` in a temporary directory by mocking path_provider's channel (`getApplicationSupportDirectory`, `getTemporaryDirectory`). The settings tests swap `SharedPreferencesAsyncPlatform.instance` for the in-memory store, with `currentPlatform = .android`. The repository tests hold the salt and the derived key in memory instead of the secure storage plugin. Not covered yet: the backup that `changeMasterPassword` can take first, and a storage-type change to `shared`, which needs the backend and password verification (P3).

## 6. Full round (every platform)

One checklist for the whole app, run on each platform and deployment model upstream ships (#139). Android is the reference (#131); Windows (#132), macOS and the iOS simulator (#136) and Linux (#138) reuse it. Unit and widget tests (`flutter test`) stay the first line; this round checks the real app on a real target.

**How:** `auto` = an automated test on the target (`flutter test`, `integration_test/`); `emu` = by hand on the Android emulator, with screenshots; `device` = by hand on a physical device (the Pixel needs the user's go-ahead, debug build only, no build-type switch). On desktop, "by hand" means the app run with `flutter run -d <platform>`.

**Result cells:** `pass` / `fail #n` (the issue) / `n/a` (not offered on that platform) / `—` (not run yet) / `blocked` (with the reason in the notes), followed by the date (MM-DD, 2026).

### Upstream features

| # | Check | How (Android) | Android | Windows | macOS | iOS sim | Linux |
|---|---|---|---|---|---|---|---|
| U1 | First launch: intro slides, master password set, home empty | emu | pass 11-13 | — | — | — | — |
| U2 | Add a TOTP by camera scan of an `otpauth://` QR | device | — | — | — | — | — |
| U3 | Add a TOTP by hand (secret, issuer, label, algorithm, digits, period) | emu | pass 11-13 | — | — | — | — |
| U4 | Add a TOTP from an `otpauth://` link opened from outside the app | emu (`adb shell am start -d`) | pass 11-13 | — | — | — | — |
| U5 | The code shown matches a reference generator, and the countdown rolls over | emu | pass 11-13 | — | — | — | — |
| U6 | Copy a code (tap, copy button setting) | emu | pass 11-13 | — | — | — | — |
| U7 | Edit a TOTP, then delete it | emu | pass 11-13 | — | — | — | — |
| U8 | Search (button setting, filter) | emu | pass 11-13 | — | — | — | — |
| U9 | Settings: theme, language, display options persist after a restart | emu | — | — | — | — | — |
| U10 | Change the master password; the TOTPs still decrypt | emu | pass 11-13 | — | — | — | — |
| U11 | App unlock: master password at start, wrong then right password | emu | pass 11-13 | — | — | — | — |
| U12 | App unlock: biometric / system authentication | device | — | — | — | — | — |
| U13 | Backup now, then restore it after deleting a TOTP; wrong backup password refused | emu | pass 11-13 | — | — | — | — |
| U14 | Manage backups: list, delete | emu | — | — | — | — | — |
| U15 | Clear data: everything gone, back to the intro | emu | — | — | — | — | — |
| U16 | Account sign-in (email link or a provider) and synchronization with the official backend | device | — | — | — | — | — |
| U17 | `openauthenticator://` link handling (debug "Input link" entry) | emu | — | — | — | — | — |
| U18 | Contributor Plan screen opens (no purchase) | emu | — | — | — | — | — |
| U19 | App restart keeps the TOTPs and settings | emu | pass 11-13 | — | — | — | — |

### EzKey (where `ezkeySupportedPlatforms` offers it)

| # | Check | How (Android) | Android | Windows | macOS | iOS sim | Linux |
|---|---|---|---|---|---|---|---|
| E1 | Key store contract (`keystore_test.dart`), tier read back from the key | auto | — | — | — | — | — |
| E2 | Enroll, check, approve through the providers against the live stack (`live_stack_test.dart`) | auto | — | — | — | — | — |
| E3 | Enroll and approve through the screens (`enrollment_ui_test.dart`) | auto | — | — | — | — | — |
| E4 | Enroll by camera scan of the invitation QR | device | — | — | — | — | — |
| E5 | Approve with local confirmation; cancelled confirmation sends nothing; deny | device | — | — | — | — | — |
| E6 | Home zones: EzKey zone collapsed until the first enrollment, collapse, split | emu | — | — | — | — | — |
| E7 | Enrollment page, identity shown, removal | emu | — | — | — | — | — |
| E8 | Backup keeps the enrollment inventory; restore lists "to re-enroll" | emu | — | — | — | — | — |
| E9 | Clear data warns about enrollments and deletes their keys | emu | — | — | — | — | — |
| E10 | HTTPS-only server rule in a profile build | emu (profile) | — | — | — | — | — |
| E11 | EzKey hidden where it is not offered: the app is upstream's | — | n/a | — | — | — | — |

### Deployment models

| Platform | Upstream's package | What this fork can check |
|---|---|---|
| Android | Play Store APK / AAB, signed by upstream | Debug and profile APKs; release needs upstream's key |
| Windows | MSIX (Microsoft Store), `protocol_activation` registers the link schemes | Debug `.exe`; an MSIX signed with a local test certificate (#132) |
| macOS, iOS | App Store, upstream's Apple team | Debug builds, locally signed or unsigned (#135, #136) |
| Linux | Flatpak (Flathub), Snap | To decide (#138) |

### Notes per run

Record one dated paragraph per platform run: build, target, what was automated, failures with their issues, items left `—` and why.

**Android, emulator `oa_api35`, 2026-11-13 (in progress, #131).** Debug APK from `main` at 1104bf9, fresh install, driven with `adb` (taps, `uiautomator dump` for node labels, screenshots). Codes checked against an independent RFC 6238 computation from the emulator's clock: SHA1 6 digits (`otpauth://` link) and SHA256 8 digits (manual entry), across a 30 s rollover. Backup restored after deleting a TOTP; a wrong backup password shows "Invalid password entered". Master password changed, then "Save encryption / decryption key" turned off: at the next start the app asks for the password, refuses the old and a wrong one, and the new one decrypts both TOTPs.

Observations, not failures:
- The same `otpauth://` link sent twice in one app session does nothing the second time: upstream consumes each link once (`AppLinksListener.consumeLink`). Use a different link for each try.
- The label keeps the `Issuer:` prefix of the link's path (`RoundTest:bob@example.com`), as already pinned by `test/pages/scan_test.dart`.
- Upstream's success and error toasts stay about 1 s; take the screenshot within a second.
- Tooling: `uiautomator dump` fails on the home screen (the countdown animation never lets the screen go idle), so check it with screenshots. The emulator (37.2.12, `swiftshader_indirect`) crashed twice with exit 139 and nothing in its log; the app's data survived each restart.
