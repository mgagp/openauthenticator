import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';

/// Deletes the device keys that no readable enrollment record references, and returns their aliases.
///
/// Keys outlive their records when the secure storage is cleared (upstream's storage recovery or
/// "Clear data"), see docs/adr/0002-ezkey-key-and-secret-storage.md. The key of an unreadable record
/// is deleted too: its alias cannot be read back, so the key can never be used again.
///
/// Run it only when no enrollment is in progress: between key generation and record save, a new
/// key has no record yet.
Future<List<String>> deleteOrphanEzkeyDeviceKeys({
  required AndroidEzkeyDeviceKeyStore keyStore,
  required EzkeyEnrollmentStore enrollmentStore,
}) async {
  Set<String> referenced = {
    for (EzkeyEnrollment enrollment in await enrollmentStore.list()) enrollment.deviceKeyAlias,
  };
  List<String> deleted = [];
  for (String alias in await keyStore.deviceKeyAliases()) {
    if (!referenced.contains(alias)) {
      await keyStore.deleteKeyPair(alias);
      deleted.add(alias);
    }
  }
  return deleted;
}
