import 'dart:async';
import 'dart:convert';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';

// The enrollments to re-enroll after a backup restore (docs/adr/0005-ezkey-enrollment-inventory-in-backups.md,
// #94). A restore adds the backup's inventory to this list, and the EzKey page shows it. Nothing here
// re-creates an enrollment: each entry needs a new invitation from its administrator.

/// Returns whether [a] and [b] are the same account: same server, organization, integration and account.
///
/// A missing or empty name never matches, so an entry that cannot be identified is kept. The enrollment id
/// cannot serve, since a re-enrollment gets a new one.
bool isSameEzkeyAccount(EzkeyInventoryEntry a, EzkeyInventoryEntry b) {
  List<String?> parts = [a.authApiHost, a.tenantName, a.integrationName, a.enrollmentName];
  return !parts.any((part) => part == null || part.isEmpty) &&
      a.authApiHost == b.authApiHost &&
      a.tenantName == b.tenantName &&
      a.integrationName == b.integrationName &&
      a.enrollmentName == b.enrollmentName;
}

/// Returns [entries] without those whose account has an enrollment in [enrollments].
List<EzkeyInventoryEntry> withoutEnrolledEzkeyAccounts(List<EzkeyInventoryEntry> entries, List<EzkeyEnrollment> enrollments) {
  List<EzkeyInventoryEntry> enrolled = [for (EzkeyEnrollment enrollment in enrollments) EzkeyInventoryEntry.fromEnrollment(enrollment)];
  return [
    for (EzkeyInventoryEntry entry in entries)
      if (!enrolled.any((other) => isSameEzkeyAccount(entry, other))) entry,
  ];
}

/// Returns [existing] plus the [restored] entries that are not already in the list and whose account has no
/// enrollment in [enrollments].
List<EzkeyInventoryEntry> mergeEzkeyToReenroll(List<EzkeyInventoryEntry> existing, List<EzkeyInventoryEntry> restored, List<EzkeyEnrollment> enrollments) {
  List<EzkeyInventoryEntry> result = [...existing];
  for (EzkeyInventoryEntry entry in withoutEnrolledEzkeyAccounts(restored, enrollments)) {
    if (!result.any((other) => _isSameEnrollment(entry, other) || isSameEzkeyAccount(entry, other))) {
      result.add(entry);
    }
  }
  return result;
}

/// Returns whether [a] and [b] are the same enrollment of the same server.
bool _isSameEnrollment(EzkeyInventoryEntry a, EzkeyInventoryEntry b) => a.authApiHost == b.authApiHost && a.enrollmentId == b.enrollmentId;

/// Persists the list in the secure storage, next to the enrollment records, so that "Clear data" removes it.
class EzkeyToReenrollStore {
  /// The secure storage key.
  static const String key = 'ezkey.toReenroll';

  /// The underlying secure storage.
  final EzkeySecureValues values;

  /// Creates a new store over [values].
  const EzkeyToReenrollStore(this.values);

  /// Returns the stored entries. An unreadable list counts as empty, and invalid entries are skipped.
  List<EzkeyInventoryEntry> read() {
    String? stored = values.read(key);
    if (stored == null) {
      return [];
    }
    try {
      Object? json = jsonDecode(stored);
      return json is List ? [for (Object? entry in json) ?EzkeyInventoryEntry.tryFromJson(entry)] : [];
    } on FormatException catch (ex) {
      debugPrint('EzKey list to re-enroll ignored: $ex');
      return [];
    }
  }

  /// Replaces the stored entries by [entries].
  Future<void> write(List<EzkeyInventoryEntry> entries) => entries.isEmpty ? values.delete(key) : values.write(key, jsonEncode([for (EzkeyInventoryEntry entry in entries) entry.toJson()]));
}

/// The enrollments to re-enroll, sorted by integration name.
final ezkeyToReenrollProvider = AsyncNotifierProvider<EzkeyToReenrollNotifier, List<EzkeyInventoryEntry>>(EzkeyToReenrollNotifier.new);

/// Lists the enrollments to re-enroll, and forgets those the device has enrolled again.
class EzkeyToReenrollNotifier extends AsyncNotifier<List<EzkeyInventoryEntry>> {
  @override
  FutureOr<List<EzkeyInventoryEntry>> build() async {
    EzkeyToReenrollStore store = EzkeyToReenrollStore((await ref.watch(ezkeyEnrollmentStoreProvider.future)).values);
    List<EzkeyEnrollment> enrollments = await ref.watch(ezkeyEnrollmentsProvider.future);
    List<EzkeyInventoryEntry> entries = store.read();
    List<EzkeyInventoryEntry> kept = withoutEnrolledEzkeyAccounts(entries, enrollments);
    if (kept.length != entries.length) {
      await store.write(kept);
    }
    return kept..sort((a, b) => (a.integrationName ?? '').toLowerCase().compareTo((b.integrationName ?? '').toLowerCase()));
  }

  /// Removes [entry] from the list. The server is not affected.
  Future<void> remove(EzkeyInventoryEntry entry) async {
    EzkeyToReenrollStore store = EzkeyToReenrollStore((await ref.read(ezkeyEnrollmentStoreProvider.future)).values);
    try {
      await store.write([
        for (EzkeyInventoryEntry other in store.read())
          if (!_isSameEnrollment(entry, other)) other,
      ]);
    } finally {
      ref.invalidateSelf();
    }
  }
}

/// Hook for upstream's restore (lib/model/backup/store.dart): adds the [inventory] of the restored backup to
/// the list.
///
/// Does nothing where EzKey is not available or without an inventory. Fails open: the TOTPs are already
/// restored, and this list never turns that into a failure.
Future<void> rememberEzkeyToReenroll(Ref ref, EzkeyBackupInventory? inventory) async {
  if (!ezkeyAvailable || inventory == null) {
    return;
  }
  try {
    SecureEzkeyEnrollmentStore enrollmentStore = await ref.read(ezkeyEnrollmentStoreProvider.future);
    EzkeyToReenrollStore store = EzkeyToReenrollStore(enrollmentStore.values);
    await store.write(mergeEzkeyToReenroll(store.read(), inventory.entries, await enrollmentStore.list()));
    ref.invalidate(ezkeyToReenrollProvider);
  } on Object catch (ex) {
    debugPrint('EzKey list to re-enroll not updated: $ex');
  }
}
