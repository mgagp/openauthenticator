import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

// Hooks for upstream's backup dialogs (lib/pages/settings/entries/backup_now.dart and
// manage_backups.dart). Backups hold the TOTPs and the salt only (test/model/backup/backup_test.dart):
// EzKey enrollments are not in them, since their keys never leave the device (ADR-0002). The dialogs say
// so when this device holds enrollments (docs/ezkey/harmonization.md, H2).

/// Returns upstream's "Backup now" password dialog [message], with a note that EzKey enrollments are not
/// included when this device holds some.
Future<String> withEzkeyBackupNote(WidgetRef ref, String message) => _withNote(ref, message, translations.ezkey.backups.backupNote);

/// Returns upstream's restore password dialog [message], with a note that only TOTPs are restored when
/// this device holds EzKey enrollments.
Future<String> withEzkeyRestoreNote(WidgetRef ref, String message) => _withNote(ref, message, translations.ezkey.backups.restoreNote);

/// Appends [note] to [message] when this device holds EzKey enrollments, readable or not.
///
/// Returns [message] unchanged where EzKey is not available, without enrollments, or when the enrollment
/// store fails, so upstream's dialog is unchanged there.
Future<String> _withNote(WidgetRef ref, String message, String note) async {
  if (!ezkeyAvailable) {
    return message;
  }
  try {
    SecureEzkeyEnrollmentStore store = await ref.read(ezkeyEnrollmentStoreProvider.future);
    bool hasEnrollments = (await store.list()).isNotEmpty || store.unreadableLocalIds().isNotEmpty;
    return hasEnrollments ? '$message\n\n$note' : message;
  } catch (ex) {
    debugPrint('EzKey backup note skipped: $ex');
    return message;
  }
}
