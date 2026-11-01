# Test plan — Open Authenticator (fork)

Status: **draft v1 (2026-10-26)**, absolute angle only (the project for itself). A second pass will adjust it for the EzKey SDK integration, which gets its own plan.

## 1. Principles

- **Risk first.** In an authenticator, the worst failures are silent: a wrong code locks the user out of an account, and a broken decryption, backup or migration loses secrets. Tests go where a bug would be both likely and costly. UI polish comes last.
- **Proportional.** About 9.8k lines in `lib/model`, ~6k in `lib/widgets` + `lib/pages`. We aim for a small number of high-value tests per critical module, not coverage numbers.
- **Upstream alignment.** We test upstream code as it is, through its public API, without changing it to make it testable (see `CLAUDE.md`). When a seam is missing, the test is adapted or the gap is recorded here (§5).
- **Deterministic, host-only by default.** Tests run with `flutter test` on the dev machine (and later in CI): no network, no device, no real clock where it matters.
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
2. **CI** right after Lot 1: a GitHub Actions workflow that uses `.flutter-version`, runs `pub get --enforce-lockfile`, the codegen steps, `flutter analyze`, the scoped format check and `flutter test`. It is a fork-only file, but needs the `Workflows` token permission.
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
