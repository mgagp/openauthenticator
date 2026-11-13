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
- **Divergence cost**, in three kinds. Weigh each one separately, because a change can be free on one and costly on another:
  1. **Sync cost:** how easily the item re-applies after an upstream sync (ADR-0003). It depends on the upstream files touched and how often upstream changes them ([`../upstream-activity.md`](../upstream-activity.md)). It counts more than the size of the diff.
  2. **Product divergence:** how far the app looks or behaves differently from upstream, even when all the code lives under `lib/ezkey/`. Example: buttons added to the TOTP zone header (H15). Changes to the parts the user knows as upstream's (TOTP list, settings, dialogs) are the user's decision.
  3. **Offer cost:** what upstream would have to accept if the work were offered to it: new UI in its own parts, new or changed strings in its five community-maintained locales, new dependencies.
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
| H4 | **App unlock** (`model/app_unlock/`, unlock challenge wrapping the app) | Already protects EzKey, since the zone is inside the app. It overlaps with EzKey's "confirm before approvals" (#34) | Explain how they combine. Possibly suggest "confirm before approvals" when app unlock is off. **Done in #83**: the confirmation is the app unlock method (upstream's sensitive-action check), or the device credential when there is none. The suggestion is still open | L1 | EzKey settings only | Medium |
| H5 | **Master password / crypto store** (`model/crypto/`) | EzKey records are not encrypted with the master password (ADR-0002: secure storage plus non-exportable keys) | Decide whether EzKey should follow the master password (e.g. lock approvals until unlocked). Needs an ADR. **Partly done in #83**: when the app unlocks with the master password, "confirm before approvals" asks for it. Encrypting the records is not planned (see the parity section) | L1–L2 | Upstream providers (read only) | Low (analysis first) |
| H6 | **QR scanner** (`pages/scan.dart`: parses `otpauth` URIs) | Separate EzKey scanner (`ezkey/pages/scan_page.dart`) | One scanner that recognizes both an `otpauth` URI and an EzKey invitation, routing each to its flow | L2 | Upstream scan page (small, ledgered edit) or a wrapper | Medium |
| H7 | **Add flow** (home `+`, `onAddButtonPress`) | Two `+` buttons, one per zone (ADR-0003) | Possibly one "Add" that offers both, depending on the home-zone evolution (#32 / #44) | L2 | Upstream home dialog (ledgered) | Low |
| H8 | **Deep links** (`model/app_links/`: `otpauth://`, `openauthenticator://`) | EzKey invitations cannot be opened by a link | Route an EzKey invitation link to the enrollment flow, if EzKey defines one | L1–L2 | Upstream link listener (a new handler) | Low (depends on EzKey) |
| H9 | **Search** (home search over TOTPs) | Does not see EzKey enrollments | Include enrollments in the results, or keep search TOTP-only on purpose | L2 | Upstream search (ledgered) | Low |
| H10 | **Settings page** (`pages/settings/`) | EzKey settings live on the EzKey page (#33); the Settings entry was removed in #28 | Decide whether an "EzKey" section belongs in Settings, for discoverability and consistency | L1 | Upstream settings page (ledgered) | Low |
| H11 | **Onboarding** (`pages/intro/`) | No mention of EzKey | One optional intro step, shown only where EzKey is available | L1 | Upstream intro (ledgered) | Low |
| H12 | **Error handling** (`utils/result/`, `handler.dart`, Sentry) | EzKey has its own toasts (`ezkey/toast.dart`) and messages | Route EzKey errors through `Result` and the handler where it fits; decide what Sentry may receive (never EzKey payloads) | L2 | New code in `lib/ezkey/` using the upstream handler | Medium |
| H13 | **Translations** (`lib/i18n/`, community-maintained through the website) | `ezkey` namespace in en and fr only; other locales fall back to English | Decide how the `ezkey` strings reach other locales without entering upstream's community pipeline | L1 | New files only | Low |
| H14 | **Images / logos cache** (`TotpImageCacheManager`) | EzKey shows its own logo, no per-integration image | Possibly show integration or installation branding (signed instance-info, #26) through the same cache | L2 | Upstream cache manager (read only) | Low |
| H15 | **Home zone headers** (fork code: `_TotpHeader` in `lib/ezkey/home_zone.dart`) | The EzKey header has ⓘ (about) and a settings shortcut; the TOTP header has neither | **Decided (2026-11-13, #69): the TOTP header stays minimal on purpose.** EzKey is the new part, so its header explains it and opens its settings. The TOTP part is what the user already knows, a settings shortcut there would repeat the top bar's, and a change would make upstream's part look different for symmetry only. If the question comes back, the cheapest variant is the ⓘ alone, with upstream's `intro.welcome.firstParagraph`, which exists in the five locales | L1 | None: nothing is built | Decided: no change |
| H16 | **Backups, export and import** (`model/backup/`) | Backups say that enrollments are not included (H2), but they keep no record of them | Add an inventory of enrollments to backups (service, tenant, server, date; never a key), so that a restore lists what to re-enroll | L1–L2 | Upstream backup format. **Decided in [ADR-0005](../adr/0005-ezkey-enrollment-inventory-in-backups.md) (#89)**: a fourth key inside the `.bak`, encrypted with the backup password; compatibility pinned by a fixture test. Writing and reading done (#92); the EzKey page lists "to re-enroll" after a restore (#94), and the home zone leads to it (#96) | Medium |
| H17 | **Recovery after restore or device change** | Each administrator has to send a new invitation | A device-replacement or re-enrollment flow. EzKey first: it is beyond EzKey's reference app | L2 | EzKey protocol, then a new EzKey page | Low (depends on EzKey) |
| H18 | **Delete account / unenroll** (`delete_account.dart` for the backend account) | "Remove" is local only: the server enrollment stays active (no device-side unenroll in the Auth API) | Unenroll from the server when the user removes an enrollment or clears data. EzKey first | L1 | EzKey Auth API, then the existing remove action | Medium (depends on EzKey) |

## Parity with Open Authenticator's features

Open Authenticator is built around a few promises: secrets encrypted under a master password, backups that can be exported and re-imported on another device, optional sync, and app unlock. EzKey cannot simply copy these promises. Its device key is created inside the hardware key store (StrongBox, TEE, later Secure Enclave or a TPM, ADR-0002), and nothing can export it. This section sorts every upstream feature by what it can mean for EzKey, so that the app keeps its character without promising what the hardware forbids.

Some equivalents go beyond what EzKey's reference mobile app does, for example an inventory of enrollments in backups. Raise them with the EzKey project before building anything that needs a change on its side.

**Categories:**
- **Shared:** the feature already serves EzKey as it is.
- **Equivalent:** a different mechanism keeps the same promise for EzKey.
- **By design:** parity is impossible, because the key cannot leave the device. The app says so instead of staying silent.
- **EzKey first:** an equivalent needs a change in EzKey (protocol, Auth API or SDK) before the app can offer it.
- **Not applicable:** the feature has no EzKey meaning.

| Feature (upstream) | Category | What it means for EzKey | Item |
| --- | --- | --- | --- |
| **Master password**: TOTP secrets encrypted with the derived key (`model/crypto/`) | Equivalent | The secret that matters, the device key, is protected by the hardware, not by the master password. The equivalent of the promise "nothing works without me" is a **gate on key use**: local confirmation before approvals (#34), possibly with the master password as the confirmation method, or a hardware key that requires user authentication. Encrypting the enrollment records under the master password adds little, since they hold no secret that can sign | H5, H4 |
| **Change master password** (re-encrypts every TOTP) | Not applicable, unless H5 encrypts records | Nothing to re-encrypt today | H5 |
| **Save derived key** | Not applicable | — | — |
| **App unlock** (none, local auth, master password) | Shared | It already protects the EzKey zone. Its overlap with "confirm before approvals" is still to be explained | H4 |
| **Backup now / Export** (encrypted file, shareable) | By design for the key; Equivalent for an **inventory** | The key cannot be backed up. A backup could carry the list of enrollments (service, tenant, server, date, no key) so that after a restore the user knows what to re-enroll. Today the dialogs only explain the absence (PR #61) | H2 → H16 |
| **Import / Restore** a backup on another device | By design for the key; EzKey first for a **recovery flow** | Restoring cannot bring enrollments back. With an inventory, a restore could list "to re-enroll". Re-enrolling still needs a new invitation from each administrator, unless EzKey defines a device-replacement flow | H2 → H16, H17 |
| **Sync / shared storage / account** (`model/backend/`) | By design | Each device enrolls on its own. Several devices for one person means several enrollments, which EzKey allows. Say "this device only" on the EzKey screens | H3 |
| **Contributor Plan TOTP limit** | Not applicable | Enrollments do not count toward the TOTP limit, which exists to protect the sync server | — |
| **Clear data** | Shared, made aware | Done: warning and immediate key deletion | H1 |
| **Delete account** | EzKey first | The closest equivalent is unenrolling from the server. The Auth API has no device-side unenroll, so "remove" is local only and the server enrollment stays active | H18 |
| **Add by QR, manually, deep link** | Shared / Equivalent / EzKey first | QR: done, one scanner for both (H6). Manual entry: debug only (#38); it is needed on desktop (ADR-0004 D5). Deep link: EzKey has no link format yet | H6, H8 |
| **Search, logos, copy button** | Equivalent / Not applicable | Search over enrollments is to decide; logos through signed instance info (#26); copying has no EzKey meaning | H9, H14 |
| **Theme, locale, onboarding, translations** | Shared / Equivalent | The theme and the locale already apply to EzKey. An intro step and the other locales are still to do | H11, H13 |
| **Change backend URL** | Not applicable | Each enrollment carries its own Auth API URL | — |
| **Legacy migrator** | Not applicable | — | — |

**Order the categories suggest:**
1. Equivalents that protect the user: the key-use gate (H4, H5).
2. The inventory in backups (H16). Decided in ADR-0005 (#89); written and read (#92), shown as "to re-enroll" after a restore (#94).
3. "EzKey first" items (H17, H18, H8), raised in the EzKey repository; the app follows once EzKey supports them.

## Tracking

| Item | Issue | Status |
| --- | --- | --- |
| H1 Clear data | #53 | Done (PR #54): extra warning when enrollments exist, keys deleted right after the clear |
| H2 Backups | #60 | Done (PR #61): note in the "Backup now" and restore password dialogs when this device holds EzKey enrollments (not included; enroll again on another device) |
| Anchor-point tests | #55 | Done: home page (PR #56), `otpauth://` parsing (PR #57), deep links (PR #58), backups (`model/backup/`, with a committed fixture), Clear data (covered by the hook tests of PR #54) |
| H6 QR scanner | #64 | Done (PR #66, checked on the Pixel): both scanners take both kinds of code: upstream's sends an EzKey invitation to the enrollment flow (the enroll page takes the scanner's place, like upstream's TOTP page), EzKey's sends a TOTP code to upstream's TOTP page. Upstream's scanner characterized first (PR #65) |
