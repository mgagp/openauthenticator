import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';

import 'support.dart';

void main() {
  late CryptoStore backupKey;

  setUpAll(() => backupKey = CryptoStore.fromPassword('backup-password', Salt.generate()));

  /// Returns a backup JSON whose inventory is [plain], encrypted with [backupKey].
  Map<String, dynamic> backupWith(String plain) => {EzkeyBackupInventory.kJsonKey: base64.encode(backupKey.encrypt(plain)!)};

  group('EzkeyInventoryEntry', () {
    test('holds display data only, never the key alias, a public key or the proof token', () {
      EzkeyInventoryEntry entry = EzkeyInventoryEntry.fromEnrollment(testEnrollment(3, authApiBaseUrl: 'https://auth.orbit.example/'));

      expect(entry.toJson(), {
        'enrollmentId': 3,
        'authApiHost': 'auth.orbit.example',
        'enrolledAt': '2026-10-27T12:00:00.000Z',
        'integrationName': 'Orbit Console',
        'tenantName': 'Ezkey System',
        'enrollmentName': 'Alice Chen',
      });
    });

    test('keeps a non-default port in the host', () {
      EzkeyInventoryEntry entry = EzkeyInventoryEntry.fromEnrollment(testEnrollment(3, authApiBaseUrl: 'http://10.0.2.2:8080'));

      expect(entry.authApiHost, '10.0.2.2:8080');
    });

    test('tryFromJson() rejects an entry without an id, a host or a valid date', () {
      Map<String, dynamic> valid = EzkeyInventoryEntry.fromEnrollment(testEnrollment(3)).toJson();

      expect(EzkeyInventoryEntry.tryFromJson(valid)?.enrollmentId, 3);
      expect(EzkeyInventoryEntry.tryFromJson({...valid, 'enrollmentId': '3'}), isNull);
      expect(EzkeyInventoryEntry.tryFromJson({...valid, 'authApiHost': null}), isNull);
      expect(EzkeyInventoryEntry.tryFromJson({...valid, 'enrolledAt': 'yesterday'}), isNull);
      expect(EzkeyInventoryEntry.tryFromJson('not an entry'), isNull);
    });
  });

  group('EzkeyBackupInventory', () {
    test('encrypt() returns null without entries, so the backup keeps upstream\'s keys', () {
      expect(EzkeyBackupInventory.encrypt([], backupKey), isNull);
    });

    test('reads back what it encrypted, only with the same key', () {
      EzkeyBackupInventory inventory = EzkeyBackupInventory.encrypt([EzkeyInventoryEntry.fromEnrollment(testEnrollment(3))], backupKey)!;
      CryptoStore otherKey = CryptoStore.fromPassword('backup-password', Salt.generate());

      expect(EzkeyBackupInventory.tryRead(inventory.toBackupJson(), backupKey)!.entries.single.enrollmentId, 3);
      expect(EzkeyBackupInventory.tryRead(inventory.toBackupJson(), otherKey), isNull);
    });

    test('tryRead() returns null when the key is missing, not Base64, not a list, or has no valid entry', () {
      expect(EzkeyBackupInventory.tryRead({}, backupKey), isNull);
      expect(EzkeyBackupInventory.tryRead({EzkeyBackupInventory.kJsonKey: 42}, backupKey), isNull);
      expect(EzkeyBackupInventory.tryRead({EzkeyBackupInventory.kJsonKey: 'not base64!'}, backupKey), isNull);
      expect(EzkeyBackupInventory.tryRead(backupWith('not json'), backupKey), isNull);
      expect(EzkeyBackupInventory.tryRead(backupWith('{"enrollmentId": 3}'), backupKey), isNull);
      expect(EzkeyBackupInventory.tryRead(backupWith('[{"enrollmentId": "x"}]'), backupKey), isNull);
    });

    test('tryRead() skips invalid entries and keeps the valid ones', () {
      String valid = jsonEncode(EzkeyInventoryEntry.fromEnrollment(testEnrollment(7)).toJson());

      EzkeyBackupInventory? inventory = EzkeyBackupInventory.tryRead(backupWith('[{"enrollmentId": "x"}, $valid, 12]'), backupKey);

      expect(inventory!.entries.map((entry) => entry.enrollmentId), [7]);
    });
  });
}
