import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/orphan_keys.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/widgets/dialog/confirmation_dialog.dart';

// Hooks for upstream's "Clear data" (lib/pages/settings/entries/clear_data.dart), which clears the
// secure storage and so every EzKey enrollment record (docs/ezkey/harmonization.md, H1). The
// Authentication API has no device-side unenroll: the enrollments stay active on the servers.

/// Returns one line per service whose EzKey enrollments are on this device, sorted, for the "Clear
/// data" warning. An unreadable record still counts, under a generic label. Empty when there is none.
List<String> ezkeyClearDataServices({
  required List<EzkeyEnrollment> enrollments,
  required int unreadableCount,
}) => [
  ...({for (EzkeyEnrollment enrollment in enrollments) enrollment.integrationName ?? ''}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))),
  for (int i = 0; i < unreadableCount; i++) translations.ezkey.clearData.unreadable,
];

/// Before the data is cleared: when this device holds EzKey enrollments, says that clearing removes
/// them for good while they stay active on the servers, and returns whether the user goes on.
///
/// Returns `true` without asking where EzKey is not available or when there is no enrollment, so
/// upstream's flow is unchanged there.
Future<bool> confirmEzkeyClearData(BuildContext context, WidgetRef ref) async {
  if (!ezkeyAvailable) {
    return true;
  }
  SecureEzkeyEnrollmentStore store = await ref.read(ezkeyEnrollmentStoreProvider.future);
  List<String> services = ezkeyClearDataServices(
    enrollments: await store.list(),
    unreadableCount: store.unreadableLocalIds().length,
  );
  if (services.isEmpty) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  return ConfirmationDialog.ask(
    context,
    title: translations.ezkey.clearData.title,
    message: translations.ezkey.clearData.message(services: services.map((service) => '• $service').join('\n')),
    okButtonVariant: .destructive,
  );
}

/// Once the secure storage is cleared: deletes this build's EzKey device keys at once, since no record
/// references them anymore, instead of waiting for the next EzKey start.
///
/// Fails open: a key store error never stops the clear, and the next start cleans up again.
Future<void> deleteEzkeyKeysAfterClearData(WidgetRef ref) async {
  if (!ezkeyAvailable) {
    return;
  }
  try {
    await deleteOrphanEzkeyDeviceKeys(
      keyStore: ref.read(ezkeyDeviceKeyStoreProvider),
      enrollmentStore: await ref.read(ezkeyEnrollmentStoreProvider.future),
    );
  } on EzkeyException catch (ex) {
    debugPrint('EzKey key cleanup after clearing data failed: $ex');
  }
}
