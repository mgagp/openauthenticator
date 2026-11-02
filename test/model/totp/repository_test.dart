import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/crypto/derived_key.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/model/database/database.dart';
import 'package:open_authenticator/model/settings/storage_type.dart';
import 'package:open_authenticator/model/totp/decrypted.dart';
import 'package:open_authenticator/model/totp/image_cache.dart';
import 'package:open_authenticator/model/totp/repository.dart';
import 'package:open_authenticator/model/totp/totp.dart';
import 'package:open_authenticator/utils/result/result.dart';

/// The plugin channel `getApplicationSupportDirectory` and `getTemporaryDirectory` (for SQLite's temporary files) go through.
const MethodChannel _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// The master password before the change.
const String _oldPassword = 'old password';

/// The master password after the change.
const String _newPassword = 'new password';

/// Holds the salt in memory instead of the secure storage.
class _MemorySalt extends SaltNotifier {
  /// The salt.
  final Salt salt;

  /// Creates a new memory salt instance.
  _MemorySalt(this.salt);

  @override
  Future<Salt?> build() async => salt;
}

/// Holds the derived key in memory instead of the secure storage, and derives it as upstream does.
class _MemoryDerivedKey extends DerivedKeyNotifier {
  /// The salt the key is derived with.
  final Salt salt;

  /// Creates a new memory derived key instance.
  _MemoryDerivedKey(this.salt);

  @override
  FutureOr<DerivedKey?> build() => DerivedKey.fromPassword(_oldPassword, salt);

  @override
  Future<DerivedKey?> updateFromPassword(String password, {bool? andWrite}) async {
    DerivedKey key = DerivedKey.fromPassword(password, salt);
    state = AsyncData(key);
    return key;
  }
}

/// Keeps the TOTPs on this device only.
class _LocalOnly extends StorageTypeSettingsEntry {
  @override
  FutureOr<StorageType> build() => StorageType.localOnly;
}

/// An image cache that caches nothing.
class _NoImageCache extends TotpImageCacheManager {
  @override
  FutureOr<Map<String, CacheObject>> build() => {};

  @override
  Future<void> fillCache({Iterable<Totp>? totps, bool checkSettings = true}) async {}

  @override
  Future<void> deleteCachedImages(Iterable<String> uuids) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Salt salt;
  late CryptoStore oldStore;
  late CryptoStore newStore;
  late Directory support;
  late AppDatabase database;
  late ProviderContainer container;

  setUpAll(() {
    salt = Salt.generate();
    oldStore = CryptoStore.fromPassword(_oldPassword, salt);
    newStore = CryptoStore.fromPassword(_newPassword, salt);
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('oa_repository_test');
    messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async => const ['getApplicationSupportDirectory', 'getTemporaryDirectory'].contains(call.method) ? support.path : null);
    database = AppDatabase();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        saltProvider.overrideWith(() => _MemorySalt(salt)),
        derivedKeyProvider.overrideWith(() => _MemoryDerivedKey(salt)),
        storageTypeSettingsEntryProvider.overrideWith(_LocalOnly.new),
        totpImageCacheManagerProvider.overrideWith(_NoImageCache.new),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    messenger.setMockMethodCallHandler(_pathProviderChannel, null);
    support.deleteSync(recursive: true);
  });

  /// Returns a TOTP encrypted with [store], updated at [updatedAt].
  DecryptedTotp totp(String uuid, {CryptoStore? store, DateTime? updatedAt}) => DecryptedTotp.create(
    cryptoStore: store ?? oldStore,
    uuid: uuid,
    secret: 'JBSWY3DPEHPK3PXP',
    label: 'alice-$uuid',
    issuer: 'Orbit',
    updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(1762041600000),
  )!;

  /// Keeps the repository alive while a test uses it, as a screen watching it would.
  TotpRepository repository() {
    container.listen(totpRepositoryProvider, (previous, next) {});
    return container.read(totpRepositoryProvider.notifier);
  }

  group('TotpRepository', () {
    test('adds, updates and deletes TOTPs in the database', () async {
      TotpRepository totps = repository();
      await container.read(totpRepositoryProvider.future);

      await totps.addTotps([totp('a'), totp('b')]);
      await totps.updateTotp(totp('a', updatedAt: DateTime.fromMillisecondsSinceEpoch(1762128000000)));
      Result deleted = await totps.deleteTotp('b', dateTime: DateTime.fromMillisecondsSinceEpoch(1762128000000));

      expect(deleted, isA<ResultSuccess>());
      expect(await database.listUuids(), ['a']);
      expect((await database.getTotp('a'))!.updatedAt, DateTime.fromMillisecondsSinceEpoch(1762128000000));
      expect(await database.getDeletedTotps(), {'b': DateTime.fromMillisecondsSinceEpoch(1762128000000)});
      expect((await container.read(totpRepositoryProvider.future)).map((totp) => totp.uuid), ['a']);
    });

    test('ignores a TOTP deleted after its last update, and restores one updated after its deletion', () async {
      DateTime deletedAt = DateTime.fromMillisecondsSinceEpoch(1762128000000);
      await database.markAsDeleted({'old': deletedAt, 'new': deletedAt});
      TotpRepository totps = repository();
      await container.read(totpRepositoryProvider.future);

      await totps.addTotps([
        totp('old', updatedAt: DateTime.fromMillisecondsSinceEpoch(1762041600000)),
        totp('new', updatedAt: DateTime.fromMillisecondsSinceEpoch(1762214400000)),
      ]);

      expect(await database.listUuids(), ['new']);
      expect(await database.getDeletedTotps(), {'old': deletedAt});
    });

    test('changing the master password re-encrypts every TOTP with the new key', () async {
      await database.addTotps([totp('a'), totp('b')]);
      TotpRepository totps = repository();
      await container.read(totpRepositoryProvider.future);

      Result<String> result = await totps.changeMasterPassword(_newPassword);
      List<Totp> stored = await database.listTotps();

      expect(result, isA<ResultSuccess<String>>());
      expect(stored, hasLength(2));
      for (Totp totp in stored) {
        Totp withNewKey = totp.decrypt(newStore);
        expect(withNewKey.isDecrypted, isTrue);
        expect((withNewKey as DecryptedTotp).secret, 'JBSWY3DPEHPK3PXP');
        expect(withNewKey.label, 'alice-${totp.uuid}');
        expect(totp.decrypt(oldStore).isDecrypted, isFalse);
      }
      expect(await container.read(cryptoStoreProvider.future), newStore);
      expect((await container.read(totpRepositoryProvider.future)).every((totp) => totp.isDecrypted), isTrue);
    });

    test('changing the master password keeps a TOTP that no key can decrypt as it is', () async {
      CryptoStore foreignStore = CryptoStore.fromPassword('someone else', Salt.generate());
      DecryptedTotp foreign = totp('foreign', store: foreignStore);
      await database.addTotps([totp('a'), foreign]);
      TotpRepository totps = repository();
      await container.read(totpRepositoryProvider.future);

      await totps.changeMasterPassword(_newPassword);

      Totp? kept = await database.getTotp('foreign');
      expect(kept!.encryptedData.encryptedSecret, foreign.encryptedData.encryptedSecret);
      expect(kept.decrypt(foreignStore).isDecrypted, isTrue);
      expect((await database.getTotp('a'))!.decrypt(newStore).isDecrypted, isTrue);
    });
  });
}
