import 'dart:async';
import 'dart:convert';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/to_reenroll.dart';

import 'support.dart';

/// Serves the given enrollments instead of the device stores.
class _FixedEnrollments extends EzkeyEnrollmentsNotifier {
  /// The enrollments, read at each build.
  final List<EzkeyEnrollment> Function() enrollments;

  /// Creates a new fixed enrollments instance.
  _FixedEnrollments(this.enrollments);

  @override
  FutureOr<List<EzkeyEnrollment>> build() => enrollments();
}

/// Returns an entry with the given values, on the same account as [testEnrollment] by default.
EzkeyInventoryEntry entry(
  int enrollmentId, {
  String authApiHost = 'localhost:8080',
  String? integrationName = 'Orbit Console',
  String? tenantName = 'Ezkey System',
  String? enrollmentName = 'Alice Chen',
}) => EzkeyInventoryEntry(
  enrollmentId: enrollmentId,
  authApiHost: authApiHost,
  enrolledAt: DateTime.utc(2026, 10, 27, 12),
  integrationName: integrationName,
  tenantName: tenantName,
  enrollmentName: enrollmentName,
);

void main() {
  group('isSameEzkeyAccount', () {
    test('is true with the same server, organization, integration and account, whatever the id', () {
      expect(isSameEzkeyAccount(entry(3), entry(9)), isTrue);
    });

    test('is false as soon as one of them differs, so two integrations of one organization stay apart', () {
      expect(isSameEzkeyAccount(entry(3), entry(3, authApiHost: 'other.example')), isFalse);
      expect(isSameEzkeyAccount(entry(3), entry(3, tenantName: 'Other')), isFalse);
      expect(isSameEzkeyAccount(entry(3), entry(3, integrationName: 'Other')), isFalse);
      expect(isSameEzkeyAccount(entry(3), entry(3, enrollmentName: 'Other')), isFalse);
    });

    test('is false when a name is missing or empty, even if both are the same', () {
      expect(isSameEzkeyAccount(entry(3, tenantName: null), entry(3, tenantName: null)), isFalse);
      expect(isSameEzkeyAccount(entry(3, integrationName: null), entry(3, integrationName: null)), isFalse);
      expect(isSameEzkeyAccount(entry(3, enrollmentName: null), entry(3, enrollmentName: null)), isFalse);
      expect(isSameEzkeyAccount(entry(3, enrollmentName: ''), entry(3, enrollmentName: '')), isFalse);
    });
  });

  group('mergeEzkeyToReenroll', () {
    test('adds the restored entries to the list', () {
      List<EzkeyInventoryEntry> merged = mergeEzkeyToReenroll([entry(1, integrationName: 'First')], [entry(2, integrationName: 'Second')], []);

      expect(merged.map((entry) => entry.enrollmentId), [1, 2]);
    });

    test('does not add an entry already listed, by enrollment or by account', () {
      List<EzkeyInventoryEntry> merged = mergeEzkeyToReenroll(
        [entry(1), entry(2, integrationName: null)],
        [entry(9), entry(2, integrationName: null)],
        [],
      );

      expect(merged.map((entry) => entry.enrollmentId), [1, 2]);
    });

    test('does not add an entry whose account is enrolled on this device', () {
      List<EzkeyInventoryEntry> merged = mergeEzkeyToReenroll([], [entry(3), entry(4, integrationName: 'Other')], [testEnrollment(9)]);

      expect(merged.map((entry) => entry.enrollmentId), [4]);
    });

    test('adds an entry with a missing name, even when an enrollment could be the same', () {
      List<EzkeyInventoryEntry> merged = mergeEzkeyToReenroll([], [entry(3, tenantName: null)], [testEnrollment(3)]);

      expect(merged.map((entry) => entry.enrollmentId), [3]);
    });
  });

  group('EzkeyToReenrollStore', () {
    late InMemorySecureValues values;
    late EzkeyToReenrollStore store;

    setUp(() {
      values = InMemorySecureValues();
      store = EzkeyToReenrollStore(values);
    });

    test('reads back what it wrote', () async {
      await store.write([entry(3)]);

      expect(store.read().single.toJson(), entry(3).toJson());
    });

    test('holds display data only', () async {
      await store.write([EzkeyInventoryEntry.fromEnrollment(testEnrollment(3))]);

      expect(values.values[EzkeyToReenrollStore.key], allOf(isNot(contains('proof-token')), isNot(contains('ezkey-device')), isNot(contains('MFkw'))));
    });

    test('leaves nothing in the secure storage once the list is empty', () async {
      await store.write([entry(3)]);

      await store.write([]);

      expect(values.values, isEmpty);
    });

    test('is not mistaken for an enrollment record', () async {
      await store.write([entry(3)]);

      SecureEzkeyEnrollmentStore enrollments = SecureEzkeyEnrollmentStore(values);

      expect(await enrollments.list(), isEmpty);
      expect(enrollments.unreadableLocalIds(), isEmpty);
    });

    test('reads an unreadable list as empty, and skips invalid entries', () {
      values.values[EzkeyToReenrollStore.key] = 'not json';
      expect(store.read(), isEmpty);

      values.values[EzkeyToReenrollStore.key] = '{"enrollmentId": 3}';
      expect(store.read(), isEmpty);

      values.values[EzkeyToReenrollStore.key] = jsonEncode(['not an entry', entry(3).toJson()]);
      expect(store.read().single.enrollmentId, 3);
    });
  });

  group('ezkeyToReenrollProvider', () {
    late InMemorySecureValues values;
    late EzkeyToReenrollStore store;
    late List<EzkeyEnrollment> enrollments;
    late ProviderContainer container;

    setUp(() {
      values = InMemorySecureValues();
      store = EzkeyToReenrollStore(values);
      enrollments = [];
      container = ProviderContainer(
        overrides: [
          ezkeyEnrollmentStoreProvider.overrideWith((ref) async => SecureEzkeyEnrollmentStore(values)),
          ezkeyEnrollmentsProvider.overrideWith(() => _FixedEnrollments(() => enrollments)),
        ],
      );
      container.listen(ezkeyToReenrollProvider, (previous, next) {});
    });

    tearDown(() => container.dispose());

    test('survives a restart, since it reads the secure storage', () async {
      await store.write([entry(3)]);

      List<EzkeyInventoryEntry> entries = await container.read(ezkeyToReenrollProvider.future);

      expect(entries.single.enrollmentId, 3);
    });

    test('sorts the entries by integration name', () async {
      await store.write([entry(1, integrationName: 'zulu'), entry(2, integrationName: 'Alpha')]);

      List<EzkeyInventoryEntry> entries = await container.read(ezkeyToReenrollProvider.future);

      expect(entries.map((entry) => entry.integrationName), ['Alpha', 'zulu']);
    });

    test('forgets an entry for good once its account is enrolled again, under a new id', () async {
      await store.write([entry(3), entry(4, integrationName: 'Other')]);
      await container.read(ezkeyToReenrollProvider.future);

      enrollments = [testEnrollment(9)];
      container.invalidate(ezkeyEnrollmentsProvider);
      List<EzkeyInventoryEntry> entries = await container.read(ezkeyToReenrollProvider.future);

      expect(entries.map((entry) => entry.enrollmentId), [4]);
      expect(store.read().map((entry) => entry.enrollmentId), [4]);
    });

    test('keeps an entry with a missing name when an enrollment could be the same', () async {
      await store.write([entry(3, enrollmentName: null)]);
      enrollments = [testEnrollment(3)];

      List<EzkeyInventoryEntry> entries = await container.read(ezkeyToReenrollProvider.future);

      expect(entries.map((entry) => entry.enrollmentId), [3]);
    });

    test('remove() takes the one entry out of the list and keeps the others', () async {
      await store.write([entry(3), entry(4, integrationName: 'Other')]);
      await container.read(ezkeyToReenrollProvider.future);

      await container.read(ezkeyToReenrollProvider.notifier).remove(entry(3));
      List<EzkeyInventoryEntry> entries = await container.read(ezkeyToReenrollProvider.future);

      expect(entries.map((entry) => entry.enrollmentId), [4]);
      expect(store.read().map((entry) => entry.enrollmentId), [4]);
    });
  });
}
