# ADR-0006: Checking for requests one enrollment at a time

- **Status:** Accepted (2026-11-06)
- **Issue:** #99. Replaces the scan introduced in #35 and refines ADR-0003 D1.

## Context

EzKey has no push: the user asks whether a request is waiting (EzKey ADR-0002). Until now, the home zone's "Check for requests" button and a tile on the EzKey page checked every enrollment in turn and opened the first attempt claimed. The goal was one tap for the daily login. The reference app does the opposite: Home does not trigger `pending`, and the user goes from Home to the enrollment's detail, then checks that enrollment (`ezkey_mobile/docs/MOBILE_API_MAPPINGS.md`).

An authenticator is a mandatory passage on the way to the application the user wants. A person usually holds few enrollments: most often one or more regular integrations, possibly one administrator enrollment, and sometimes several EzKey installations. The decision must keep that passage short and leave no ambiguity.

The scan does not fit the protocol or this goal:

- **A claim is one-shot** (contract §1.1) and leaving the approval page denies the attempt. A scan can claim an attempt on an enrollment the user was not aiming at, which primes an approval they did not start, the pattern EzKey's user-initiated model is meant to avoid.
- **Failures add up.** Checks run in sequence, so one unreachable server adds up to 15 s to every check (SDK default timeout), against an attempt lifetime of at most 120 s. Running them in parallel is not a safe fix, since each check can claim.
- **Failures hide the answer.** One revoked enrollment replaces "no request" with an unnamed error on every check.
- **Several attempts need sequencing.** Only the first is shown; the others wait unseen. Handling this properly means an on-screen queue and per-enrollment error screens: accidental complexity, out of proportion for a few entries.

## Decision

1. **A check targets one enrollment.** `EzkeyActions.checkPending` takes one enrollment, and the app has no scan.
2. **Each home row has its own "Check" button.** A login stays one tap, and the user names the service they are signing in to. It carries its own semantics label naming the service.
3. **The rest of the row opens the enrollment page**, as before. It keeps its own check, for a user who wants to read the details first. A tap meant to read details never claims an attempt.
4. **The EzKey page has no check.** It keeps settings and the list of enrollments, each leading to its page.

## Alternatives

- **Keep the scan and open a dedicated screen for each special case.** Rejected: it keeps the queue, the partial failures and the priming, and adds screens.
- **The reference app's path only: row, detail, then check.** Rejected: strictly canonical, but one more tap and one more screen on every login. It remains available through the enrollment page.
- **The whole row checks, with details behind a secondary control.** Rejected: a tap meant to read details could claim an attempt, and leaving would then deny it.

## Consequences

- **Difference from the reference app, kept on purpose:** the check starts from Home. It stays explicit and limited to one enrollment, so it keeps the reference's intent.
- **An unexpected attempt on another enrollment is not shown.** It expires unseen, as in the reference app. The scan would have shown it, at the cost above.
- **The row must identify the service without ambiguity**, since the user now chooses by it. This raises the priority of the identity work in #26.
- **Not solved by this decision, since the scan did not cause them:** tapping before the server has the attempt still answers "no request", and a collapsed zone still takes one more tap to reach the rows.

## References

- EzKey client behaviour contract §1 (one-shot claim), EzKey ADR-0002 (user-initiated checks), `ezkey_mobile/docs/MOBILE_APP_STATE_MACHINE.md` § Enrollment Detail → claim pending.
- ADR-0003 (home screen).
