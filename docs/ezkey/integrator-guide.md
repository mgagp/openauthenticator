# Integrator guide: adding EzKey to an existing mobile app

**Status: draft.** It comes from one integration, Open Authenticator (Flutter), checked on Android devices only. It grows with each lesson, and its test is in [§14](#14-how-this-guide-is-tested).

## Who this is for

You have an existing mobile app, your own or a fork, and you want it to act as an EzKey authenticator: enroll the device, then approve or deny sign-in requests. You may be a person or a coding agent starting cold.

**Check that you have the right SDK.** EzKey has two kinds:

| SDK | Used by | Talks to | This guide? |
| --- | --- | --- | --- |
| Authenticator SDK (`ezkey_dart` here) | An app that holds the device key and approves requests | Authentication API | Yes |
| Integration SDK | An application protected by EzKey, which creates the requests | Integration API | No |

This guide does not restate the protocol. It says what to decide, in what order, and what is easy to get wrong. The protocol and the required client behaviour stay in the [sources](#3-read-these-first).

## 1. Build your compass first

Every choice below is weighed against this:

- **The authenticator is never the core business.** The user's goal is to log in to an application. This app is a mandatory passage on the way there, so it is a friction point to minimize.
- **The information must be quick to read**, for a quick security posture: which service, which account, and whether it is an administrator enrollment.
- **Expect few entries.** Most often one or more regular integrations, possibly one administrator enrollment. Several EzKey installations on one phone are possible but not the general case. Be general enough that nothing is ambiguous, and do not design for a long list.

Before adopting a feature, walk through a real login with it, including its failure cases: an unreachable server, a revoked enrollment, a tap made too early. A shortcut that looks good on the success path can hide a cost there (§6).

State your assumptions about usage as assumptions, and have the product owner validate them.

## 2. Decide your relation with the host app

- **If you fork an app you do not own,** being able to re-apply your work after an upstream update is the main cost. Put your code in new files, and limit upstream files to small hooks.
- **Keep a ledger of every upstream file you touch,** precise enough to re-apply after a sync. See [`integration.md`](integration.md) § Upstream files touched.
- **Judge an upstream change by how easily it can be re-integrated,** not only by its size. A structural change to a stable screen can be cheaper than many scattered hooks (ADR-0003).
- **Before changing a host feature, pin its behaviour with tests,** in their own PR. Otherwise you cannot tell what you broke (#56, #57, #58, #59, #65).
- **Pin the SDK to a commit,** and read its changes when you move the pin (ADR-0001).
- **Put native code in a local plugin,** so the host's platform files stay untouched (ADR-0001).
- **Take no initiative on the host's dependencies, formatting or refactors.** Note what you find and leave it. If the host has no lock file, pin yours and the toolchain's version, so builds and tests are reproducible (#7, #9).
- **Weigh three costs separately:** re-applying after a sync (check how often upstream changes each file), the app looking different from the original even with your own code, and what upstream would have to accept if the work were offered to it (#70).
- **Agree on what needs the owner's word first:** host files you have not touched yet, the host's strings, dependencies, crypto and stored data, real devices (#72).
- **Make the integration disappear where it is not available.** Where EzKey is off, the app must look like the original (ADR-0004).

If you own the host app, the ledger is optional. The other rules still pay off.

## 3. Read these first

All in the EzKey repository, in this order:

1. `docs/CLIENT_BEHAVIOUR_CONTRACT.md`: what a client MUST, SHOULD and MAY do between API calls.
2. `ezkey_dart/README.md`: the SDK API, the storage hooks and the security pitfalls. It has known gaps with the rest of the canon: see [`integration.md`](integration.md) § Findings.
3. `product-docs/global/architecture-decisions.md` ADR-0002: user-initiated checks only. The contract does not say it yet.
4. `ezkey_mobile/docs/MOBILE_POSITIONING.md` § Enrollment identity vocabulary: the words to show the user.
5. `ezkey_mobile/docs/MOBILE_APP_STATE_MACHINE.md`: the edge cases of the reference app.
6. `ezkey_mobile/docs/MOBILE_DATA_MODEL.md` § Installation Trust Zone.

The reference app shows one valid answer, not the only one. When you differ from it, keep its intent, and write down the difference and why.

## 4. Keys and storage

- **Implement the key store on the platform's hardware,** and never offer software keys. On Android: Keystore, StrongBox when available, falling back to the TEE (ADR-0002, ADR-0004).
- **Report the storage tier honestly.** Read it back from the generated key, never from what was requested, and report what it is, even `none`, rather than refuse the key: a minimum tier is the server's to enforce (#108). It is per key, because StrongBox can be unavailable for one generation. It is self-reported: do not describe it as attested.
- **Do not bind the key to user authentication.** Every check signs with it, so the user would be prompted on every check. A local confirmation belongs at the app level, on Approve only (contract §4).
- **Store enrollment records in the app's existing secure storage,** after checking that it is excluded from cloud backup and device transfer.
- **Keep them apart from the host's own secrets model.** Encrypting records with the host's vault password would tie approvals to it and mix two security models (ADR-0002).
- **Scope everything by server address and enrollment id.** An enrollment id is only unique per server.
- **Show an unreadable record as unusable,** with a way to remove it. Do not let it disappear silently.

## 5. Enrollment

- **Take the enrollment id from the bind answer, never from the invitation.** The invitation holds the proof token and, optionally, the server address (EzKey ADR-0019). Let the SDK parse it, and do not read its fields yourself: this app needed no code change when the id left the invitation (#129).
- **The invitation may carry no server address,** so be ready to ask for it, and validate it with the SDK's URL policy.
- **Require HTTPS in release builds.** The SDK's default policy also accepts plain HTTP to `localhost`, `127.0.0.1` and `10.0.2.2`, as the reference app does. Keep that for debug builds, where a local stack and an emulator need it, and pass `EzkeyUrlPolicy.httpsOnly` elsewhere (#109). The SDK refuses an address with the same exception as an invitation already enrolled, so check the address first to tell the user the real reason.
- **Scanning is the release path.** The QR content carries a bearer token, so typing or pasting it belongs in debug builds unless you decide otherwise for a platform with no camera (ADR-0004 D5).
- **Show who the enrollment is for before the challenge:** service, organization, account, server, and whether it is an administrator enrollment.
- **Warn before the code is submitted,** since a wrong code invalidates the invitation.
- **If the host has its own scanner, make both recognize both kinds of code,** so the user cannot scan at the wrong place (#66).

## 6. Checking and approving

This is the daily path, and the core of the integration.

- **A check targets one enrollment.** A claim is one-shot, and leaving the approval screen denies the attempt. Do not scan every enrollment from one button: it can claim an attempt the user was not aiming at, and it brings waits, hidden errors and on-screen queues. We built this scan and removed it (ADR-0006).
- **Checks are user-initiated.** No push, no background polling, no check when the app returns to the foreground: this is a stance against push fatigue, not a missing feature (EzKey ADR-0002). The SDK's `pollPending` and `watchPending` are not for this path.
- **Keep the path short:** one tap from the home screen to the check. We put a button on each row. The rest of the row opens the details, so reading the details can never claim an attempt.
- **Show nothing from a pending response until its signature verifies.** On failure, send nothing (the SDK raises the error).
- **Decide your error copy from the exception type and problem kind,** never from the server's text (contract §7).
- **Treat an unknown outcome as uncertain, not as a failure.** Offer no retry (contract §2).
- **Follow the SDK's decision lock** for the buttons, and close the page once a decision is sent (#23).
- **A confirmation before Approve is the user's choice to make.** Reuse the app's unlock method rather than adding a second one (#40, #84). A cancelled confirmation sends nothing and keeps the attempt open. Deny and leaving never ask (#25).
- **Protect the switch too.** Turning the confirmation off needs the same confirmation, so someone holding an unlocked phone cannot remove it just before approving (#40).

## 7. The identity you show

- **Use one vocabulary on every screen:** Installation, Purpose, Account, Role, Device. The same string must not appear at two levels (`MOBILE_POSITIONING.md`).
- **The row must identify the service without ambiguity,** since the user chooses by it. Check this with long names: a line cut in the wrong place can remove the account.
- **An installation is identified by its normalized server address.** Its signed name is display only, and never a trust anchor.
- **Add structure only when it removes an ambiguity.** Frames, headers and collapsible groups cost height and taps on a list of few entries. This app stays flat and names the server when the device has several installations (ADR-0007). The reference app frames each one. Both are defensible; choose from the data you expect.
- **Build the identity in one place,** and use it on the row, the details, the invitation and the approval. An administrator reads "Administration" with the role, and no organization.
- **Order a one-line summary by what must survive a cut:** the role, the account, then the organization.

## 8. Placing it in the host's home screen

- **Put the daily action on the home screen, not under Settings.** There is no push, so opening the app and checking is the normal path (ADR-0003).
- **Share the screen without taking it over.** Where no enrollment exists, keep the integration's presence small, and keep the host's own content intact when the user collapses a zone (#37).
- **Let the user divide the screen.** Each zone can collapse, never both at once, and a divider sets their heights (#62, #67).
- **Give each enrollment a page** for its details and its removal, so the row stays short (#43).
- **Do not reuse the host's look for what is not the host's.** A distinct color and logo tell the user which part they are in.
- **Leave the host's own strings alone.** Keep yours in your own namespace, so community translations stay untouched.

## 9. Walk through the host's features

Go through every host feature and ask what it means for an enrollment. [`harmonization.md`](harmonization.md) is the worked example. The ones that mattered here:

| Host feature | Question | What we did |
| --- | --- | --- |
| Backup and restore | Keys cannot leave the device: what does the user lose, and how do they find out? | Say so in the dialogs (#61). Keep an encrypted list of what to re-enroll in the backup file, display data only (ADR-0005). After a restore, show the list and lead to it from the home screen. An entry leaves once it is enrolled again (#95, #97) |
| Clear data | Does it leave keys behind, or remove enrollments silently? | Warn, and delete the keys at once (#54) |
| App unlock | Does the app's lock also protect approvals? | Reuse it for the confirmation (#84) |
| Scanner | Which scanner does the user open? | Both recognize both codes (#66) |
| Sync across devices | Could enrollment data travel with it? | Keep it out: an enrollment belongs to one device |

## 10. Testing

- **Test your logic without a device,** with a mocked key store channel and in-memory stores. Keep the tests deterministic.
- **Prove that the tests can fail:** break the code, see red, restore.
- **Run the key store contract test on each real key store** (ADR-0004 D6).
- **Use a live stack for the whole path:** enroll, check, approve, forget. Script it, so an agent can run it on an emulator.
- **Keep a real device for the final checks,** with its owner's agreement: emulators often lack a secure element. Never run anything that erases the real data on it.
- **Test accessibility with semantics-enabled widget tests,** not with manual passes.
- **Build every platform in CI** when the host supports several. Transient download failures happen, so read the log before concluding.

## 11. Gotchas

| Gotcha | What happens | What to do |
| --- | --- | --- |
| High-S signatures from Android Keystore | About half are rejected by the server | The SDK normalizes them. Do not re-implement this in the plugin |
| Debug and release builds on one device | Separate secure storage, but shared Keystore keys. Orphan cleanup in one build deleted the other's keys | Scope cleanup to the build's namespace, and do not switch build types on a device you care about (#41) |
| Uninstalling the app | Removes the enrollments, and the server still lists them | Tell the user that an administrator must revoke them. Never uninstall on a device without asking |
| `forget` is local | The server-side enrollment stays active | Say so in the removal copy |
| A claimed attempt lives in memory | If the app dies before the decision, the attempt simply expires | Accept it |
| Starting the app behind the lock screen, with biometric unlock (Flutter `local_auth`) | The prompt is refused silently, and the app stays locked until force-stopped | Left as a known limit: only a start through adb was seen to cause it (#98, which holds the diagnosis). In device scripts, check that the device is unlocked first |
| Icon button inside a list tile (forui) | The tile merges its semantics, leaving a button with no name | Give the button its own semantics node, and test it |
| Widget tests run as Android | Availability is true, so tests reach the real secure storage plugin | Override the enrollment store in any test that shows the zone |
| Automated device tests | The screen locks during a long step, and later taps land on the lock screen | Check the lock state before each tap sequence |
| A tap on a toast's body (forui) | It stops the auto-dismissal with no visible change, so the toast looks stuck and can cover the back arrow. A second tap restarts it | Know it before chasing a bug (#103). Changing it means changing the toaster at the host's root |
| Focus in a text field of forui 0.25, with semantics enabled | A framework assertion fails in debug, and later taps can reach stale controls. It is a forui bug, fixed in 0.26 (#47) | Keep semantics off in tests that type, and test screen readers on the other controls, until the host moves to a fixed version |

## 12. Do and do not

**Do:**

- Walk through a real login, including its failures, before adopting a shortcut.
- Record each decision where it applies, with its alternatives when someone could reopen it.
- Record what you learn about the SDK and its docs, and send it back.
- Keep the check explicit, and limited to one enrollment.

**Do not:**

- Add push, background polling or a check on resume.
- Back up keys, or claim that a backup restores enrollments.
- Show the server's error text.
- Treat instance branding as proof of anything.
- Describe a self-reported key tier as attested.
- Build for many entries or many installations before someone needs it.

## 13. Feed what you learn back

You are also testing the SDK. Keep two lists, as in [`integration.md`](integration.md) § Findings: documentation gaps and SDK gaps, each with a suggested action. When a wrong turn could have been avoided by a sentence in the SDK's docs, that sentence is the finding.

## 14. How this guide is tested

**Criterion:** with this guide, a cold agent builds its own compass and reaches the design, implementation and test decisions of this fork.

**Protocol (not run yet):**

1. Give a fresh agent the host app at the fork point, the SDK, its docs and this guide. It gets no access to this fork's history, ADRs or `CLAUDE.md`.
2. Ask it the questions in the ledger below, without the answers.
3. Compare each answer with the final decision: **same**, **defensible** (different, but it would pass the compass), or **miss**.
4. For each miss, either the guide has a gap, or the decision was weak. Change one of them.

**Reversals count.** The target is the final state of a decision, not the commit that first made it. A guide that reproduced every commit would also reproduce our mistakes. So each reversal stays in the ledger as a lesson.

### Decision ledger

Complete up to commit `79f4358`, the 54 commits of `upstream/main..main`. **Reversed** means an earlier choice was replaced: the decision shown is the final one, and it is the target.

**The host app**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| How does a fork stay able to take upstream updates? | New files, small hooks, a ledger | Kept | ADR-0001, #19 | §2 |
| How is the SDK referenced? | A git dependency pinned to a commit, not a path or a vendored copy | Kept | ADR-0001, #91 | §2, §13 |
| Where does the native key store code go? | A local plugin, not the host's platform files | Kept | ADR-0001, #19 | §2 |
| Is a structural change to a host screen acceptable? | Yes, if the screen is stable and the re-apply step is clear | Kept | ADR-0003, #31 | §2 |
| Who decides about the host's dependencies and formatting? | No initiative, with a lock and a pinned toolchain for reproducibility | Kept | #7, #9 | §2 |
| What do you do before changing a host feature? | Pin its behaviour with tests, in their own PR | Kept | #56, #57, #58, #59, #65, #78 to #82 | §2 |
| How is the cost of a change judged? | Three costs: sync, product divergence, offer, using upstream's activity per file | Kept | #52, #70 | §2 |
| What needs the owner's agreement first? | An explicit list, including real devices | Kept | #72 | §2 |
| Is the integration Android-only in shape? | It was. Now portable code, offered only where a hardware key store exists | **Reversed** | #19, ADR-0004, #50 | §2, §4 |
| What does the app look like where EzKey is off? | Exactly like the original | Kept | ADR-0004, #50 | §2 |

**Keys and storage**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| Where does the device key live? | Hardware key store, never software | Kept | ADR-0002, ADR-0004 | §4 |
| Should the key require biometrics? | No: an app-level confirmation on Approve only | Kept | ADR-0002 | §4 |
| Where do enrollment records go? | The host's secure storage, after checking it stays out of cloud backup | Kept | ADR-0002, #19 | §4 |
| Are records encrypted with the host's vault password? | No | Kept | ADR-0002 | §4 |
| Is the key tier described as attested? | No: self-reported, per key | Kept | ADR-0002 | §4 |
| Who normalizes high-S signatures? | The SDK, not the plugin | Kept | ADR-0002, #19 | §11 |
| Which keys may orphan cleanup delete? | It deleted any orphan, and cost a real enrollment. Now only its own build's namespace | **Reversed** | #21, #42 | §11 |

**Enrollment**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| What if the invitation has no server address? | Ask for it, validated by the SDK's URL policy | Kept | #21 | §5 |
| Can an invitation be pasted in release builds? | It could. Now debug only | **Reversed** | #21, #39 | §5 |
| What is shown before the challenge? | Service, organization, account, server, administrator notice | Kept | #21 | §5 |
| What if the user scans in the host's scanner? | Both scanners recognize both kinds of code | Kept | #66 | §5 |

**Checking and approving**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| How does the user check for requests? | One enrollment at a time, from its row | Kept | ADR-0006, #100 | §6 |
| Does one button scan every enrollment? | It did, then was removed | **Reversed** | #23, #35, ADR-0006 | §6 |
| Can a check run by itself? | No: no push, no polling, no check on resume | Kept | #23, ADR-0003 | §6 |
| What happens on leaving the approval page? | One deny is sent, navigation is never held back, and the page says so | Kept | #25 | §6 |
| How are repeated decisions prevented? | The buttons follow the SDK's decision lock | Kept | #23 | §6 |
| Where does error copy come from? | The exception type and problem kind, never the server's text | Kept | #21, #23 | §6 |
| Is a confirmation before Approve on by default? | It was always on. Now off by default, the user's choice | **Reversed** | #25, #40 | §6 |
| Which prompt does that confirmation use? | It was the device's. Now the app's unlock method | **Reversed** | #25, #84 | §6 |
| Can the confirmation be turned off freely? | No: turning it off needs the same confirmation | Kept | #40 | §6 |

**The identity shown**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| What does each screen call an enrollment? | One helper: Purpose, Account, Role, with no repeated label | Kept | ADR-0007, #105 | §7 |
| What does an administrator enrollment show? | "Administration" and the role, no organization | Kept | ADR-0007, #105 | §7 |
| How are installations told apart? | The server was on the EzKey page's rows only. Now a flat list that names it on the home rows and the approval page when there are several, no frames | **Reversed** | #35, ADR-0007, #105 | §7 |
| What gets cut on a long row? | The organization first, never the role | Kept | #105 | §7 |

**The home screen**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| Where does the daily action live? | It was under Settings. Now on the home screen | **Reversed** | #23, ADR-0003, #35 | §8 |
| What does a user with no enrollment see? | Close to the original, with EzKey as a thin bar | Kept | #37 | §8 |
| How do the two zones share the screen? | Each can collapse, never both, and a divider sets the heights | Kept | #62, #67 | §8 |
| Where do an enrollment's details and removal live? | On its own page, not the list | **Reversed** | #21, #43 | §8 |
| Whose strings change? | Only the integration's own namespace | Kept | #52, #72 | §8 |

**The host's features**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| How are host features reviewed? | Each one is sorted by what it means for an enrollment | Kept | #52, #74 | §9 |
| What happens to enrollments on Clear data? | Warn, and delete the keys at once | Kept | #54 | §9 |
| What does a backup keep of enrollments? | It was nothing, with a note. Now also an encrypted list, display data only | **Reversed** | #61, ADR-0005, #90, #93 | §9 |
| Does a restore bring enrollments back? | No: it lists them to re-enroll, and the home screen leads there | Kept | ADR-0005, #95, #97 | §9 |
| Does sync carry enrollments? | No: an enrollment belongs to one device | Kept | #52, #74 | §9 |

**Testing**

| Question | Decision | Status | Source | Guide |
| --- | --- | --- | --- | --- |
| What runs without a device? | The logic, with a mocked channel and in-memory stores, deterministic | Kept | #13, #15, #19 | §10 |
| How is a test trusted? | Break the code, see it fail, restore | Kept | #13 | §10 |
| How is the whole path tested? | A scripted live stack on an emulator: enroll, check, approve, forget | Kept | #21, #46 | §10 |
| When is a real device used? | Final checks, with its owner's agreement | Kept | #42, #72 | §10 |
| How are screen readers tested? | Semantics-enabled widget tests, no manual passes | Kept | #47, #72 | §10 |
| What must CI build? | Every platform the host supports | Kept | #77 | §10 |

### Commits with no question for an integrator

These commits were walked through and left out, because they concern this fork's own setup or only record a decision listed above:

- **Fork tooling and setup:** #2, #5, #11, #87, #88.
- **Records of decisions above, or of this guide:** #18 (the ADRs), #63 (a doc fix), #102 (this guide).
