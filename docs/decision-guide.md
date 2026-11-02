# Decision guide

How decisions are made in this fork: when to stop and ask the maintainer, what to weigh before proposing a change, and where to record the outcome. It gathers rules that live in several places and links to them. The links stay the source of truth.

This guide is meant to evolve: when a decision shows that a trigger or a check is missing, add it in the PR that records that decision.

## Ask the maintainer first

Stop and ask before acting when a change:

1. **Touches an upstream file** that the ledger does not already list ([`ezkey/integration.md`](ezkey/integration.md) § Upstream files touched), or makes a listed hook bigger.
2. **Changes what the user sees or does in upstream's own parts**: the TOTP list and zone, settings, dialogs, onboarding. This applies even when all the code lives under `lib/ezkey/` (product divergence, [`ezkey/harmonization.md`](ezkey/harmonization.md) § Method).
3. **Adds or changes strings in upstream's namespaces.** Upstream's five locales are maintained by its community. Fork strings go in the `ezkey` namespace (H13).
4. **Adds a dependency** or changes a version range. `CLAUDE.md` § Upstream alignment applies: the fork takes no initiative on dependencies.
5. **Involves crypto, authentication, stored secrets, sync or data migration.**
6. **Acts on a real device or on shared state**: installing on the Pixel, switching build types, anything that can erase enrollments or TOTPs, or a live EzKey stack's database (`CLAUDE.md` § Android device build, § On-device tests).
7. **Changes the workflow or this guide's rules**, including `CLAUDE.md`.

Who merges what is set in `CLAUDE.md` § Development workflow, step 5. When unsure which side a change falls on, treat it as the maintainer's.

## Before proposing a change

- **Track:** EzKey or Open Authenticator harmonization. Propose one item per track and alternate ([`ezkey/harmonization.md`](ezkey/harmonization.md) § Two tracks).
- **Integration level:** L0 alongside, L1 aware, or L2 shared.
- **The three costs, weighed separately:**
  - **sync:** check the [upstream activity map](upstream-activity.md) for the files touched;
  - **product divergence;**
  - **offer.**

  A change can be free on one and costly on another.
- **Anchor point:** prefer, in this order, a new file, then an existing upstream extension point, then a small ledgered edit.
- **Characterize first:** pin the anchor point's current behaviour with tests in a test-only PR before changing it.
- **Portability:** nothing Android-only ([ADR-0004](adr/0004-ezkey-multi-platform-posture.md)). Where EzKey is unavailable, the app must look like upstream.
- **Alternatives:** state them. If someone could reasonably reopen the choice, it needs an ADR ([`README.md`](README.md) § Writing an ADR).

## Recording the outcome

- The decision goes in the PR that applies it: a line in the owning document, or an ADR ([`README.md`](README.md) § Rules).
- An open question gets an issue that lists what is known and what is to be decided, and a line in the owning dossier. For an example, see #69 and H15.
- Upstream file changes get a ledger entry precise enough to re-apply after a sync.
