# ADR-0003: EzKey on the home screen

- **Status:** Accepted (2026-10-29)
- **Issue:** #27; applied by #28 (phase 1). Refines ADR-0001 D3 for the home screen.

## Context

Until now, the EzKey screens could only be reached through Settings → Security. That was the smallest upstream hook (#20).

EzKey has **no push and no automatic polling, by design**: the app checks for pending requests only when the user asks (EzKey ADR-0002, "User-initiated mobile polling", against push fatigue and opaque platform services). So the everyday action is to open the app and check for requests. Enrolling is rare.

The upstream home screen (`lib/pages/home/page.dart`) has two states:
- empty: an illustration, "No TOTP for the moment", and a floating green + on Android;
- filled: a scrolling list of TOTP cards.

Every add path goes through `onAddButtonPress`, which opens the "Add a TOTP" dialog (QR code / manually / cancel).

Upstream is mature. Since 2026-04-30 the home folder has received 4 commits, all refactors or dependency updates and none a layout change. The last was on 2026-06-10, and the last upstream commit overall on 2026-08-15. A structural change to this screen is therefore unlikely to fight frequent upstream work.

## Decision

1. **Two framed zones on the home screen.**
   - **Zone 1 (TOTP):** the upstream content (empty state or card list) and its green +.
   - **Zone 2 (EzKey):** built on the same pattern, with the EzKey logo and the enrollments. "Check for requests" is visible as soon as one enrollment exists, and a blue + (the logo's color) leads to scanning or entering an invitation.

   Tapping an enrollment opens the existing EzKey page. The Settings entry is removed, so the total number of upstream hooks stays small.
2. **Phases.**
   - Phase 1 (#28) shows enrollments with the current summary display (one line each).
   - EzKey's richer concepts come later, one issue per phase (#26): trust zones per installation (normalized Auth URL, signed instance name), tenant groups, the admin / regular distinction, and visual polish.
3. **Built to evolve without breaking.**
   - The EzKey zone is a self-contained widget under `lib/ezkey/`.
   - One enrollment row widget is shared by the home zone and the EzKey page.
   - The data handed to the UI is grouped by installation even while phase 1 shows it flat, so adding trust-zone frames changes the display, not the data shape.
4. **Upstream changes judged by how easily they can be re-integrated, not only by their size.** This refines ADR-0001 D3 ("hooks only"):
   - A deeper change to an upstream file is acceptable when the screen is stable upstream and the ledger in `docs/ezkey/integration.md` states how to re-apply the change after an upstream sync.
   - When syncing, take upstream's version, re-apply the listed change, and run the checks.

## Alternatives considered

- **One unified dialog** ("Add an authentication method" with QR / manually). Rejected:
  - "Manually" means different things (a TOTP form vs pasting an invitation).
  - It changes a title translated in five community-maintained locales.
  - It would teach the scan page to recognize EzKey invitations.
  - Checking for requests would still be off the home screen.
- **A third choice in the upstream "+" dialog.** It is a small change, but the dialog title ("Add a TOTP") becomes wrong, and checking for requests is still off the home screen.
- **A chooser behind the "+"** (TOTP or EzKey, then the original dialog). It is the least intrusive, but adds a tap to every TOTP add and leaves checking for requests off the home screen.
- **An EzKey icon in the top bar.** The hook is tiny, but EzKey stays hidden: the home screen still says "No TOTP for the moment" to a user who has EzKey enrollments.
- **Notifications for new requests.** Excluded by EzKey ADR-0002.

## Consequences

- The fork diverges in the home screen's structure, not just in an entry point. The ledger records the exact change and how to re-apply it. If upstream ever redesigns this screen, the zones are re-applied on the new layout.
- The TOTP zone keeps upstream's strings, including "No TOTP for the moment", which stays accurate inside its own zone.
- Phase 1 does not show which EzKey installation an enrollment belongs to. With enrollments from several self-hosted installations, the server host on each line is the only clue until the trust-zone phase.

## References

- EzKey ADR-0002, "User-initiated mobile polling": `product-docs/global/architecture-decisions.md` (EzKey repo).
- EzKey reference app home: `ezkey_mobile/app/screens/Home/HomeScreen.tsx`, `ezkey_mobile/docs/MOBILE_DATA_MODEL.md` § "Installation Trust Zone".
- Display concepts to bring gradually: #26.
