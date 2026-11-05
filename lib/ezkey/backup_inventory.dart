import 'dart:convert';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/model/crypto/store.dart';

// The EzKey enrollment inventory in backups (docs/adr/0005-ezkey-enrollment-inventory-in-backups.md).
// Upstream's lib/model/backup/backup.dart and store.dart call into this file; each hook is listed in
// docs/ezkey/integration.md. The inventory never re-creates an enrollment: the device keys stay on the
// device (ADR-0002), so it only tells the user what to re-enroll after a restore.

/// One enrollment in a backup's EzKey inventory: display data only, never anything that can sign or
/// authenticate (no device key alias, public key or proof token).
class EzkeyInventoryEntry {
  /// The enrollment id on the server, so an administrator can find and revoke it.
  final int enrollmentId;

  /// The Auth API host (with its port, when not the default one).
  final String authApiHost;

  /// When the device enrolled.
  final DateTime enrolledAt;

  /// The integration (service) name.
  final String? integrationName;

  /// The organization (tenant) name.
  final String? tenantName;

  /// The account (enrollment) name.
  final String? enrollmentName;

  /// Creates a new EzKey inventory entry instance.
  const EzkeyInventoryEntry({
    required this.enrollmentId,
    required this.authApiHost,
    required this.enrolledAt,
    this.integrationName,
    this.tenantName,
    this.enrollmentName,
  });

  /// Creates the entry describing [enrollment].
  EzkeyInventoryEntry.fromEnrollment(EzkeyEnrollment enrollment)
    : this(
        enrollmentId: enrollment.enrollmentId,
        authApiHost: _host(enrollment.authApiBaseUrl),
        enrolledAt: enrollment.enrolledAt.toUtc(),
        integrationName: enrollment.integrationName,
        tenantName: enrollment.tenantName,
        enrollmentName: enrollment.enrollmentName,
      );

  /// Returns the entry held in [json], or `null` when it is not a valid entry.
  static EzkeyInventoryEntry? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    Object? enrollmentId = json['enrollmentId'];
    Object? authApiHost = json['authApiHost'];
    Object? enrolledAt = json['enrolledAt'];
    DateTime? date = enrolledAt is String ? DateTime.tryParse(enrolledAt) : null;
    if (enrollmentId is! int || authApiHost is! String || date == null) {
      return null;
    }
    return EzkeyInventoryEntry(
      enrollmentId: enrollmentId,
      authApiHost: authApiHost,
      enrolledAt: date.toUtc(),
      integrationName: _optionalString(json['integrationName']),
      tenantName: _optionalString(json['tenantName']),
      enrollmentName: _optionalString(json['enrollmentName']),
    );
  }

  /// Converts this entry to JSON.
  Map<String, dynamic> toJson() => {
    'enrollmentId': enrollmentId,
    'authApiHost': authApiHost,
    'enrolledAt': enrolledAt.toUtc().toIso8601String(),
    'integrationName': integrationName,
    'tenantName': tenantName,
    'enrollmentName': enrollmentName,
  };

  /// Returns the host of [baseUrl], with its port when not the default one, or [baseUrl] itself when
  /// it has none.
  static String _host(String baseUrl) {
    String? authority = Uri.tryParse(baseUrl)?.authority;
    return authority == null || authority.isEmpty ? baseUrl : authority;
  }

  /// Returns [value] when it is a string, `null` otherwise.
  static String? _optionalString(Object? value) => value is String ? value : null;
}

/// The EzKey enrollment inventory of one backup, under [kJsonKey] in the `.bak` file.
class EzkeyBackupInventory {
  /// The backup JSON key.
  static const String kJsonKey = 'ezkeyEnrollments';

  /// The entries.
  final List<EzkeyInventoryEntry> entries;

  /// The entries as stored in the file: the AES-GCM ciphertext of their JSON list, in standard Base64.
  final String encrypted;

  /// Creates a new EzKey backup inventory instance.
  const EzkeyBackupInventory._({
    required this.entries,
    required this.encrypted,
  });

  /// Encrypts [entries] with the backup's [cryptoStore].
  ///
  /// Returns `null` without entries, so the backup keeps upstream's three keys.
  static EzkeyBackupInventory? encrypt(List<EzkeyInventoryEntry> entries, CryptoStore cryptoStore) {
    if (entries.isEmpty) {
      return null;
    }
    Uint8List? encrypted = cryptoStore.encrypt(jsonEncode([for (EzkeyInventoryEntry entry in entries) entry.toJson()]));
    if (encrypted == null) {
      return null;
    }
    return EzkeyBackupInventory._(
      entries: List.unmodifiable(entries),
      encrypted: base64.encode(encrypted),
    );
  }

  /// Reads the inventory of the backup whose content is [backupJson], with the backup's [cryptoStore].
  ///
  /// Returns `null` when there is none, or when it cannot be read: a bad inventory never blocks the
  /// TOTP restore. Entries that are not valid are skipped.
  static EzkeyBackupInventory? tryRead(Map<String, dynamic> backupJson, CryptoStore cryptoStore) {
    Object? encrypted = backupJson[kJsonKey];
    if (encrypted is! String) {
      return null;
    }
    try {
      String? decrypted = cryptoStore.decrypt(base64.decode(encrypted));
      Object? json = decrypted == null ? null : jsonDecode(decrypted);
      if (json is! List) {
        return null;
      }
      List<EzkeyInventoryEntry> entries = [
        for (Object? entry in json) ?EzkeyInventoryEntry.tryFromJson(entry),
      ];
      return entries.isEmpty
          ? null
          : EzkeyBackupInventory._(
              entries: List.unmodifiable(entries),
              encrypted: encrypted,
            );
    } on FormatException catch (ex) {
      debugPrint('EzKey backup inventory ignored: $ex');
      return null;
    }
  }

  /// Returns the backup JSON entry holding this inventory.
  Map<String, dynamic> toBackupJson() => {kJsonKey: encrypted};
}

/// Returns the inventory entries of the enrollments this device holds, for a new backup.
///
/// Returns an empty list where EzKey is not available, and when the enrollment store fails: the
/// backup is then made as upstream does. Unreadable enrollments are left out, since nothing about them
/// can be shown.
Future<List<EzkeyInventoryEntry>> ezkeyInventoryEntries(Ref ref) async {
  if (!ezkeyAvailable) {
    return [];
  }
  try {
    SecureEzkeyEnrollmentStore store = await ref.read(ezkeyEnrollmentStoreProvider.future);
    return [for (EzkeyEnrollment enrollment in await store.list()) EzkeyInventoryEntry.fromEnrollment(enrollment)];
  } catch (ex) {
    debugPrint('EzKey backup inventory skipped: $ex');
    return [];
  }
}
