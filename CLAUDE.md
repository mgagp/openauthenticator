# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Open Authenticator: a cross-platform (Android, iOS, Windows, macOS, Linux) Flutter TOTP app with optional sync to a self-hostable backend (separate repo: `openauthenticator-app/backend`). This checkout is a fork of `Skyost/OpenAuthenticator`.

## Toolchain (machine-specific paths)

Toolchain locations are not hardcoded. They live in `dev-env.local` at the repo root (gitignored; copy `dev-env.example`), which sets `JAVA_HOME` (JDK 17 — the Android build targets Java 17; JDK 21 also works) and optionally `FLUTTER_ROOT`. Run Flutter/Gradle commands through the wrapper so the right JDK is used instead of whatever `java` is first on `PATH`:

```sh
scripts/with-env.sh flutter doctor -v        # Git Bash / POSIX
scripts\with-env.ps1 flutter build apk       # PowerShell
scripts/with-env.sh                          # no args: print resolved JAVA_HOME / java / flutter / dart
```

Flutter does not honor `JAVA_HOME` when Android Studio's bundled JBR is installed (its `flutter config --jdk-dir` setting wins), so the wrapper also syncs that user-global setting to `JAVA_HOME`. Do not search the filesystem for a JDK; read `dev-env.local`. If it is missing, ask the user for the paths.

### Decision: desktop targets disabled (Android is the primary target)

- **Decision** (issue #3, 2026-10-26): the Windows desktop target is out of scope for now (no Visual Studio needed), and Linux cannot be built on the Windows dev machine anyway. Both are disabled in Flutter's user-global config: `flutter config --no-enable-windows-desktop --no-enable-linux-desktop`.
- **Why**: when a project has a `windows/` or `linux/` folder *and* that desktop target is enabled (the default in current Flutter), every `flutter pub get` creates `<platform>/flutter/ephemeral/.plugin_symlinks/` — symlinks the CMake build uses to reach native plugin code (`flutter_tools/lib/src/flutter_plugins.dart`, `createPluginSymlinks`). Windows only lets a non-admin create symlinks in Developer Mode, so `pub get` failed with "Building with plugins requires symlink support" (`ERROR_PRIVILEGE_NOT_HELD`). Android/iOS never need these symlinks. Disabling the unused targets avoids changing a system security setting.
- **Consequence**: `windows/` and `linux/` stay in the repo untouched but are ignored by the tooling; `flutter build windows|linux` and those devices are unavailable. The setting is per user account, so it affects every Flutter project on the machine. `flutter doctor` still reports Visual Studio as missing — expected.
- **To re-enable** (when Windows becomes a target): enable Windows Developer Mode (`start ms-settings:developers`) or work from an elevated terminal, install Visual Studio with the "Desktop development with C++" workload, run `flutter config --enable-windows-desktop` (and/or `--enable-linux-desktop`), then `flutter pub get` and `flutter doctor`. Update this section.

## Setup and generated files

A fresh clone does not compile until the gitignored generated files exist (`lib/app.dart`, `**/*.g.dart`, `assets/images/**/*.si`):

```sh
flutter pub get
dart run open_authenticator:compile_svg                    # SVG assets -> .si (jovial_svg)
dart run build_runner build --delete-conflicting-outputs   # drift (database.g.dart) and other *.g.dart
dart run slang                                             # lib/i18n/**/*.json -> lib/i18n/translations.g.dart
dart run open_authenticator:generate                       # writes lib/app.dart (App.appName, backend URL, Sentry DSN, RevenueCat keys...)
flutter run
```

- **Pinned toolchain and dependencies** (issue #6, a fork-only divergence: upstream gitignores the lock). Goal: reproducible builds and non-flaky tests.
  - `pubspec.lock` is versioned. `flutter pub get` keeps it unchanged unless `pubspec.yaml` changes; use `flutter pub get --enforce-lockfile` to verify that.
  - `.flutter-version` holds the reference Flutter version (currently 3.47.8 / Dart 3.13.7). `scripts/with-env.*` warn when the active SDK differs. The lockfile only records an SDK floor (in practice **Dart ≥ 3.13 / Flutter ≥ 3.47**, stricter than `pubspec.yaml`'s `>=3.12.0` because of dependencies).
  - **No dependency initiative** (see "Upstream alignment"): never run `flutter pub upgrade` and never edit dependency ranges on our own. The lock changes only when an upstream sync changes `pubspec.yaml`: run `flutter pub get` and commit the updated lock in that sync PR. Bump `.flutter-version` only when an upstream change requires a newer SDK.
  - Known and accepted: `forui 0.25` pulls the discontinued `forui_assets`. Migrating (forui 0.25 → 0.27) is upstream's call (issue #4, closed as not planned).
- Run the steps through the wrapper (`scripts/with-env.sh <step>`). `build_runner` is the slow one (~1.5 min cold, 375 outputs); the others take seconds.
- `pub get` rewrites `macos/Flutter/GeneratedPluginRegistrant.swift` with LF endings; with `core.autocrlf=true` git then reports it modified with no content diff (`git diff` is empty). Discard it with `git restore`; never commit it unless its content actually changed.
- `dart run open_authenticator:generate --help` lists the options; defaults point at the official backend with empty Sentry/RevenueCat keys. Never hand-edit `lib/app.dart`; regenerate it.
- Re-run `build_runner` after changing drift tables, and `slang` after editing translation JSON.

## Android device build (issue #10)

Debug build on a physical device, with no change to upstream files:

```sh
scripts/with-env.sh dart scripts/generate_google_services.dart   # once: writes gitignored android/app/google-services.json
scripts/with-env.sh flutter build apk --debug                    # ~6.5 min cold, ~226 MB (all ABIs, JIT)
adb install build/app/outputs/flutter-apk/app-debug.apk          # or: scripts/with-env.sh flutter run -d <device>
```

- **`google-services.json`**: the upstream Gradle file applies the Google Services plugin, which refuses to build without this file, and upstream does not ship it. `scripts/generate_google_services.dart` derives it from the Android options in the upstream-tracked `lib/model/migrator/firebase_options.dart` (same Firebase project; these are public client identifiers, not secrets). Firebase is only used by the legacy-storage migrator. Do not create our own Firebase project.
- **NDK**: Flutter 3.47 requires NDK `28.2.13676358`. Gradle's auto-install fails ("Package ndk not found"): in cmdline-tools 23.0, `sdkmanager` is a deprecated shim over the new `android` CLI, and the `;` in `ndk;<version>` gets split. Install it manually with the new syntax: `"$ANDROID_HOME/cmdline-tools/latest/bin/android.exe" --no-metrics sdk install ndk/28.2.13676358` (list packages with `... sdk list`). Do the same when a future Flutter needs another NDK.
- **Release builds** need upstream's signing key (`android/key.properties`, not in the repo), so only debug (or profile) builds are possible here.
- **App identity**: the build keeps the upstream `applicationId` `app.openauthenticator` (no `.dev` suffix, to avoid divergence). It cannot be installed over the Play Store app (signature mismatch). The official app was uninstalled from the dev Pixel on 2026-10-26 with the user's explicit consent. **Never uninstall or replace an installed `app.openauthenticator` on any device without asking**: uninstalling wipes its TOTP data.
- **Expected build warnings** (upstream-owned, left as is): Flutter will soon drop support for AGP 8.11.1 (wants ≥ 9.0.1) and Kotlin 2.2.20 (wants ≥ 2.3.20). A future Flutter bump may turn these into errors; `.flutter-version` keeps us on 3.47.8 meanwhile.
- **Screenshots**: `adb exec-out screencap -p` returns a black image when the screen is off or locked (`adb shell dumpsys power | grep mWakefulness`).

## Lint / format

- `flutter analyze` (uses `flutter_lints` + the `riverpod_lint` analyzer plugin). Baseline: no issues.
- Format check: only on Dart files that differ from upstream (ours are formatted, upstream's are left as upstream has them; upstream uses an older formatter, so reformatting its files would create divergence):
  ```sh
  files=$( (git diff --name-only --diff-filter=d upstream/main -- '*.dart'; git ls-files --others --exclude-standard -- '*.dart') | sort -u); [ -z "$files" ] || scripts/with-env.sh dart format --output=none --set-exit-if-changed $files
  ```
  The empty guard matters: `dart format` with no paths formats the whole directory. Generated files (e.g. `lib/model/database/database.g.dart`) are gitignored, so `git diff` never lists them. Always run the formatter inside the repo, because it reads `page_width` from `analysis_options.yaml`; outside the repo it falls back to 80 columns.
- `dart format <files you changed>` (never `dart format .`, see "Upstream alignment"). The project sets `page_width: 200` and `trailing_commas: preserve` in `analysis_options.yaml`, so lines are long and existing trailing commas are kept.
- Style rules enforced: single quotes, `prefer_const_constructors`, `unnecessary_lambdas`. Code uses explicit local variable types (`AppDatabase database = ...`) rather than `var`, and every public member has a `///` doc comment.
- The SDK constraint is `>=3.12.0`; the code uses dot shorthands (`mode: .insertOrReplace`, `currentPlatform == .linux`).

## Tests

Fork-only addition (issue #12): `flutter_test` (`sdk: flutter`) is in `dev_dependencies`, and tests live under `test/`.

```sh
scripts/with-env.sh flutter test                                        # all tests
scripts/with-env.sh flutter test test/utils/result/result_test.dart     # one file
scripts/with-env.sh flutter test --name 'to\(\) converts'               # by test-name regex
```

Conventions:
- `test/` mirrors `lib/`: the tests for `lib/<path>/<name>.dart` go in `test/<path>/<name>_test.dart` (the `_test.dart` suffix is how `flutter test` finds them). Import code under test with `package:open_authenticator/...`.
- Use `package:flutter_test/flutter_test.dart`, even for pure-Dart logic (it re-exports `package:test` and adds widget testing). One `group` per class or unit, and test names that state the behavior (`'to() keeps the same exception and stack trace'`).
- Arrange / act / assert, separated by blank lines. Same style as `lib/`: explicit local types, single quotes, `const` where possible.
- Test the documented contract, not implementation details. When adding tests for an important behavior, check that they can fail: temporarily break the code, see red, restore (`git restore`).
- Tests must be deterministic: no network, no real clock or randomness without injection, no device.
- Do not change upstream code to make it testable (see "Upstream alignment"). If something cannot be tested without a change, note it in the test plan instead.

The only CI workflow is `.github/workflows/docs.yml` (docs dispatch): nothing builds or tests the app in CI yet (when added, it should use `.flutter-version` and `--enforce-lockfile`).

## Architecture

**State management is Riverpod 3 everywhere** (hand-written providers, no codegen). `main.dart` sets up desktop windowing (`window_manager`), locale, optional Sentry, then `ProviderScope` → `TranslationProvider` → `OpenAuthenticatorApp`, which routes by name (`HomePage.name`, `IntroPage.name`, ...) and wraps the app in the unlock challenge, migrator and app-link listeners.

- `lib/model/` — domain + state. Key pieces:
  - `totp/` — `Totp` (encrypted form) vs `DecryptedTotp`; `TotpRepository` (`totpRepositoryProvider`) is the main entry point for adding/updating/deleting TOTPs. Each mutation writes to the Drift DB, and when `StorageType.shared` is selected it also enqueues a backend push operation and updates the image cache.
  - `crypto/` — `Salt` + `DerivedKey` (from the master password) → `CryptoStore` (`cryptoStoreProvider`). TOTP secrets are encrypted at rest with it; changing the master password re-encrypts via the repository.
  - `database/` — single Drift `AppDatabase` (`build.yaml` registers it) with tables in `tables.dart` (part file). Schema migrations use drift's versioned steps: bump `schemaVersion`, run `dart run drift_dev make-migrations`, which updates `drift_schemas/app/drift_schema_vN.json` and `database.steps.dart` (generated, do not edit).
  - `backend/` — HTTP client for the sync backend: `request/`, `authentication/` (session, OAuth-style providers, native web auth), `synchronization/` (push-operation queue persisted in the DB + periodic pull controller), `connectivity.dart`.
  - `settings/` — each setting is a `SettingsEntry<T>` (`AsyncNotifier` backed by prefixed `SharedPreferences`); subclass and override load/save for non-primitive types. `storage_type.dart` also holds the local ↔ shared storage migration logic.
  - `backup/` — backup files (store and path handling).
  - `password_verification/` — master-password verification methods.
  - `app_unlock/` — unlock methods (none, local_auth, master password) and the unlock state machine.
  - `migrator/` — one-off migration from the legacy Firebase-based storage (Firebase deps are slated for removal).
  - `purchases/` — "Contributor Plan" via RevenueCat (`purchases_flutter` on mobile/macOS, a Dart REST client for Windows/Linux).
  - `app_links/` — handlers for `otpauth://`, `openauthenticator://`, auth and purchase deep links.
- `lib/flows/` — multi-step user flows (`AppFlow` base) that orchestrate dialogs + model calls (account login, master password, storage migration, email confirmation...).
- `lib/pages/`, `lib/widgets/` — UI built on **forui** (not plain Material widgets) plus `AppScaffold`.
- `lib/utils/result/` — sealed `Result<T>` (`ResultSuccess` / `ResultError` / `ResultCancelled`) returned by most model operations; `handler.dart` turns a result into a toast/dialog plus optional Sentry reporting. Prefer returning `Result` over throwing across layers.
- `lib/i18n/` — slang with namespaces: one JSON file per namespace per locale (`en/`, `fr/`, `de/`, `it/`, `pt/`); `en` is the base locale and keys are camelCase. Access through the generated `translations` object. Translations are community-maintained via the website, and changes to `lib/i18n/**` trigger the docs-site dispatch workflow (`.github/workflows/docs.yml`).

## Development workflow (this fork)

Work happens on the fork `mgagp/openauthenticator` (`origin`). `upstream` is `openauthenticator-app/openauthenticator`, fetch-only (push URL disabled); sync with `git fetch upstream` + a PR. Never open PRs or issues against upstream: `gh` defaults to the parent repo on forks, so the default is pinned with `gh repo set-default mgagp/openauthenticator` — pass `--repo mgagp/openauthenticator` if in doubt. Contributing a change upstream is a separate, explicit decision.

**Upstream alignment (current goal, set 2026-10-26, issue #8).** In the short term this fork follows upstream exactly and only moves when upstream moves.
- App code (`lib/`, `bin/`, platform folders, `pubspec.yaml`) stays identical to `upstream/main`. Check with `git diff --stat upstream/main -- lib bin pubspec.yaml`.
- No initiative on dependencies, formatting or refactors of upstream code. Findings like discontinued packages get noted, not acted on.
- Fork-only additions are allowed when they do not touch upstream files: tooling (`scripts/with-env.*`, `dev-env.example`, `.flutter-version`), `CLAUDE.md`, `.claude/`, `pubspec.lock`, and new tests under `test/`. Adding `flutter_test` to `dev_dependencies` for tests is the one expected `pubspec.yaml` change.
- **Single planned exception: EzKey integration.** A later step will integrate the experimental EzKey Flutter SDK (from the user's EzKey project). If that integration hits a dead end that cannot be solved within the alignment rule (e.g. a dependency or SDK version conflict with upstream), the needed divergence is decided with the user at that point, documented here, and kept minimal. No other exception.
- Revisit this rule explicitly with the user before diverging.

1. **Issue** — every unit of work starts with an issue (context, goal, acceptance criteria). Exception: trivial touch-ups (typos, small doc fixes) can go straight to a PR.
2. **Branch** — one per issue, from up-to-date `main`: `<type>/<issue>-<slug>`, e.g. `chore/1-dev-env-tooling`, `test/3-result-unit-test`. `<type>` is a conventional-commit type.
3. **Commits** — conventional commits in the repo's existing style: `type(scope): Capitalized past-tense summary.` (e.g. `chore(tooling): Added dev-env wrapper.`).
4. **PR** — to `main` of the fork. Title is a conventional commit (it becomes the squash commit and feeds the changelog); body has `Closes #n`, a summary, and the checks that were run with their results.
5. **Merge** — squash only (enforced by the `protect-main` ruleset: PR required, no force push, no deletion; branches auto-delete on merge).
   - **Claude may merge** when the change's correctness is fully established by deterministic checks that were run and passed (`dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, a build when relevant): e.g. tests, generated/derived files, a lock update that follows an upstream sync and builds and passes, CI config.
   - **The user merges** anything whose correctness needs human judgment: app behavior and UI, crypto/auth/sync logic, security-sensitive or data-migration changes, and changes to this workflow or to `CLAUDE.md` itself.
   - When unsure which category applies, leave it to the user.

There is no CI yet, so checks are run locally (through `scripts/with-env.*`) and reported in the PR.

## Packaging

`bin/` holds the generator scripts (`generate.dart`, `compile_svg.dart`, `generate_polkit_policy.dart`). Linux packaging lives in `flatpak/`, `snap/` and `scripts/{flatpak-build-publish,snap-build}.sh`; Windows MSIX config is in `pubspec.yaml` (`msix_config`). Changelog entries come from conventional commits via the `release` package (`docs`, `version`, `deps`, `flatpak` scopes are ignored). PR titles must use a conventional-commit prefix (CONTRIBUTING.md).
