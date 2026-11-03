# ADR-0005: EzKey enrollment inventory in backups

- **Status:** Accepted (2026-11-03)
- **Issue:** #89. Harmonization H16 (`docs/ezkey/harmonization.md`). Builds on ADR-0002 (device keys never leave the device) and #61 (the backup dialogs say enrollments are not included).

## Context

An upstream backup is one JSON file, `<13-digit timestamp>.bak`, with three keys: `passwordSignature`, `salt` and `totps`. The TOTPs are encrypted with a key derived from the backup password, labels and issuers included (`lib/model/backup/backup.dart`). Export shares that one file; import copies that one file (`lib/model/backup/store.dart`). Upstream's reader checks the three keys and reads nothing else, so a fourth key is ignored (pinned by `test/model/backup/backup_test.dart`).

EzKey enrollments cannot be backed up: their keys stay in the device's hardware key store (ADR-0002). Since #61 the backup dialogs say so, but a backup keeps no trace of them. After a restore on a new device, the user has to remember which services, organizations and servers to re-enroll with. Upstream's `lib/model/backup/` is cold: one commit in 2026 (`docs/upstream-activity.md`).

## Decision

1. **The inventory goes inside the `.bak` file**, as a fourth top-level key, `ezkeyEnrollments`. It travels with export and import, since they move that one file.
2. **It is encrypted with the backup's crypto store**, the same key as the TOTPs: service and organization names are as private as TOTP labels. Value: the AES-GCM ciphertext (`CryptoStore`, 12-byte IV prefix) of a JSON list, in standard Base64.
3. **Each entry holds display data only**: integration name, organization (tenant) name, account (enrollment) name, Auth API host, enrollment date, and the server's enrollment id (so an administrator can find and revoke it). Never the device key alias, a public key, the proof token or anything that can sign or authenticate.
4. **Written only when the device holds enrollments.** Without enrollments, or where EzKey is not available (`ezkeyAvailable`), the file has upstream's three keys and nothing else.
5. **Restore never re-creates an enrollment.** The TOTPs are restored exactly as upstream does. The inventory is decrypted with the same password and shown on the EzKey page as "to re-enroll", each entry needing a new invitation from its administrator. A missing, unreadable or malformed inventory is ignored: it never blocks the TOTP restore.
6. **Hooks in upstream code stay minimal.** `Backup`'s create, save and read are private to its library, so `backup.dart` gets a few lines calling functions in `lib/ezkey/`, which hold all the logic. Each hook is listed in `docs/ezkey/integration.md` with its re-apply step.

## Compatibility

| Backup made by | Restored in | Result |
|---|---|---|
| Upstream | Fork | TOTPs restored; no inventory |
| Fork, without enrollments | Upstream | Same file as upstream's |
| Fork, with enrollments | Upstream | TOTPs restored; the inventory is ignored |
| Fork, with enrollments | Fork | TOTPs restored; inventory shown as "to re-enroll" |

Upstream never rewrites an existing backup file, so it does not drop the key. A new backup made in upstream's app has no inventory.

## Alternatives considered

- **A file next to the `.bak`** (`<timestamp>.ezkey`). Upstream's format stays untouched, but export and import move the `.bak` only, so the inventory is lost exactly on a device change. Deleting a backup would also need a hook. Rejected.
- **A separate EzKey export** (a button on the EzKey page). No upstream file touched, but it is one more action the user must remember, and it is separate from the backup they actually keep. Rejected; can be added later on top of this.
- **The inventory in clear text.** Simpler, but it would expose the services a user relies on, while upstream encrypts TOTP labels. Rejected.
- **Nothing beyond the #61 note.** Leaves the user without a list after a restore. Rejected.

## Consequences

- A divergence in `lib/model/backup/backup.dart`, a cold upstream file. Re-applying it after a sync means re-adding the calls listed in `docs/ezkey/integration.md`.
- The test that pins "nothing else" in a backup (`backup_test.dart`) stays true without enrollments; a new test covers the case with enrollments.
- The committed fixture `test/model/backup/fixtures/1793500000000.bak` keeps restoring unchanged; a fixture with an inventory is added with the implementation.
- When EzKey defines a device-replacement flow (H17, EzKey first), the inventory is its natural input.

## References

- `lib/model/backup/backup.dart`, `lib/model/backup/store.dart`; `lib/ezkey/backups.dart` (#61 notes).
- `test/model/backup/backup_test.dart`: the fixture, and the extra-key compatibility test (#89).
- ADR-0002; `docs/ezkey/harmonization.md` H2, H16, H17.
