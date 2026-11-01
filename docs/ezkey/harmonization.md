# EzKey × Open Authenticator — harmonization dossier

Living dossier for #51. It analyses how EzKey can use the features Open Authenticator built for TOTP, and tracks the items as they are taken. Decisions with trade-offs still get an ADR; this file holds the inventory, the method and the tracking.

## Two tracks, interleaved

| Track | Scope | Examples |
| --- | --- | --- |
| **EzKey** | The EzKey integration itself: SDK, enrollment and approval flows, display concepts, portability | #26 display concepts, #32 / #44 home zones, #29 SDK pin, ADR-0004 portability |
| **Open Authenticator** | EzKey working *with* the app's existing features, so the result feels like one app | Items below |

The two tracks alternate, one item at a time, chosen by what is done and how it evolves. Nothing here is a commitment until it has an issue.

## Method

**Integration levels.** Each item names the level it aims for:
- **L0, alongside:** EzKey has its own version and the upstream feature ignores EzKey (today's default).
- **L1, aware:** the upstream feature knows EzKey exists and does not harm it: warns, excludes, explains.
- **L2, shared:** one feature serves both, for example one scanner that recognizes both kinds of QR code.

**Judging an item:**
- **User value:** what the user gains, or which risk goes away.
- **Anchor point:** where it plugs into upstream. Prefer, in order:
  1. a new file reached through an existing hook;
  2. an extension point upstream already has (a provider, a settings entry, a link handler);
  3. a small, ledgered edit in an upstream file (ADR-0001 D3, `integration.md` § Upstream files touched).
- **Re-integration cost:** how easily the item re-applies after an upstream sync (ADR-0003). It counts more than the size of the diff.
- **UI practice:** reuse upstream's widgets and patterns (forui, `AppScaffold`, settings entries, dialogs, `Result` handling) instead of parallel ones. Upstream must still look like upstream wherever EzKey is unused.
- **Portability:** no Android-only assumption (ADR-0004).
- **Characterize first:** before changing an anchor point, pin its current behaviour with characterization tests (test-only PR), so a change or an upstream sync that breaks it shows up red. #55 covered the home page, `otpauth://` parsing, deep links, backups and Clear data.

## Inventory

First pass on 2026-10-30. Facts checked in the code; ideas are hypotheses until their issue.

| # | Feature (upstream location) | Today with EzKey | Harmonization idea | Level | Anchor point / re-integration | Priority |
| --- | --- | --- | --- | --- | --- | --- |
| H1 | **Clear data** (`pages/settings/entries/clear_data.dart`: clears secure storage, preferences, DB, cache) | **Risk.** EzKey records are erased with the secure storage. The keys are deleted only at the next EzKey start (orphan cleanup), and the **server enrollments stay active**. Nothing tells the user | Warn when EzKey enrollments exist (they cannot be restored; ask the administrators to revoke them), or delete the keys at once | L1 | Upstream file (the dialog text or one hook before the clear); or an EzKey-side notice | **High** (risk) |
| H2 | **Backups** (`model/backup/`: TOTPs and salt only) | EzKey is not in backups. That is correct, since the keys cannot be exported (ADR-0002), but it is not explained | Say in the backup UI that EzKey enrollments are device-bound and need re-enrollment after a restore; never back up records without keys | L1 | Text near the backup entries; possibly an upstream settings entry | Medium |
| H3 | **Sync / shared storage** (`model/backend/synchronization/`, `storage_type.dart`) | TOTP only; EzKey is device-local by nature | State "this device only" on EzKey screens; never sync EzKey | L1 | EzKey side only (no upstream change) | Low |
| H4 | **App unlock** (`model/app_unlock/`, unlock challenge wrapping the app) | Already protects EzKey, since the zone is inside the app. It overlaps with EzKey's "confirm before approvals" (#34) | Explain how they combine. Possibly suggest "confirm before approvals" when app unlock is off | L1 | EzKey settings only | Medium |
| H5 | **Master password / crypto store** (`model/crypto/`) | EzKey records are not encrypted with the master password (ADR-0002: secure storage plus non-exportable keys) | Decide whether EzKey should follow the master password (e.g. lock approvals until unlocked). Needs an ADR | L1–L2 | Upstream providers (read only) | Low (analysis first) |
| H6 | **QR scanner** (`pages/scan.dart`: parses `otpauth` URIs) | Separate EzKey scanner (`ezkey/pages/scan_page.dart`) | One scanner that recognizes both an `otpauth` URI and an EzKey invitation, routing each to its flow | L2 | Upstream scan page (small, ledgered edit) or a wrapper | Medium |
| H7 | **Add flow** (home `+`, `onAddButtonPress`) | Two `+` buttons, one per zone (ADR-0003) | Possibly one "Add" that offers both, depending on the home-zone evolution (#32 / #44) | L2 | Upstream home dialog (ledgered) | Low |
| H8 | **Deep links** (`model/app_links/`: `otpauth://`, `openauthenticator://`) | EzKey invitations cannot be opened by a link | Route an EzKey invitation link to the enrollment flow, if EzKey defines one | L1–L2 | Upstream link listener (a new handler) | Low (depends on EzKey) |
| H9 | **Search** (home search over TOTPs) | Does not see EzKey enrollments | Include enrollments in the results, or keep search TOTP-only on purpose | L2 | Upstream search (ledgered) | Low |
| H10 | **Settings page** (`pages/settings/`) | EzKey settings live on the EzKey page (#33); the Settings entry was removed in #28 | Decide whether an "EzKey" section belongs in Settings, for discoverability and consistency | L1 | Upstream settings page (ledgered) | Low |
| H11 | **Onboarding** (`pages/intro/`) | No mention of EzKey | One optional intro step, shown only where EzKey is available | L1 | Upstream intro (ledgered) | Low |
| H12 | **Error handling** (`utils/result/`, `handler.dart`, Sentry) | EzKey has its own toasts (`ezkey/toast.dart`) and messages | Route EzKey errors through `Result` and the handler where it fits; decide what Sentry may receive (never EzKey payloads) | L2 | New code in `lib/ezkey/` using the upstream handler | Medium |
| H13 | **Translations** (`lib/i18n/`, community-maintained through the website) | `ezkey` namespace in en and fr only; other locales fall back to English | Decide how the `ezkey` strings reach other locales without entering upstream's community pipeline | L1 | New files only | Low |
| H14 | **Images / logos cache** (`TotpImageCacheManager`) | EzKey shows its own logo, no per-integration image | Possibly show integration or installation branding (signed instance-info, #26) through the same cache | L2 | Upstream cache manager (read only) | Low |

## Tracking

| Item | Issue | Status |
| --- | --- | --- |
| H1 Clear data | #53 | Done (PR #54): extra warning when enrollments exist, keys deleted right after the clear |
| H2 Backups | #60 | Note in the "Backup now" and restore password dialogs when this device holds EzKey enrollments (not included; enroll again on another device) |
| Anchor-point tests | #55 | Done: home page (PR #56), `otpauth://` parsing (PR #57), deep links (PR #58), backups (`model/backup/`, with a committed fixture), Clear data (covered by the hook tests of PR #54) |
