# Upstream sync

How the fork brings in upstream's changes. The fork follows upstream (`CLAUDE.md` § Upstream alignment) and diverges only through the EzKey ledger ([`ezkey/integration.md`](ezkey/integration.md) § Upstream files touched), so a sync is: merge upstream, re-apply the ledger where it conflicts, adapt the fork's own code, check, and learn.

This method was written during the first sync (#148, 2026-11). Its retrospective (#149) refines it. Each sync keeps a journal under [`upstream-sync/`](upstream-sync/), which is the input of its retrospective.

## Principles

- **A real merge, not a squash.** The sync PR is merged with a merge commit, so `main` keeps upstream's history and the next sync starts where this one ended. It is the only kind of PR merged that way; every other PR is squashed. The `protect-main` ruleset allows both methods (since 2026-11-20). GitHub's merge button remembers the last method used: switch it back to squash after a sync.
- **One sync, one issue, one PR.** The PR's commits stay readable in the history: the merge (conflicts resolved), the toolchain, the fork code adapted, the docs.
- **Moratorium while the sync is open.** No new EzKey work, open drafts stay drafts, manual checks wait until the sync is on `main` (they would validate code about to be replaced). Merge or park open PRs first, so the sync adapts them rather than the reverse.
- **Upstream's choices are taken as they are.** Toolchain, dependencies, lint rules, formatting and refactors come in with the sync, including on the fork's own code. The fork does not keep an older version of something upstream moved.
- **Keep a journal as you go.** Each step with its effort, each problem (symptom, cause, fix), each decision, and lesson candidates marked **Lesson?**. Write it during the work, not after.

## Steps

1. **Size it.** `git fetch upstream`, then:
   - `git log --oneline main..upstream/main` and `git diff --dirstat=files,5 <last sync> upstream/main` for what moved;
   - `git merge-tree --write-tree --name-only origin/main upstream/main`, a trial merge that writes nothing and lists the conflicting files. Compare them with the ledger: a conflict outside it means an unledgered divergence.
   - `git diff <last sync> upstream/main -- pubspec.yaml android/settings.gradle.kts` for the toolchain and dependencies.
2. **Open the issue** (context, moratorium, criteria below) and **the journal** (`docs/upstream-sync/<yyyy-mm>-<slug>.md`). Branch `chore/<issue>-upstream-sync`.
3. **Install the toolchain upstream needs** beside the current one, so a rollback is a one-line change in `dev-env.local`: `git clone --depth 1 --branch <version> https://github.com/flutter/flutter.git C:\Tools\flutter-<version>`.
4. **Merge.** `git -c merge.conflictstyle=diff3 merge --no-ff --no-commit upstream/main`. For each conflict, take upstream's side and re-apply the ledger entry; follow upstream's current style in the re-applied lines. Check that `git diff upstream/main -- lib bin pubspec.yaml`, outside `lib/ezkey/` and the EzKey translations, shows exactly the ledger. Commit the merge alone.
5. **Toolchain and lock.** Set `.flutter-version`, run `flutter pub get`. If it fails on a git dependency upstream follows without a `ref` (`purchases_dart`), run `flutter pub upgrade <that package>` only. Update the Android toolchain in the second place that holds it: `packages/ezkey_keystore/android/build.gradle.kts` (AGP and Kotlin, same as `android/settings.gradle.kts`). Run the codegen. Commit.
6. **Adapt the fork's code.**
   - Rewrite imports from upstream's rename list: `git diff -M --name-status <last sync> upstream/main | grep '^R'` gives the moves; turn them into a `sed` script for the fork's folders (`lib/ezkey/`, `test/`, `integration_test/`, `scripts/`, `packages/`). Move the fork's test folders to keep the mirror of `lib/`.
   - Apply upstream's lint rules to the fork's code with `dart fix --apply <fork folder>`, folder by folder; never on upstream's code.
   - Fix what is left by hand. Read the changed signatures of the upstream APIs the fork calls: a sync-to-async change can compile and still break a test silently.
   - Run the tests. Classify each failure: upstream fixed a pinned quirk (invert the pin), upstream changed a behavior on purpose (update the pin and say so in its comment), or a real regression in the fork (fix it). Commit.
7. **Docs.** Update `CLAUDE.md` (versions, paths), the ledger (paths, names), the test plan and the harmonization inventory where upstream fixed or changed something, and refresh [`upstream-activity.md`](upstream-activity.md). Close or update the fork's issues about upstream findings that the sync resolved.
8. **Check.** Locally and in CI: analyze, scoped format check, `flutter test`, the five builds. Then the device tests: the full round on the Android emulator and on Windows (`integration_test/round/`), the key store contract test, and the EzKey enrollment test on the emulator. If upstream moved again meanwhile, merge `upstream/main` again into the branch.
9. **Merge** (the maintainer, with a merge commit), then lift the moratorium and run the manual checks that waited for it.
10. **Retrospective.** With the maintainer, from the journal: what worked, what cost more than expected, what to change. Apply each retained lesson where it belongs (this method, the ledger, `CLAUDE.md`, scripts, CI) or set it aside with a reason, and write the outcome in the journal's retrospective section. A sync is not finished until this step is done.

## Acceptance criteria for a sync issue

- `upstream/main` merged; the divergence from upstream is exactly the ledger plus fork-only files.
- `.flutter-version` and `pubspec.lock` updated; `flutter pub get --enforce-lockfile` passes.
- Analyze, scoped format check and `flutter test` (the fork's tests and upstream's) pass; CI is green on every job.
- Device tests pass (Android emulator round, Windows round, key store contract test, EzKey enrollment test).
- Docs updated, and the journal complete enough for the retrospective.
