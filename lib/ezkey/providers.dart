import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_authenticator/ezkey/device_key_store.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/orphan_keys.dart';
import 'package:open_authenticator/model/secure_storage.dart';

/// The EzKey device key store, on the platform's hardware key store.
final ezkeyDeviceKeyStoreProvider = Provider<NativeEzkeyDeviceKeyStore>((ref) => NativeEzkeyDeviceKeyStore());

/// The EzKey enrollment store, on the app's secure storage.
final ezkeyEnrollmentStoreProvider = FutureProvider<SecureEzkeyEnrollmentStore>((ref) async => SecureEzkeyEnrollmentStore(CachedSecureValues(await ref.watch(secureStorageProvider.future))));

/// The EzKey authenticator (SDK entry point).
///
/// Kept alive: it holds the per-attempt decision locks and the Auth API clients. Before handing it
/// out, it deletes orphan device keys once, so the cleanup never runs during an enrollment.
final ezkeyAuthenticatorProvider = FutureProvider<EzkeyAuthenticator>((ref) async {
  NativeEzkeyDeviceKeyStore keyStore = ref.watch(ezkeyDeviceKeyStoreProvider);
  SecureEzkeyEnrollmentStore enrollmentStore = await ref.watch(ezkeyEnrollmentStoreProvider.future);
  try {
    await deleteOrphanEzkeyDeviceKeys(keyStore: keyStore, enrollmentStore: enrollmentStore);
  } on EzkeyException catch (ex) {
    // Fail open: a leftover key is harmless, and the cleanup runs again on the next start.
    debugPrint('EzKey orphan key cleanup failed: $ex');
  }
  http.Client client = http.Client();
  ref.onDispose(client.close);
  return EzkeyAuthenticator(
    keyStore: keyStore,
    enrollmentStore: enrollmentStore,
    httpClient: client,
    keyAliasFactory: (enrollmentId) => ezkeyDeviceKeyAlias(enrollmentId, namespace: keyStore.namespace),
  );
});

/// The local EzKey enrollments, sorted by integration name.
final ezkeyEnrollmentsProvider = AsyncNotifierProvider<EzkeyEnrollmentsNotifier, List<EzkeyEnrollment>>(EzkeyEnrollmentsNotifier.new);

/// Lists, adds and forgets the local EzKey enrollments.
class EzkeyEnrollmentsNotifier extends AsyncNotifier<List<EzkeyEnrollment>> {
  @override
  FutureOr<List<EzkeyEnrollment>> build() async {
    EzkeyAuthenticator authenticator = await ref.watch(ezkeyAuthenticatorProvider.future);
    List<EzkeyEnrollment> enrollments = await authenticator.listEnrollments();
    return enrollments..sort((a, b) => (a.integrationName ?? '').toLowerCase().compareTo((b.integrationName ?? '').toLowerCase()));
  }

  /// Finishes [bound] with the [enrollmentChallenge] typed by the user, then refreshes the list.
  Future<EzkeyEnrollment> complete(EzkeyBoundEnrollment bound, int enrollmentChallenge) async {
    EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
    try {
      return await authenticator.completeEnrollment(bound, enrollmentChallenge: enrollmentChallenge);
    } finally {
      ref.invalidateSelf();
    }
  }

  /// Deletes [enrollment] from this device (record and key), then refreshes the list.
  ///
  /// The server keeps the enrollment: an administrator has to revoke it there.
  Future<void> forget(EzkeyEnrollment enrollment) async {
    EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
    try {
      await authenticator.forget(enrollment);
    } finally {
      ref.invalidateSelf();
    }
  }
}
