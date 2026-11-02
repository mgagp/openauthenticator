# Upstream activity map

How often upstream changes each part of the app. Use it to judge the **sync cost** of a divergence: a hook in a file upstream rarely touches costs little to keep, while one in a hot file conflicts at every sync. Read it together with the three kinds of divergence cost in [`ezkey/harmonization.md`](ezkey/harmonization.md) § Method.

## Snapshot

Measured on 2026-11-02 against `upstream/main` at `272d67e`. That is upstream's last commit, dated 2026-08-15. The history has 426 commits, the first dated 2024-07-08. Windows: 12 months = since 2025-11-01, 6 months = since 2026-05-01.

**Upstream is in maintenance mode.**
- Over 12 months, the commit types were: 95 `chore`, 18 `fix`, 14 `refactor`, and only 3 `feat` (authentication tabs, salt recovery, Flatpak).
- Activity comes in bursts:
  - 80 commits in April 2026 (custom backend and refactors);
  - 15 in May 2026;
  - 17 in June 2026;
  - since then: 5 in July, 1 in August, none after.
- A typical recent commit updates dependencies or moves code. It rarely changes a layout.

**Commit counts overstate the risk.** A dependency or refactor commit touches every file it renames in, often for one or two lines. Before calling a file hot, look at the lines changed and at what the commits were.

### By area

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

The files in the ledger ([`ezkey/integration.md`](ezkey/integration.md) § Upstream files touched).

| File | All commits | 12 months | Lines changed, 12 months | Last change |
| --- | ---: | ---: | ---: | --- |
| `lib/pages/home/page.dart` | 14 | 13 | 883 | 2026-06-10 |
| `lib/pages/scan.dart` | 12 | 4 | 60 | 2026-05-06 |
| `lib/pages/settings/entries/clear_data.dart` | 24 | 14 | 97 | 2026-06-26 |
| `lib/pages/settings/entries/backup_now.dart` | 6 | 4 | 21 | 2026-06-10 |
| `lib/pages/settings/entries/manage_backups.dart` | 21 | 12 | 257 | 2026-08-15 |
| `pubspec.yaml` | 86 | 34 | 561 | 2026-08-15 |

- **The home page's 883 lines all date from January and February 2026,** the design update and the custom backend. Since 2026-02-24, upstream has made 7 commits to it, each of 1 or 2 lines. The fork's home hook is 2 lines plus an import, so a sync conflict there is unlikely and quick to resolve.
- **`pubspec.yaml` is the hottest file the fork touches.** Its entries are dependency lines, which are easy to re-apply, but every upstream dependency update conflicts with them textually.
- **Settings entries change in step with upstream refactors** (results, flows, backups). The hooks there are 3 to 4 lines at a stable spot (the start of a handler), which keeps them easy to re-apply.

## Refresh

Run from the repo root, after `git fetch upstream`. Update the snapshot line and the tables when the numbers move enough to change a reading. Rule 3 of [`README.md`](README.md) applies: this map is worth keeping only while it steers decisions.

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
