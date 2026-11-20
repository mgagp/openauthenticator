# Upstream activity map

How often upstream changes each part of the app. Use it to judge the **sync cost** of a divergence: a hook in a file upstream rarely touches costs little to keep, while one in a hot file conflicts at every sync. Read it together with the three kinds of divergence cost in [`ezkey/harmonization.md`](ezkey/harmonization.md) § Method.

## Snapshot

Refreshed on 2026-11-20 against `upstream/main` at `57b4fca` (2026-11-19), after the first sync (#148). The history has 465 commits, the first dated 2024-07-08. Windows: 12 months = since 2025-11-20, 6 months = since 2026-05-20.

**Upstream is quiet most of the time, then moves in bursts that can rewrite foundations.**
- Over 12 months, the commit types were: 98 `chore`, 41 `fix`, 23 `refactor`, and only 3 `feat`.
- Activity per month: 80 commits in April 2026 (custom backend and refactors), 15 in May, 17 in June, 5 in July, 1 in August, none in September and October, then **39 on 2026-11-18 and 2026-11-19**.
- The November burst was not features: a new Flutter (3.50, adopted within days of its release), every dependency updated, a much stricter lint set, `lib/model` renamed `lib/core` and other moves, and about twenty robustness fixes. The previous snapshot (2026-11-02) read "maintenance mode"; three months of silence did not predict it.
- **Reading for the fork:** expect long quiet periods and sudden large syncs. A burst touches every file through renames and lint fixes, so its cost is mostly in the fork's own code (imports, tests, lints), not in the ledger's conflicts. See [`upstream-sync.md`](upstream-sync.md).

**Commit counts overstate the risk.** A dependency or refactor commit touches every file it renames in, often for one or two lines. Before calling a file hot, look at the lines changed and at what the commits were.

### By area

Measured on 2026-11-02 at `272d67e`, before upstream renamed `lib/model` to `lib/core` (the `lib/model/...` rows now live under `lib/core/...`). Not refreshed in 2026-11: `git log -- <directory>` does not follow a rename, so the new paths only count the commits since the move. The readings still hold, with the November burst added to every row.

| Area | All commits | 12 months | 6 months | Last change | Reading |
| --- | ---: | ---: | ---: | --- | --- |
| `pubspec.yaml` | 86 | 34 | 9 | 2026-08-15 | Hot (dependencies) |
| `lib/i18n/` | 90 | 30 | 9 | 2026-06-24 | Hot (community translations) |
| `lib/pages/settings/` | 67 | 30 | 9 | 2026-08-15 | Hot |
| `lib/model/backend/` | 40 | 40 | 10 | 2026-07-20 | Hot (rewritten in 2026) |
| `lib/widgets/` | 88 | 33 | 10 | 2026-08-15 | Hot |
| `lib/utils/` | 80 | 31 | 10 | 2026-07-08 | Hot |
| `lib/main.dart` | 59 | 27 | 4 | 2026-07-20 | Warm |
| `lib/model/totp/` | 47 | 27 | 6 | 2026-07-08 | Warm |
| `lib/model/settings/` | 34 | 24 | 5 | 2026-08-15 | Warm |
| `lib/pages/intro/` | 33 | 21 | 5 | 2026-07-08 | Warm |
| `lib/pages/totp.dart` | 34 | 17 | 3 | 2026-06-10 | Warm |
| `lib/model/purchases/` | 24 | 16 | 4 | 2026-07-08 | Warm |
| `lib/model/app_unlock/` | 32 | 15 | 3 | 2026-06-10 | Warm |
| `lib/pages/home/` | 19 | 18 | 3 | 2026-06-10 | Cold since 2026-02-24 (see below) |
| `lib/model/database/` | 12 | 12 | 0 | 2026-04-30 | Cold |
| `lib/model/migrator/` | 11 | 11 | 3 | 2026-06-26 | Cold (slated for removal) |
| `lib/model/crypto/` | 6 | 6 | 4 | 2026-07-08 | Cold, but sensitive |
| `lib/pages/scan.dart` | 12 | 4 | 1 | 2026-05-06 | Cold |
| `lib/flows/` | 2 | 2 | 2 | 2026-06-10 | Cold (new in 2026) |
| `lib/model/backup/`, `lib/model/app_links/` | 1 each | 1 | 1 | 2026-05-06 | Cold (new in 2026) |
| `android/`, `ios/`, `macos/`, `windows/`, `linux/` | 16 / 27 / 35 / 15 / 19 | 5 / 7 / 11 / 5 / 6 | 2 / 2 / 4 / 2 / 1 | 2026-06 to 2026-08 | Warm on Apple, cold elsewhere |

### Upstream files the fork touches

The files in the ledger ([`ezkey/integration.md`](ezkey/integration.md) § Upstream files touched). Refreshed on 2026-11-20 (`git log --follow`, so the counts include the history before the move to `lib/core`).

| File | All commits | 12 months | Lines changed, 12 months | Last change |
| --- | ---: | ---: | ---: | --- |
| `lib/pages/home/page.dart` | 18 | 17 | 929 | 2026-11-18 |
| `lib/pages/scan.dart` | 15 | 7 | 66 | 2026-11-18 |
| `lib/pages/settings/entries/clear_data.dart` | 29 | 19 | 243 | 2026-11-18 |
| `lib/pages/settings/entries/backup_now.dart` | 9 | 7 | 29 | 2026-11-18 |
| `lib/pages/settings/entries/manage_backups.dart` | 26 | 16 | 291 | 2026-11-18 |
| `lib/core/backup/backup.dart` | 6 | 2 | 194 | 2026-11-18 |
| `lib/core/backup/store.dart` | 4 | 1 | 148 | 2026-11-18 |
| `pubspec.yaml` | 93 | 39 | 626 | 2026-11-18 |

- **In the first sync, every ledger file conflicted, and every conflict was small.** Most were an import list (upstream's new imports next to the fork's one); the rest were the hook lines themselves, which upstream had restyled (`final` locals) or moved into a new method (`clear_data.dart`). Each was re-applied from its ledger entry.
- **The home page hook survived a burst without a code conflict**: upstream changed 23 lines of the file, none near the wrapped list.
- **`pubspec.yaml` stays the hottest file the fork touches**, and its conflicts stay mechanical (dependency lines).

## Refresh

Run from the repo root, after `git fetch upstream`. For a file, add `--follow` so its history survives upstream's renames; for a directory upstream moved, count the old and the new path. Update the snapshot line and the tables when the numbers move enough to change a reading. Rule 3 of [`README.md`](README.md) applies: this map is worth keeping only while it steers decisions.

```sh
git log upstream/main -1 --format='%h %ad' --date=short     # snapshot commit
git log upstream/main --since=2025-11-01 --format=%ad --date=format:%Y-%m | sort | uniq -c   # activity per month
git log upstream/main --since=2025-11-01 --format=%s | sed -E 's/^([a-z]+).*/\1/' | sort | uniq -c | sort -rn   # commit types
for d in lib/pages/home lib/pages/scan.dart pubspec.yaml; do   # any area or file
  printf '%s all=%s 12m=%s 6m=%s last=%s\n' "$d" \
    "$(git log upstream/main --oneline -- "$d" | wc -l)" \
    "$(git log upstream/main --since=2025-11-01 --oneline -- "$d" | wc -l)" \
    "$(git log upstream/main --since=2026-05-01 --oneline -- "$d" | wc -l)" \
    "$(git log upstream/main -1 --format=%ad --date=short -- "$d")"
done
git log upstream/main --since=2025-11-01 --numstat --format= -- lib/pages/home/page.dart | awk '{n+=$1+$2} END {print n}'   # lines changed
git log upstream/main --format='%ad %s' --date=short --numstat -- lib/pages/home/page.dart   # what the commits were
```

Move the windows forward when you refresh, so "12 months" keeps meaning the last 12 months.
