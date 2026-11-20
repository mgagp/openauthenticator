import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/core/backup/backup.dart';
import 'package:open_authenticator/core/crypto/salt.dart';
import 'package:open_authenticator/core/crypto/store.dart';
import 'package:open_authenticator/core/totp/algorithm.dart';
import 'package:open_authenticator/core/totp/decrypted.dart';
import 'package:open_authenticator/core/totp/json.dart';
import 'package:open_authenticator/core/totp/repository.dart';
import 'package:open_authenticator/core/totp/totp.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/to_reenroll.dart';
import 'package:open_authenticator/utils/platform.dart' as app;
import 'package:open_authenticator/utils/result/result.dart';

import '../../ezkey/support.dart';

// Characterization tests (#55): they pin upstream's backups as they are today, before the backup UI
// explains EzKey (harmonization H2). A backup holds the TOTPs and the salt, never an EzKey record: its keys
// cannot leave the device (ADR-0002), so a record restored without its key would be useless. Since #92 it
// also holds, when the device has enrollments, an encrypted inventory of them (display data, ADR-0005).
// `fixtures/1793500000000.bak` was written by this code on 2026-11-01 (password `fixture-password`):
// it must keep restoring, so that users' existing backups do too. `fixtures/1793600000000.bak` is the same
// backup with an EzKey inventory of two entries (#92).

/// The plugin channel `getApplicationDocumentsDirectory` goes through.
const MethodChannel _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// The password of the committed fixture.
const String _fixturePassword = 'fixture-password';

/// A TOTP repository that holds a fixed list and records what [replaceBy] receives, without the database.
class _RecordingTotps extends TotpRepository {
  /// The TOTPs.
  final List<Totp> totps;

  /// The lists given to [replaceBy], in order. Shared by every instance, since the provider can be rebuilt.
  final List<List<Totp>> replacements;

  /// Creates a new recording TOTP repository instance.
  _RecordingTotps(this.totps, this.replacements);

  @override
  FutureOr<List<Totp>> build() => totps;

  @override
  Future<Result<List<Totp>>> replaceBy(List<Totp> totps, {bool fromNetwork = false}) async {
    replacements.add(totps);
    return ResultSuccess(value: totps);
  }
}

/// A crypto store notifier that holds a fixed store, without the secure storage.
class _FixedCryptoStore extends CryptoStoreNotifier {
  /// The store, or `null` for none.
  final CryptoStore? store;

  /// Creates a new fixed crypto store notifier instance.
  _FixedCryptoStore(this.store);

  @override
  FutureOr<CryptoStore?> build() => store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late CryptoStore deviceStore;
  late Directory documents;
  late Directory backups;
  late List<List<Totp>> replacements;
  late ProviderContainer container;

  setUpAll(() async => deviceStore = await CryptoStore.fromPasswordInIsolate('device-password', Salt.generate()));

  /// Returns a decrypted TOTP named [label], encrypted with the device store.
  Totp totp(String label) => DecryptedTotp.create(
    cryptoStore: deviceStore,
    uuid: 'uuid-$label',
    secret: 'JBSWY3DPEHPK3PXP',
    label: label,
    issuer: 'Orbit',
  )!;

  /// Creates the container over [totps], with [store] as the device crypto store and [ezkeyStore] as
  /// the EzKey enrollment store (an empty one by default: `flutter test` runs as Android, where EzKey is
  /// available).
  BackupStore backupStore({List<Totp> totps = const [], CryptoStore? store, bool withCryptoStore = true, SecureEzkeyEnrollmentStore? ezkeyStore}) {
    replacements = [];
    container = ProviderContainer(
      overrides: [
        totpRepositoryProvider.overrideWith(() => _RecordingTotps(totps, replacements)),
        cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(withCryptoStore ? (store ?? deviceStore) : null)),
        ezkeyEnrollmentStoreProvider.overrideWith((ref) async => ezkeyStore ?? SecureEzkeyEnrollmentStore(InMemorySecureValues())),
      ],
    );
    container.listen(backupStoreProvider, (previous, next) {});
    return container.read(backupStoreProvider.notifier);
  }

  /// Returns the files in the backups directory.
  List<String> backupFiles() => backups.existsSync() ? [for (final FileSystemEntity entity in backups.listSync()) entity.uri.pathSegments.last] : [];

  setUp(() {
    documents = Directory.systemTemp.createTempSync('oa_backup_test');
    backups = Directory('${documents.path}${Platform.pathSeparator}Open Authenticator Backups (Debug)');
    messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async => call.method == 'getApplicationDocumentsDirectory' ? documents.path : null);
  });

  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(_pathProviderChannel, null);
    documents.deleteSync(recursive: true);
  });

  group('BackupStore.doBackup', () {
    test('writes one timestamped .bak file in the app\'s backups directory and lists it', () async {
      final BackupStore store = backupStore(totps: [totp('alice')]);

      final Result<Backup> result = await store.doBackup('backup-password');

      expect(result, isA<ResultSuccess<Backup>>());
      expect(backupFiles(), [matches(RegExp(r'^\d{13}\.bak$'))]);
      expect(container.read(backupStoreProvider).value, [(result as ResultSuccess<Backup>).value.backupPath]);
    });

    test('holds exactly the password signature, the salt and the TOTPs, and nothing else', () async {
      final BackupStore store = backupStore(totps: [totp('alice'), totp('bob')]);

      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      final Map<String, dynamic> content = jsonDecode(backup.backupPath.file.readAsStringSync());

      expect(content.keys, unorderedEquals([Backup.kPasswordSignatureKey, Backup.kSaltKey, Backup.kTotpsKey]));
      expect(content[Backup.kTotpsKey], hasLength(2));
      for (final Map<String, dynamic> entry in (content[Backup.kTotpsKey] as List).cast<Map<String, dynamic>>()) {
        expect(
          entry.keys,
          everyElement(
            isIn([
              Totp.kUuidKey,
              Totp.kSecretKey,
              Totp.kLabelKey,
              Totp.kIssuerKey,
              Totp.kImageUrlKey,
              Totp.kEncryptionSaltKey,
              Totp.kAlgorithmKey,
              Totp.kDigitsKey,
              Totp.kValidityKey,
              Totp.kUpdatedAtKey,
            ]),
          ),
        );
      }
    });

    test('encrypts the TOTPs with the backup password, not with the device key', () async {
      final BackupStore store = backupStore(totps: [totp('alice')]);

      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      final Map<String, dynamic> content = jsonDecode(backup.backupPath.file.readAsStringSync());
      final Totp saved = JsonTotp.fromJson((content[Backup.kTotpsKey] as List).first);
      final CryptoStore backupKey = await CryptoStore.fromPasswordInIsolate('backup-password', Salt.base64Decode(string: content[Backup.kSaltKey]));

      expect(saved.decrypt(deviceStore).isDecrypted, isFalse);
      expect((saved.decrypt(backupKey) as DecryptedTotp).secret, 'JBSWY3DPEHPK3PXP');
    });

    test('fails without a crypto store and writes nothing', () async {
      final BackupStore store = backupStore(totps: [totp('alice')], withCryptoStore: false);

      final Result<Backup> result = await store.doBackup('backup-password');

      expect(result, isA<ResultError<Backup>>());
      expect(backupFiles(), isEmpty);
    });
  });

  group('BackupStore.restoreBackup', () {
    test('replaces the TOTPs by the backup content, re-encrypted with the device key', () async {
      final BackupStore store = backupStore(totps: [totp('alice'), totp('bob')]);
      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;

      final Result<Backup> result = await store.restoreBackup(backup.backupPath, 'backup-password');

      expect(result, isA<ResultSuccess<Backup>>());
      expect(replacements, hasLength(1));
      final List<Totp> restored = replacements.single;
      expect(restored.map((totp) => totp.uuid), unorderedEquals(['uuid-alice', 'uuid-bob']));
      expect(restored.map((totp) => (totp.decrypt(deviceStore) as DecryptedTotp).label), unorderedEquals(['alice', 'bob']));
    });

    test('rejects a wrong password and leaves the TOTPs alone', () async {
      final BackupStore store = backupStore(totps: [totp('alice')]);
      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;

      final Result<Backup> result = await store.restoreBackup(backup.backupPath, 'wrong-password');

      expect(result, isA<ResultError<Backup>>());
      expect((result as ResultError<Backup>).exception, isA<InvalidBackupPasswordException>());
      expect(replacements, isEmpty);
    });
  });

  group('BackupStore.import', () {
    test('copies the committed fixture, keeps its date, and restores both of its TOTPs', () async {
      final CryptoStore otherDevice = await CryptoStore.fromPasswordInIsolate('another-device-password', Salt.generate());
      final BackupStore store = backupStore(store: otherDevice);
      backups.createSync(recursive: true);

      final Result<BackupPath> imported = await store.import(File('test/core/backup/fixtures/1793500000000.bak'));
      final BackupPath path = (imported as ResultSuccess<BackupPath>).value;
      final Result<Backup> restored = await store.restoreBackup(path, _fixturePassword);

      expect(path.timestamp, DateTime.fromMillisecondsSinceEpoch(1793500000000));
      expect(backupFiles(), ['1793500000000.bak']);
      expect(restored, isA<ResultSuccess<Backup>>());
      final Map<String, DecryptedTotp> totps = {for (final Totp totp in replacements.single) totp.uuid: totp.decrypt(otherDevice) as DecryptedTotp};
      expect(totps.keys, unorderedEquals(['fixture-totp-1', 'fixture-totp-2']));
      expect([totps['fixture-totp-1']!.secret, totps['fixture-totp-1']!.label, totps['fixture-totp-1']!.issuer], ['JBSWY3DPEHPK3PXP', 'alice@example.com', 'Orbit']);
      expect([totps['fixture-totp-2']!.secret, totps['fixture-totp-2']!.label, totps['fixture-totp-2']!.issuer], ['GEZDGNBVGY3TQOJQ', 'bob', null]);
      expect([totps['fixture-totp-2']!.algorithm, totps['fixture-totp-2']!.digits, totps['fixture-totp-2']!.validity], [Algorithm.sha256, 8, const Duration(seconds: 60)]);
    });

    test('ignores a key it does not know, such as the EzKey inventory, and still restores both TOTPs (ADR-0005)', () async {
      final CryptoStore otherDevice = await CryptoStore.fromPasswordInIsolate('another-device-password', Salt.generate());
      final BackupStore store = backupStore(store: otherDevice);
      backups.createSync(recursive: true);
      final Map<String, dynamic> content = jsonDecode(File('test/core/backup/fixtures/1793500000000.bak').readAsStringSync());
      content['ezkeyEnrollments'] = base64.encode(utf8.encode('opaque to upstream'));
      final File withInventory = File('${documents.path}${Platform.pathSeparator}1793500000000.bak')..writeAsStringSync(jsonEncode(content));

      final Result<BackupPath> imported = await store.import(withInventory);
      final Result<Backup> restored = await store.restoreBackup((imported as ResultSuccess<BackupPath>).value, _fixturePassword);

      expect(restored, isA<ResultSuccess<Backup>>());
      expect([for (final Totp totp in replacements.single) totp.uuid], unorderedEquals(['fixture-totp-1', 'fixture-totp-2']));
    });

    test('creates the backups directory when no backup was ever made', () async {
      // Upstream fixed this quirk in the 2026-11 sync (#148): the import used to fail with a FileSystemException.
      final BackupStore store = backupStore();

      final Result<BackupPath> result = await store.import(File('test/core/backup/fixtures/1793500000000.bak'));

      expect(result, isA<ResultSuccess<BackupPath>>());
      expect(backups.existsSync(), isTrue);
    });

    test('rejects a file that is not a backup and copies nothing', () async {
      final BackupStore store = backupStore();
      final File notJson = File('${documents.path}${Platform.pathSeparator}1793500000000.bak')..writeAsStringSync('not json');
      final File noSalt = File('${documents.path}${Platform.pathSeparator}other.bak')..writeAsStringSync(jsonEncode({Backup.kTotpsKey: [], Backup.kPasswordSignatureKey: 'x'}));

      final Result<BackupPath> first = await store.import(notJson);
      final Result<BackupPath> second = await store.import(noSalt);

      expect(first, isA<ResultError<BackupPath>>());
      expect(second, isA<ResultError<BackupPath>>());
      expect(backupFiles(), isEmpty);
    });
  });

  group('BackupStore.build', () {
    test('lists only files named with 13 digits and .bak, newest first', () async {
      backups.createSync(recursive: true);
      for (final String name in ['1700000000000.bak', '1800000000000.bak', 'notes.txt', '123.bak', '17000000000000.json']) {
        File('${backups.path}${Platform.pathSeparator}$name').writeAsStringSync('{}');
      }
      backupStore();

      final List<BackupPath> paths = await container.read(backupStoreProvider.future);

      expect(paths.map((path) => path.filename), ['1800000000000.bak', '1700000000000.bak']);
    });
  });

  group('EzKey enrollment inventory (ADR-0005)', () {
    late app.Platform platform;
    late SecureEzkeyEnrollmentStore ezkeyStore;

    setUp(() async {
      platform = app.currentPlatform;
      app.currentPlatform = .android;
      ezkeyStore = SecureEzkeyEnrollmentStore(InMemorySecureValues());
      await ezkeyStore.save(testEnrollment(3, authApiBaseUrl: 'https://auth.orbit.example'));
      await ezkeyStore.save(testEnrollment(7, authApiBaseUrl: 'http://localhost:8080', integrationName: 'Lab'));
    });

    tearDown(() => app.currentPlatform = platform);

    /// Imports [file] into a fresh container, then restores it with the fixture password. The EzKey
    /// enrollment store is [into], or an empty one.
    Future<Result<Backup>> importAndRestore(File file, {SecureEzkeyEnrollmentStore? into}) async {
      final BackupStore store = backupStore(store: await CryptoStore.fromPasswordInIsolate('another-device-password', Salt.generate()), ezkeyStore: into);
      backups.createSync(recursive: true);
      final Result<BackupPath> imported = await store.import(file);
      return store.restoreBackup((imported as ResultSuccess<BackupPath>).value, _fixturePassword);
    }

    test('a backup with enrollments has a 4th key, encrypted, that restores with the TOTPs', () async {
      final BackupStore store = backupStore(totps: [totp('alice')], ezkeyStore: ezkeyStore);

      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      final String raw = backup.backupPath.file.readAsStringSync();
      final Result<Backup> restored = await store.restoreBackup(backup.backupPath, 'backup-password');

      expect((jsonDecode(raw) as Map<String, dynamic>).keys, unorderedEquals([Backup.kPasswordSignatureKey, Backup.kSaltKey, Backup.kTotpsKey, EzkeyBackupInventory.kJsonKey]));
      expect(raw, allOf(isNot(contains('Orbit Console')), isNot(contains('Alice Chen')), isNot(contains('proof-token'))));
      expect([for (final Totp totp in replacements.single) totp.uuid], ['uuid-alice']);
      final List<EzkeyInventoryEntry> entries = (restored as ResultSuccess<Backup>).value.ezkeyInventory!.entries;
      expect(
        entries.map((entry) => [entry.enrollmentId, entry.authApiHost, entry.integrationName]),
        unorderedEquals([
          [3, 'auth.orbit.example', 'Orbit Console'],
          [7, 'localhost:8080', 'Lab'],
        ]),
      );
    });

    test('a backup without enrollments keeps upstream\'s three keys', () async {
      final BackupStore store = backupStore(totps: [totp('alice')], ezkeyStore: SecureEzkeyEnrollmentStore(InMemorySecureValues()));

      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      final Map<String, dynamic> content = jsonDecode(backup.backupPath.file.readAsStringSync());

      expect(content.keys, unorderedEquals([Backup.kPasswordSignatureKey, Backup.kSaltKey, Backup.kTotpsKey]));
      expect(backup.ezkeyInventory, isNull);
    });

    test('where EzKey is not available, the backup keeps upstream\'s three keys even with enrollments', () async {
      app.currentPlatform = .windows;
      final BackupStore store = backupStore(totps: [totp('alice')], ezkeyStore: ezkeyStore);

      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      final Map<String, dynamic> content = jsonDecode(backup.backupPath.file.readAsStringSync());

      expect(content.keys, unorderedEquals([Backup.kPasswordSignatureKey, Backup.kSaltKey, Backup.kTotpsKey]));
    });

    test('a failing enrollment store does not block the backup, which keeps upstream\'s three keys', () async {
      replacements = [];
      container = ProviderContainer(
        overrides: [
          totpRepositoryProvider.overrideWith(() => _RecordingTotps([totp('alice')], replacements)),
          cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(deviceStore)),
          ezkeyEnrollmentStoreProvider.overrideWith((ref) async => throw StateError('secure storage unavailable')),
        ],
      );
      container.listen(backupStoreProvider, (previous, next) {});

      final Result<Backup> result = await container.read(backupStoreProvider.notifier).doBackup('backup-password');
      final Map<String, dynamic> content = jsonDecode((result as ResultSuccess<Backup>).value.backupPath.file.readAsStringSync());

      expect(content.keys, unorderedEquals([Backup.kPasswordSignatureKey, Backup.kSaltKey, Backup.kTotpsKey]));
    });

    test('the committed fixture with an inventory restores both TOTPs and both entries', () async {
      final Result<Backup> restored = await importAndRestore(File('test/core/backup/fixtures/1793600000000.bak'));

      expect([for (final Totp totp in replacements.single) totp.uuid], unorderedEquals(['fixture-totp-1', 'fixture-totp-2']));
      expect((restored as ResultSuccess<Backup>).value.ezkeyInventory!.entries.map((entry) => entry.toJson()), [
        {'enrollmentId': 3, 'authApiHost': 'auth.orbit.example', 'enrolledAt': '2026-10-27T12:00:00.000Z', 'integrationName': 'Orbit Console', 'tenantName': 'Orbit', 'enrollmentName': 'Alice Chen'},
        {'enrollmentId': 7, 'authApiHost': 'localhost:8080', 'enrolledAt': '2026-11-02T09:30:00.000Z', 'integrationName': null, 'tenantName': null, 'enrollmentName': null},
      ]);
    });

    test('restoring the fixture lists both entries to re-enroll, once even when restored twice', () async {
      final SecureEzkeyEnrollmentStore empty = SecureEzkeyEnrollmentStore(InMemorySecureValues());
      final File fixture = File('test/core/backup/fixtures/1793600000000.bak');

      await importAndRestore(fixture, into: empty);
      final Result<BackupPath> again = await container.read(backupStoreProvider.notifier).import(fixture);
      await container.read(backupStoreProvider.notifier).restoreBackup((again as ResultSuccess<BackupPath>).value, _fixturePassword);

      expect(EzkeyToReenrollStore(empty.values).read().map((entry) => entry.enrollmentId), [3, 7]);
    });

    test('restoring on the device that holds the enrollments lists nothing to re-enroll', () async {
      final BackupStore store = backupStore(totps: [totp('alice')], ezkeyStore: ezkeyStore);

      final Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      await store.restoreBackup(backup.backupPath, 'backup-password');

      expect(EzkeyToReenrollStore(ezkeyStore.values).read(), isEmpty);
    });

    test('where EzKey is not available, a restore lists nothing to re-enroll', () async {
      app.currentPlatform = .windows;
      final SecureEzkeyEnrollmentStore empty = SecureEzkeyEnrollmentStore(InMemorySecureValues());

      final Result<Backup> restored = await importAndRestore(File('test/core/backup/fixtures/1793600000000.bak'), into: empty);

      expect(restored, isA<ResultSuccess<Backup>>());
      expect(EzkeyToReenrollStore(empty.values).read(), isEmpty);
    });

    test('a failing enrollment store does not block the restore of the TOTPs', () async {
      replacements = [];
      container = ProviderContainer(
        overrides: [
          totpRepositoryProvider.overrideWith(() => _RecordingTotps([], replacements)),
          cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(deviceStore)),
          ezkeyEnrollmentStoreProvider.overrideWith((ref) async => throw StateError('secure storage unavailable')),
        ],
      );
      container.listen(backupStoreProvider, (previous, next) {});
      final BackupStore store = container.read(backupStoreProvider.notifier);
      backups.createSync(recursive: true);

      final Result<BackupPath> imported = await store.import(File('test/core/backup/fixtures/1793600000000.bak'));
      final Result<Backup> restored = await store.restoreBackup((imported as ResultSuccess<BackupPath>).value, _fixturePassword);

      expect(restored, isA<ResultSuccess<Backup>>());
      expect([for (final Totp totp in replacements.single) totp.uuid], unorderedEquals(['fixture-totp-1', 'fixture-totp-2']));
    });

    test('a corrupted inventory is ignored and both TOTPs still restore', () async {
      final Map<String, dynamic> content = jsonDecode(File('test/core/backup/fixtures/1793600000000.bak').readAsStringSync());
      final String encrypted = content[EzkeyBackupInventory.kJsonKey];
      content[EzkeyBackupInventory.kJsonKey] = '${encrypted.substring(0, 20)}${encrypted.substring(20, 24) == 'AAAA' ? 'BBBB' : 'AAAA'}${encrypted.substring(24)}';
      final File corrupted = File('${documents.path}${Platform.pathSeparator}1793600000000.bak')..writeAsStringSync(jsonEncode(content));

      final Result<Backup> restored = await importAndRestore(corrupted);

      expect((restored as ResultSuccess<Backup>).value.ezkeyInventory, isNull);
      expect([for (final Totp totp in replacements.single) totp.uuid], unorderedEquals(['fixture-totp-1', 'fixture-totp-2']));
    });
  });
}
