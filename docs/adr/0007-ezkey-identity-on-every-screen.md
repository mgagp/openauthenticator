# ADR-0007: One identity on every EzKey screen, in a flat list

- **Status:** Accepted (2026-11-06)
- **Issue:** #104, a phase of #26. Refines the "server host on each line" note of ADR-0003.

## Context

Since ADR-0006, a person chooses the service by its home row, then decides on the approval page. Both must say who and what without ambiguity, quickly: an authenticator is a mandatory passage on the way to the application the user wants, not a place to study.

A person usually holds few enrollments: most often one or more regular integrations, possibly one administrator enrollment. Several EzKey installations are possible, for different business units or small companies, but are not the general case.

The screens showed the server's integration name, including for an administrator, and no role outside a warning. A long organization name cut the account from the row. The approval page gave no way to tell two installations apart.

The reference app defines the words (`ezkey_mobile/docs/MOBILE_POSITIONING.md` § Enrollment identity vocabulary) and builds them in one helper (`app/utils/enrollmentDisplay.ts`). Its home screen also frames each installation and adds tenant sections.

## Decision

1. **One helper builds the identity,** `lib/ezkey/identity.dart`, used by the row, the enrollment page, the enroll page and the approval page. It follows the reference app: Purpose, Account, Role, and a label that repeats a higher one is dropped.
2. **An administrator reads "Administration" with the role,** Global Admin or Tenant Admin, on all four screens. They show no organization: their enrollment belongs to EzKey's system tenant, which says nothing about the business they manage.
3. **The list stays flat, and the server appears when it removes an ambiguity.** With several installations on the device, each row and the approval page name the server. With one, they do not. While the number is unknown, the approval page names it.
4. **A row's line keeps what matters first,** since it can be cut: the role, then the account, then the organization. A long organization name no longer hides the account.

## Alternatives

- **The reference app's frames per installation, with the signed name.** Rejected for now: a frame and a network call cost height and attention on every screen, for a case that is not the general one, and the signed name is only display. The server is the installation's identity and is enough to tell two apart. Reconsider it if people hold many enrollments across installations. `EzkeyInstallation` already groups the data.
- **Always show the server.** Rejected: it adds a line to every row and to the approval page of the common case, for a person who has only one server. It teaches them to ignore it.
- **Show the server only when two rows would read the same.** Rejected: more logic for little gain, and on the approval page the person would still not know which installation is asking.
- **Tenant headers inside the list.** Rejected: the reference app shows them when the tenant differs from the installation's name, which this app does not fetch. The organization stays on the row, last.

## Consequences

- **Difference from the reference app, kept on purpose:** no installation frame, no signed instance name and no tenant section. The vocabulary and the collision rule are the same.
- **Two enrollments with the same purpose, account and server still read the same.** They can only come from enrolling the same account twice, and the enrollment page shows the date.
- **The list of enrollments to re-enroll keeps the server's name for an administrator:** the backup inventory does not carry the administrator fields. It does show the account before the organization.
- The rule for the unknown number favors showing the server, so it can appear for an instant while the list loads.

## References

- `ezkey_mobile/docs/MOBILE_POSITIONING.md` § Enrollment identity vocabulary, `ezkey_mobile/app/utils/enrollmentDisplay.ts` (EzKey repo).
- ADR-0003 (home screen), ADR-0006 (a check per enrollment).
