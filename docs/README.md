# Fork documentation

Decision records and design notes for this fork. `CLAUDE.md` holds the operating instructions (toolchain, commands, workflow); this folder holds the **why**: decisions, trade-offs and designs that future sessions must be able to rely on.

## Direction

This fork explores integrating EzKey into Open Authenticator while staying aligned with upstream (`CLAUDE.md` § Upstream alignment). Every divergence is kept small, ledgered and easy to re-apply, so that the work can either be offered upstream or stand on its own. Every platform upstream ships stays buildable ([ADR-0004](adr/0004-ezkey-multi-platform-posture.md)). The work alternates between the EzKey track and the harmonization track ([`ezkey/harmonization.md`](ezkey/harmonization.md)).

This direction evolves with the project. When it changes, update this section in the PR that records the change.

## Rules

1. **One canonical place per concept.** Link to the source of truth; never copy it. EzKey protocol and behaviour live in the EzKey repository (`mgagp/ezkey`): link them, do not restate them.
2. **A decision is recorded in the PR that applies it.** One line plus the reason in the owning document, or an ADR when the trade-off needs explaining. A decision that only exists in a chat or an issue comment is unrecorded.
3. **Write only what will steer a future judgment.** No narration of the code (the code says *what*), no copies of external docs, no status reports. If a document no longer guides any decision, archive or delete it.

## Index

| Document | Use it for |
| --- | --- |
| [`test-plan.md`](test-plan.md) | What to test first, at which level, and the known seams and gaps |
| [`upstream-activity.md`](upstream-activity.md) | How often upstream changes each area and each file the fork touches: the sync cost of a divergence |
| [`ezkey/integration.md`](ezkey/integration.md) | EzKey integration design: layers, contract conformance, upstream files touched, lab setup |
| [`ezkey/harmonization.md`](ezkey/harmonization.md) | EzKey × Open Authenticator features: the two tracks, integration levels, inventory of upstream features, tracking |
| [`decision-guide.md`](decision-guide.md) | When to ask the maintainer, what to weigh before proposing a change, where to record the outcome |
| [`adr/`](adr/) | Decisions with real trade-offs (below) |

### Architecture decision records

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](adr/0001-ezkey-integration-divergence.md) | How the fork diverges from upstream for the EzKey integration | Accepted |
| [0002](adr/0002-ezkey-key-and-secret-storage.md) | Where the EzKey device key and enrollment secrets live on Android | Accepted |
| [0003](adr/0003-ezkey-on-the-home-screen.md) | How EzKey appears on the home screen, in phases, and how upstream changes are judged by re-integration | Accepted |
| [0004](adr/0004-ezkey-multi-platform-posture.md) | How EzKey stays portable to every upstream platform: availability rule, one key store channel contract, tiers, desktop enrollment | Proposed |
| [0005](adr/0005-ezkey-enrollment-inventory-in-backups.md) | EzKey enrollment inventory inside the backup file, encrypted, display data only, so a restore lists what to re-enroll | Accepted |
| [0006](adr/0006-ezkey-check-per-enrollment.md) | Checking for requests one enrollment at a time, with a button on each home row | Accepted |

## Writing an ADR

Use an ADR when a decision has alternatives that someone could reasonably reopen; otherwise a line in the owning document is enough. File name: `adr/NNNN-short-slug.md`, numbered in order. Sections: **Status** (Proposed / Accepted / Superseded by NNNN), **Context**, **Decision**, **Alternatives considered**, **Consequences**, **References**. Keep it to a page. When a decision changes, write a new ADR that supersedes the old one and mark both; do not rewrite history.

## Where things live outside this folder

- EzKey vision for this integration: [`V-2026-10-27-third-party-authenticator-integration-kit`](https://github.com/mgagp/ezkey/blob/main/product-docs/global/vision/V-2026-10-27-third-party-authenticator-integration-kit.md) (EzKey repo).
- EzKey client behaviour contract: [`docs/CLIENT_BEHAVIOUR_CONTRACT.md`](https://github.com/mgagp/ezkey/blob/main/docs/CLIENT_BEHAVIOUR_CONTRACT.md) (EzKey repo).
- EzKey Dart SDK guide: [`ezkey_dart/README.md`](https://github.com/mgagp/ezkey/blob/main/ezkey_dart/README.md) (EzKey repo).
