import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/backup/backup.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/model/totp/algorithm.dart';
import 'package:open_authenticator/model/totp/decrypted.dart';
import 'package:open_authenticator/model/totp/json.dart';
import 'package:open_authenticator/model/totp/repository.dart';
import 'package:open_authenticator/model/totp/totp.dart';
import 'package:open_authenticator/utils/result/result.dart';

// Characterization tests (#55): they pin upstream's backups as they are today, before the backup UI
// explains EzKey (harmonization H2). A backup holds the TOTPs and the salt only, never anything from
// EzKey: its keys cannot leave the device (ADR-0002), so a record restored without its key would be useless.
// `fixtures/1793500000000.bak` was written by this code on 2026-11-01 (password `fixture-password`):
// it must keep restoring, so that users' existing backups do too.

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
  TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late CryptoStore deviceStore;
  late Directory documents;
  late Directory backups;
  late List<List<Totp>> replacements;
  late ProviderContainer container;

  setUpAll(() => deviceStore = CryptoStore.fromPassword('device-password', Salt.generate()));

  /// Returns a decrypted TOTP named [label], encrypted with the device store.
  Totp totp(String label) => DecryptedTotp.create(
    cryptoStore: deviceStore,
    uuid: 'uuid-$label',
    secret: 'JBSWY3DPEHPK3PXP',
    label: label,
    issuer: 'Orbit',
  )!;

  /// Creates the container over [totps], with [store] as the device crypto store.
  BackupStore backupStore({List<Totp> totps = const [], CryptoStore? store, bool withCryptoStore = true}) {
    replacements = [];
    container = ProviderContainer(
      overrides: [
        totpRepositoryProvider.overrideWith(() => _RecordingTotps(totps, replacements)),
        cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(withCryptoStore ? (store ?? deviceStore) : null)),
      ],
    );
    container.listen(backupStoreProvider, (previous, next) {});
    return container.read(backupStoreProvider.notifier);
  }

  /// Returns the files in the backups directory.
  List<String> backupFiles() => backups.existsSync() ? [for (FileSystemEntity entity in backups.listSync()) entity.uri.pathSegments.last] : [];

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
      BackupStore store = backupStore(totps: [totp('alice')]);

      Result<Backup> result = await store.doBackup('backup-password');

      expect(result, isA<ResultSuccess<Backup>>());
      expect(backupFiles(), [matches(RegExp(r'^\d{13}\.bak$'))]);
      expect(container.read(backupStoreProvider).value, [(result as ResultSuccess<Backup>).value.backupPath]);
    });

    test('holds exactly the password signature, the salt and the TOTPs, and nothing else', () async {
      BackupStore store = backupStore(totps: [totp('alice'), totp('bob')]);

      Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      Map<String, dynamic> content = jsonDecode(backup.backupPath.file.readAsStringSync());

      expect(content.keys, unorderedEquals([Backup.kPasswordSignatureKey, Backup.kSaltKey, Backup.kTotpsKey]));
      expect(content[Backup.kTotpsKey], hasLength(2));
      for (Map<String, dynamic> entry in (content[Backup.kTotpsKey] as List).cast<Map<String, dynamic>>()) {
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
      BackupStore store = backupStore(totps: [totp('alice')]);

      Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;
      Map<String, dynamic> content = jsonDecode(backup.backupPath.file.readAsStringSync());
      Totp saved = JsonTotp.fromJson((content[Backup.kTotpsKey] as List).first);
      CryptoStore backupKey = CryptoStore.fromPassword('backup-password', Salt.base64Decode(string: content[Backup.kSaltKey]));

      expect(saved.decrypt(deviceStore).isDecrypted, isFalse);
      expect((saved.decrypt(backupKey) as DecryptedTotp).secret, 'JBSWY3DPEHPK3PXP');
    });

    test('fails without a crypto store and writes nothing', () async {
      BackupStore store = backupStore(totps: [totp('alice')], withCryptoStore: false);

      Result<Backup> result = await store.doBackup('backup-password');

      expect(result, isA<ResultError<Backup>>());
      expect(backupFiles(), isEmpty);
    });
  });

  group('BackupStore.restoreBackup', () {
    test('replaces the TOTPs by the backup content, re-encrypted with the device key', () async {
      BackupStore store = backupStore(totps: [totp('alice'), totp('bob')]);
      Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;

      Result<Backup> result = await store.restoreBackup(backup.backupPath, 'backup-password');

      expect(result, isA<ResultSuccess<Backup>>());
      expect(replacements, hasLength(1));
      List<Totp> restored = replacements.single;
      expect(restored.map((totp) => totp.uuid), unorderedEquals(['uuid-alice', 'uuid-bob']));
      expect(restored.map((totp) => (totp.decrypt(deviceStore) as DecryptedTotp).label), unorderedEquals(['alice', 'bob']));
    });

    test('rejects a wrong password and leaves the TOTPs alone', () async {
      BackupStore store = backupStore(totps: [totp('alice')]);
      Backup backup = ((await store.doBackup('backup-password')) as ResultSuccess<Backup>).value;

      Result<Backup> result = await store.restoreBackup(backup.backupPath, 'wrong-password');

      expect(result, isA<ResultError<Backup>>());
      expect((result as ResultError<Backup>).exception, isA<InvalidBackupPasswordException>());
      expect(replacements, isEmpty);
    });
  });

  group('BackupStore.import', () {
    test('copies the committed fixture, keeps its date, and restores both of its TOTPs', () async {
      CryptoStore otherDevice = CryptoStore.fromPassword('another-device-password', Salt.generate());
      BackupStore store = backupStore(store: otherDevice);
      backups.createSync(recursive: true);

      Result<BackupPath> imported = await store.import(File('test/model/backup/fixtures/1793500000000.bak'));
      BackupPath path = (imported as ResultSuccess<BackupPath>).value;
      Result<Backup> restored = await store.restoreBackup(path, _fixturePassword);

      expect(path.timestamp, DateTime.fromMillisecondsSinceEpoch(1793500000000));
      expect(backupFiles(), ['1793500000000.bak']);
      expect(restored, isA<ResultSuccess<Backup>>());
      Map<String, DecryptedTotp> totps = {for (Totp totp in replacements.single) totp.uuid: totp.decrypt(otherDevice) as DecryptedTotp};
      expect(totps.keys, unorderedEquals(['fixture-totp-1', 'fixture-totp-2']));
      expect([totps['fixture-totp-1']!.secret, totps['fixture-totp-1']!.label, totps['fixture-totp-1']!.issuer], ['JBSWY3DPEHPK3PXP', 'alice@example.com', 'Orbit']);
      expect([totps['fixture-totp-2']!.secret, totps['fixture-totp-2']!.label, totps['fixture-totp-2']!.issuer], ['GEZDGNBVGY3TQOJQ', 'bob', null]);
      expect([totps['fixture-totp-2']!.algorithm, totps['fixture-totp-2']!.digits, totps['fixture-totp-2']!.validity], [Algorithm.sha256, 8, const Duration(seconds: 60)]);
    });

    test('fails while no backup was ever made, since the backups directory does not exist yet', () async {
      BackupStore store = backupStore();

      Result<BackupPath> result = await store.import(File('test/model/backup/fixtures/1793500000000.bak'));

      expect(result, isA<ResultError<BackupPath>>());
      expect((result as ResultError<BackupPath>).exception, isA<FileSystemException>());
      expect(backups.existsSync(), isFalse);
    });

    test('rejects a file that is not a backup and copies nothing', () async {
      BackupStore store = backupStore();
      File notJson = File('${documents.path}${Platform.pathSeparator}1793500000000.bak')..writeAsStringSync('not json');
      File noSalt = File('${documents.path}${Platform.pathSeparator}other.bak')..writeAsStringSync(jsonEncode({Backup.kTotpsKey: [], Backup.kPasswordSignatureKey: 'x'}));

      Result<BackupPath> first = await store.import(notJson);
      Result<BackupPath> second = await store.import(noSalt);

      expect(first, isA<ResultError<BackupPath>>());
      expect(second, isA<ResultError<BackupPath>>());
      expect(backupFiles(), isEmpty);
    });
  });

  group('BackupStore.build', () {
    test('lists only files named with 13 digits and .bak, newest first', () async {
      backups.createSync(recursive: true);
      for (String name in ['1700000000000.bak', '1800000000000.bak', 'notes.txt', '123.bak', '17000000000000.json']) {
        File('${backups.path}${Platform.pathSeparator}$name').writeAsStringSync('{}');
      }
      backupStore();

      List<BackupPath> paths = await container.read(backupStoreProvider.future);

      expect(paths.map((path) => path.filename), ['1800000000000.bak', '1700000000000.bak']);
    });
  });
}
