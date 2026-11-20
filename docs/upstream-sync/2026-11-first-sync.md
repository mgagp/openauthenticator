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
