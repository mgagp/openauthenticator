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

- `pubspec.lock` is gitignored, so dependency versions are not pinned: each `pub get` may resolve newer versions within the `pubspec.yaml` ranges. In practice the resolved set needs **Dart ≥ 3.13 / Flutter ≥ 3.47** (stricter than the `>=3.12.0` in `pubspec.yaml`, because of dependencies). Baseline verified on Flutter 3.47.8 / Dart 3.13.7.
- Run the steps through the wrapper (`scripts/with-env.sh <step>`). `build_runner` is the slow one (~1.5 min cold, 375 outputs); the others take seconds.
- `pub get` rewrites `macos/Flutter/GeneratedPluginRegistrant.swift` with LF endings; with `core.autocrlf=true` git then reports it modified with no content diff (`git diff` is empty). Discard it with `git restore`; never commit it unless its content actually changed.
- `dart run open_authenticator:generate --help` lists the options; defaults point at the official backend with empty Sentry/RevenueCat keys. Never hand-edit `lib/app.dart`; regenerate it.
- Re-run `build_runner` after changing drift tables, and `slang` after editing translation JSON.

## Lint / format

- `flutter analyze` (uses `flutter_lints` + the `riverpod_lint` analyzer plugin). Baseline: no issues.
- Format check: `dart format --output=none --set-exit-if-changed $(git ls-files 'bin/*.dart' 'lib/*.dart')`. Check tracked files only: generated files such as `lib/model/database/database.g.dart` are not formatter-clean and are gitignored anyway (`dart format` has no exclude option). Baseline: clean (203 files). Always run the formatter inside the repo, because it reads `page_width` from `analysis_options.yaml`; outside the repo it falls back to 80 columns.
- `dart format .` — the project sets `page_width: 200` and `trailing_commas: preserve` in `analysis_options.yaml`, so lines are long and existing trailing commas are kept.
- Style rules enforced: single quotes, `prefer_const_constructors`, `unnecessary_lambdas`. Code uses explicit local variable types (`AppDatabase database = ...`) rather than `var`, and every public member has a `///` doc comment.
- The SDK constraint is `>=3.12.0`; the code uses dot shorthands (`mode: .insertOrReplace`, `currentPlatform == .linux`).

There is no `test/` directory yet, and `flutter_test` is not in `dev_dependencies`; add both before writing the first test. The only CI workflow is `.github/workflows/docs.yml` (docs dispatch): nothing builds or tests the app in CI, and no Flutter version is pinned anywhere.

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

1. **Issue** — every unit of work starts with an issue (context, goal, acceptance criteria). Exception: trivial touch-ups (typos, small doc fixes) can go straight to a PR.
2. **Branch** — one per issue, from up-to-date `main`: `<type>/<issue>-<slug>`, e.g. `chore/1-dev-env-tooling`, `test/3-result-unit-test`. `<type>` is a conventional-commit type.
3. **Commits** — conventional commits in the repo's existing style: `type(scope): Capitalized past-tense summary.` (e.g. `chore(tooling): Added dev-env wrapper.`).
4. **PR** — to `main` of the fork. Title is a conventional commit (it becomes the squash commit and feeds the changelog); body has `Closes #n`, a summary, and the checks that were run with their results.
5. **Merge** — squash only (enforced by the `protect-main` ruleset: PR required, no force push, no deletion; branches auto-delete on merge).
   - **Claude may merge** when the change's correctness is fully established by deterministic checks that were run and passed (`dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, a build when relevant): e.g. tests, generated/derived files, dependency bumps that build and pass, formatting, CI config.
   - **The user merges** anything whose correctness needs human judgment: app behavior and UI, crypto/auth/sync logic, security-sensitive or data-migration changes, and changes to this workflow or to `CLAUDE.md` itself.
   - When unsure which category applies, leave it to the user.

There is no CI yet, so checks are run locally (through `scripts/with-env.*`) and reported in the PR.

## Packaging

`bin/` holds the generator scripts (`generate.dart`, `compile_svg.dart`, `generate_polkit_policy.dart`). Linux packaging lives in `flatpak/`, `snap/` and `scripts/{flatpak-build-publish,snap-build}.sh`; Windows MSIX config is in `pubspec.yaml` (`msix_config`). Changelog entries come from conventional commits via the `release` package (`docs`, `version`, `deps`, `flatpak` scopes are ignored). PR titles must use a conventional-commit prefix (CONTRIBUTING.md).
