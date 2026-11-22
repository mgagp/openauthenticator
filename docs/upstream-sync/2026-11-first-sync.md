# First upstream sync, 2026-11 (#148)

Journal of the fork's first upstream sync, kept as the work goes. It is the input of the retrospective (#149). Each entry says what was done, what it cost, and what went wrong. Lesson candidates are marked **Lesson?** so the retrospective can find them.

- **Range:** `upstream/main` from `272d67e` (2026-08-15) to `57b4fca` (2026-11-19), 39 commits.
- **Branch:** `chore/148-upstream-sync`, to be merged with a merge commit.
- **Toolchain before:** Flutter 3.47.8 / Dart 3.13.7. **After:** Flutter 3.50.1 / Dart 3.14.0.

## Before starting (2026-11-20)

- **How we noticed:** the maintainer saw the activity on GitHub. Nothing in the fork watches upstream. **Lesson?** A cheap watch (a scheduled check, or a CI job that reports `git rev-list --count main..upstream/main`) would tell us earlier.
- **Survey:** `git log`, `git diff --dirstat`, and a trial merge with `git merge-tree --write-tree --name-only origin/main upstream/main`. The trial merge wrote nothing and listed the 8 conflicting files in seconds. It matched the ledger exactly. **Lesson?** Keep the trial merge as the first step: it sizes the textual part of a sync for free.
- **What upstream did:** toolchain (Flutter 3.50, AGP 9.1, Kotlin 2.4, Gradle 9.3), all dependencies updated (forui 0.28, Material moved to the `material_ui` package, RevenueCat 11, Firebase 5/7, Sentry 10, window_manager 0.7), refactors (`lib/model` → `lib/core`, `lib/utils` split, dialogs moved), about twenty robustness fixes, a much stricter lint set (`analysis_options.yaml`, +72 lines) and upstream's own tests in `test/`.
- **`docs/upstream-activity.md` was wrong:** it said "upstream is in maintenance mode". The burst came three months after its snapshot. **Lesson?** The activity map describes the past; it cannot predict a burst. Its value is the per-file reading, not the forecast.
- **Merge method:** `main` only allowed squash. A squashed sync drops upstream's ancestry, so the next sync would replay the same conflicts. The maintainer allowed merge commits in the repo settings and in the `protect-main` ruleset (2026-11-20), with the convention "merge commit only for upstream syncs". The merge commit takes the PR title and description. **Lesson?** Decide the merge method before the first sync, not during it. Watch for GitHub's merge button, which remembers the last method used.
- **Moratorium:** no EzKey work, the TPM spike (#147) kept as a draft, no manual Windows checks until the sync is on `main`. Open PR #146 (tests and docs) was merged first so the sync adapts it.
- **Flutter 3.50.1:** installed beside 3.47.8 (`git clone --depth 1 --branch 3.50.1` into `C:\Tools\flutter-3.50.1`, about 5 minutes with the first-run download), and `dev-env.local` pointed at it. 3.47.8 stays in `C:\Tools\flutter` for a rollback. Upstream adopted 3.50 within days of its release (3.50.1 is dated 2026-11-18).

## Step 1: merge and conflicts (2026-11-20)

- `git -c merge.conflictstyle=diff3 merge --no-ff --no-commit upstream/main`: 8 conflicts, the files the trial merge listed. Git followed the `lib/model/backup` → `lib/core/backup` rename, so the hooks in `backup.dart` and `store.dart` landed in the new paths by themselves.
- **Import conflicts:** most conflicts were an import list. Upstream's side was a block of new imports (`material_ui`, `core/...`) and ours one `ezkey/...` import. A small script kept upstream's block and appended ours, which sorts right after it (`core` < `ezkey` < `flows`). Then each code hunk took upstream's side and the hook was re-applied from the ledger.
- **Ledger held:** every hook was re-applied from its ledger entry without reading the old diff. Two needed a new place:
  - `clear_data.dart`: upstream moved the clearing into a `_clear(ref, deleteBackups)` method. The orphan-key hook went after `secureStorage.clear()` there.
  - `backup.dart`: `save()` now writes inside a `try`. The inventory spread went into the same map.
- **Style drift:** upstream now writes `final` locals with explicit types (`prefer_final_locals`). The re-applied hooks follow it (`final String message = ...`).
- **`pubspec.yaml`:** upstream added `flutter_test` to `dev_dependencies` itself, so the fork's own `flutter_test` entry is gone and the divergence shrank to the EzKey block and `integration_test`.
- **Check:** `git diff upstream/main -- lib bin pubspec.yaml` outside `lib/ezkey/` and the EzKey translations shows exactly the ledger entries.
- **Observed for later:** upstream's new `_clear` stops at the first backup that fails to delete and now reports it. With #141 (the backup list mutated in place), clearing data with backups deleted may now show an error dialog instead of failing silently. To check in the device round.
- **Lesson?** Line endings: with `core.autocrlf=true`, the working tree is CRLF, so a script that matches conflict markers must handle `\r\n`. Lost a few minutes on it.

## Step 2: toolchain (2026-11-20)

- `.flutter-version` → 3.50.1, then `flutter pub get`.
- **Snag: a git dependency that upstream follows at HEAD.** `pub get` failed: `purchases_dart` (upstream's own package, a git dependency with no `ref`) was locked at an April commit that requires `purchases_flutter` 10, while the merged `pubspec.yaml` asks for 11. Upstream updated that repo the same day. Upstream gitignores its lock, so it always gets the latest commit; the fork's lock pins it. Fix: `flutter pub upgrade purchases_dart`, a targeted upgrade of that one package. 62 packages changed in the lock, all driven by the merged constraints. **Lesson?** Before `pub get`, list upstream's git dependencies without a `ref` and check whether their repos moved too; a targeted `pub upgrade <name>` is the fix and stays within the "no dependency initiative" rule.
- The generated registrants (`windows/flutter/...`, `macos/Flutter/...`) came back with line-ending-only changes, restored as usual.
- Codegen (`compile_svg`, `slang`, `generate`, `build_runner`) ran unchanged; `build_runner` took about 80 s.

## Step 3: fork code adapted (2026-11-20)

- **First analysis: 1442 findings.** Almost all came from moved paths and the new lint set, not from real breakage.
- **Paths, scripted from upstream's own renames.** `git diff -M --name-status 272d67e upstream/main` lists the 72 renamed Dart files; a generated `sed` script rewrote the fork's imports (`lib/ezkey/`, `test/`, `integration_test/`, `scripts/`, `packages/`), then `model/` → `core/` and `flutter/material.dart` → `material_ui`. `test/model/` moved to `test/core/` to keep the mirror. That left about 40 real errors. **Lesson?** Derive the import rewrite from upstream's rename list instead of fixing errors one by one; it took minutes.
- **Real API changes, all in the fork's tests of upstream code:**
  - `CryptoStore.fromPassword` became the asynchronous `fromPasswordInIsolate`;
  - `AppDatabase` lost `getTotp`, `listUuids`, `updateTotp`, `deleteTotp` (now `saveTotps`, `deleteTotps` with timestamps); a small test-side extension rebuilds the two read helpers;
  - `CryptoStore.encrypt` no longer returns `null`, and `checkPasswordValidity` became asynchronous. The second one compiled and would have failed silently (`expect(Future, isTrue)`); only reading the diff caught it. **Lesson?** A signature change from sync to async does not always break the build; read the changed signatures of what the fork's tests call.
  - In the fork's code, one: the backup hook read `backupData`, which upstream renamed `jsonData`. The ledger entry quotes the old name.
- **My own slip:** the script that made test callbacks `async` walked up past tests that were already `async` and marked some `group(...)` callbacks `async`, which Dart does not support. Caught by the next analysis, fixed. **Lesson?** Prefer the analyzer's own fixes (`dart fix`) to home-made rewriting scripts for code changes.
- **Upstream's lint set on the fork's code:** `dart fix --apply`, run on the fork's folders only, made about 720 fixes (mostly `final` locals). Left: `unnecessary_async` on test fakes (provider overrides and interface fakes that return a Future on purpose), ignored in `test/analysis_options.yaml` with the reason written there. `unnecessary_await_in_return`, which the fork's own lint files enabled, is deprecated in Dart 3.14 and was removed from them.
- **Tests: 336 passed, 18 failed.** Every failure was the fork's tests pinning upstream behavior that upstream has now changed. None was a regression in the EzKey integration:
  - **fixed upstream, pins inverted:** case-insensitive search (our #145), `BackupStore.import` without a backups directory, the double dash in the migrated legacy database name, `tryFromJson` without a date;
  - **changed on purpose upstream, pins updated:** the `issuer:` prefix is now split off an `otpauth` label (`ff1c9aa`), stricter TOTP JSON parsing (`963d86c`), and a master password change now aborts on an undecryptable TOTP instead of skipping it;
  - **moved by our own rename:** the backup fixtures path (`test/model/` → `test/core/`).
  - After the updates: 354 passed. **Lesson?** The fork's "pinned upstream quirk" tests did their job: each upstream behavior change showed up as a named failure. Their comments made each one quick to classify.
- **Formatting:** the Dart 3.14 formatter reformatted 4 fork files.
- **Android plugin:** `packages/ezkey_keystore` hard-codes the AGP and Kotlin versions (it says so: "same as the host app"). Moved to 9.1.1 and 2.4.10 by hand. **Lesson?** Two places hold the Android toolchain; the sync checklist must name the second one.
- **Built-in Kotlin, a warning for later:** Flutter 3.50 warns that the app and three plugins apply the Kotlin Gradle Plugin "which will cause build failures in future versions of Flutter": upstream's app (it sets `android.builtInKotlin=false`), `purchases_ui_flutter`, `simple_secure_storage_android`, and the fork's own `ezkey_keystore`. The same build also warns that the AGP, Kotlin and Gradle versions upstream just adopted "will soon be dropped". The fork follows upstream's setting for now. **Lesson?** The fork's plugin is the one item on that list the fork owns; migrating it is a candidate follow-up, to weigh in the retrospective.

## Step 4: docs (2026-11-20)

- `CLAUDE.md`: Flutter 3.50.1 / Dart 3.14, `lib/core`, `material_ui`, upstream's lint set on the fork's code (with `dart fix`), the targeted `pub upgrade` exception for git dependencies in a sync, upstream's own tests in `test/`, and the merge rule (squash, except a sync PR, merged with a merge commit).
- The ledger (`docs/ezkey/integration.md`): new paths, the renamed variable in the backup hook, the clear-data hook's new place, the `final` style, and "last checked against `57b4fca`".
- `docs/test-plan.md`, `docs/ezkey/harmonization.md`, ADR-0002 and ADR-0005: paths only (`model/` → `core/`); the two backup quirks in the test plan are marked fixed upstream. The ADRs' decisions are unchanged; only their file references moved.
- `docs/upstream-activity.md`: snapshot refreshed. The per-area table was kept from 2026-11-02, because `git log -- <directory>` does not follow upstream's rename and the new paths would undercount. **Lesson?** Refresh commands need `--follow` (files) or both paths (directories) after an upstream rename.
- New: `docs/upstream-sync.md` (the method, ending with the retrospective) and this journal, both in the docs index.

## Step 5: checks on devices (2026-11-20)

- **Android emulator:**
  - key store contract test: 3/3 (tier `none`, as always on the emulator);
  - automated round (`upstream_round_test.dart`): intro, manual TOTP and its code pass, then it stops at the edit step, which goes through the desktop "…" menu. The test was written for desktop (#132); Android's full round was manual (#131). **Lesson?** A platform-aware round test (the mobile menu on Android) would make the Android round re-runnable at each sync instead of manual.
- **Windows:**
  - the build works with VS 2022 as before; the Firebase SDK now prints more `LNK4099` warnings (same cause, missing PDBs).
  - round: the first run failed at "Clear data". Upstream replaced the dialog's OK/Cancel with "Delete them" / "Keep them". The test helper now picks "Keep them". Then everything passed: intro, manual add, code, edit, delete, backup and restore (wrong password refused), clear data.
  - across a restart (setup, then restart): all pass. The copy check passed this time (session unlocked). The search for "Manual" now finds "ManualCo": **#145 is fixed in the real app**. Deleting a backup still leaves it listed until the dialog is reopened: **#141 is still there**.
  - The maintainer's debug data was set aside before and restored after (`scripts/windows_round_data.ps1`, verified byte for byte). It is still at database schema 2; its first launch with this build will run upstream's migration to schema 3.
- **Not run:** the key store contract test on Windows (the Windows plugin lives on the TPM spike, #147, not on `main`).

## Step 6: CI (2026-11-20)

- First CI run: Linux and Windows builds passed; four jobs failed, for two reasons the local checks could not show.
  - **`cnativeapi` build hook** (new, pulled by window_manager 0.7): its native build hook runs on every Linux host, even for `dart run` and `flutter test`, and needs the GTK 3, X11 and Xi development packages. Only the Linux build job installed them; the analyze job and the Android build (both on Ubuntu) failed. Fix: the shared setup action installs them on Linux. **Lesson?** A new dependency with native build hooks can break CI jobs that never build for its platform; read upstream's new dependencies, not only the bumped ones.
  - **`scripts/generate_google_services.dart`** still read `lib/model/migrator/firebase_options.dart` (iOS and macOS failed; Android would have next). The import rewrite only touched Dart `import` lines, and locally the generated Firebase files already existed, so nothing ran the script. Fix: path updated, script re-run from scratch locally (identical output). **Lesson?** After an upstream move, grep the fork's scripts, CI and docs for the old path as plain text, not only Dart imports; and run each generator from a clean state.
- Second CI run: analyze, Android, Linux and Windows pass. **iOS and macOS fail:** Flutter 3.50 turns on Swift Package Manager and migrates the Xcode projects during the build; on the runner (macos-15-intel, Xcode 26.3), Xcode crashes with an internal error while resolving the packages (RevenueCat, Firebase, Sentry...). Flutter 3.47 used CocoaPods. Attempt: the shared setup turns SPM off on macOS runners (`flutter config --no-enable-swift-package-manager`), so the Apple builds keep CocoaPods as before. **Lesson?** A Flutter bump can change the build system of a platform the fork cannot build locally; the Apple side needs the Mac (#135, #136) before or during a sync, not after.

## Step 7: Pixel, then upstream moved again (2026-11-21)

- **Pixel (debug build updated over the 11-13 one, after a backup in the app):** `adb install -r` succeeded. The app process started by itself right after the install, while the phone had locked again, and the activity came up behind the lock screen: stuck on "Open Authenticator is locked" with the Unlock button doing nothing (`BiometricPromptCompat: Unable to start authentication. Called after onSaveInstanceState()`), our known #98. `am force-stop`, then opened by the maintainer while unlocked: the app unlocks, the database migrated (no TOTPs on that phone, so the migration ran on an empty vault), and the EzKey enrollments are all there. **Lesson?** After installing on the Pixel, force-stop the app before the maintainer opens it.
- **The APK in `build/` was not the app:** the EzKey lab test on the emulator had rebuilt `app-debug.apk` with the test entry point. Caught before installing (the file's time), rebuilt with `flutter build apk --debug`. **Lesson?** Build the APK to install right before installing it, never reuse the one in `build/` after an integration test.
- **EzKey enrollment test on the emulator** against the local stack: enrolled, sign-in request approved, test enrollment revoked. The screens render as before with forui 0.28.
- **Upstream moved again during the sync:** 26 more commits on 2026-11-20 (`57b4fca` → `db19409`), all fixes. CI's scoped format check, which compares with the latest `upstream/main`, flagged upstream's own new files as if they were the fork's: that is how we noticed. **Lesson?** The format check is a free "upstream moved" alarm; the method's "merge again before the end" step was needed on the first sync.
  - Second merge: one conflict, the `_create` hook in `backup.dart` (new signature), re-applied from the ledger.
  - **A hook lost its input:** upstream's backup reader now keeps only the TOTPs, the salt and the signature, so the inventory hook no longer had the decoded file. Instead of reaching into upstream's reader, the fork's `EzkeyBackupInventory.tryReadFile` reads the file again (small file, fails open). The hook stays one line.
  - **Tests:** the fork's backup test hung (timeouts): upstream now lists the support directory too on Windows and Linux and calls the path provider platform directly, which the test's method-channel mock no longer reached. Fixed by faking `PathProviderPlatform`, as upstream's own tests do (upstream added `path_provider_platform_interface` for that). **Lesson?** Run `flutter test --timeout 60s`: a hang then shows up as named failures instead of a silent stall.
  - **The fork's test lint rules reach upstream's tests:** `test/analysis_options.yaml` applies to upstream's flat test files too; `avoid_slow_async_io` flagged upstream's new test and was dropped.
  - **Upstream fixed two of our findings in that batch:** #141 (the backup list is now rebuilt on delete) and #98's cause is addressed by "Deferred biometric prompts while the app was in the background" and "Retried the automatic unlock when the app went to the background before the biometric prompt" (to confirm on the Pixel).
  - 368 tests pass; analyze and format clean.
- **Apple CI, second finding:** turning Swift Package Manager off does not work: `sentry_flutter` 10 (upstream's new version) is "only compatible with Swift Package Manager". The CocoaPods attempt was reverted. The Apple builds need SPM, and SPM resolution crashes Xcode 26.3 on the `macos-15-intel` runner. Not solved yet; it needs the Mac (`ssh mac`, #135) to reproduce and pick a runner or Xcode that resolves, and probably a change to `ci.yml` (a workflow file).
- **Session note:** Claude Code stopped the emulator and the Windows round in the background because the PC ran low on memory. The maintainer's Windows debug data had been set aside for the round; the leftover test app was stopped and the data restored and verified. **Lesson?** Do not run the emulator and a Windows integration test at the same time; stop the emulator when its tests are done.

## Step 8: after the second merge (2026-11-22)

- **Windows, on `db19409`:** the round, then setup and restart, all pass. **#141 is fixed in the real app:** the deleted backup leaves the list at once ("listed 1, after delete 0"). #145 stays fixed. Debug data set aside and restored, verified.
- **Apple builds on the Mac** (over `ssh mac`, as the maintainer allowed; separate folders `~/development/flutter-3.50.1` and `~/github/openauthenticator-sync`, nothing of the EzKey iOS work touched): with Swift Package Manager, macOS and iOS (`--no-codesign`) both build with Xcode 27.0 on arm64. So the CI crash is the runner's (Xcode 26.3, Intel), not the code's.
- **Cause found on the Mac:** the build rewrote upstream's four `Package.resolved` files: they still pin the Swift packages from before upstream's dependency update (Firebase 11.3 → 12.1, and so on), and Xcode updates them during the build. The macOS build also raised `MACOSX_DEPLOYMENT_TARGET` from 10.15 to 12.0 in `project.pbxproj` (Flutter 3.50's minimum). Upstream has not committed either. CI attempt: remove the `Package.resolved` files before the Apple builds, so Xcode resolves from scratch, without committing anything to upstream's files. **Lesson?** Upstream's tracked build files can lag behind its own dependency updates; on our side, CI must tolerate that without diverging from upstream's files. Noted as an upstream finding for the retrospective (not reported upstream).
- **Pixel, on `db19409`:** installed over the previous build (then force-stopped at once, per the lesson above), opened normally: works. Then #98 reproduced on purpose with the maintainer: phone locked, app started through adb, phone unlocked: the biometric prompt shows and unlocks; no `onSaveInstanceState` error in the log. **#98 is fixed upstream.** `CLAUDE.md`, the integrator guide and the test plan no longer describe it as a known limit.
- **Findings closed by this sync:** #145 (search), #141 (backup list), #98 (biometric prompt behind the lock screen), each confirmed in the real app. Still to recheck: #118 (secure storage recovery) and #86 (Google sign-in with DuckDuckGo as default browser), which need conditions not reproduced here.
