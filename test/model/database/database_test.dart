import 'dart:io';

import 'package:drift/drift.dart' show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/database/database.dart';
import 'package:open_authenticator/model/totp/algorithm.dart';
import 'package:open_authenticator/model/totp/totp.dart';

/// The plugin channel `getApplicationSupportDirectory` and `getTemporaryDirectory` (for SQLite's temporary files) go through.
const MethodChannel _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// The `totps` table of schema version 1 (`drift_schemas/app/drift_schema_v1.json`), as the first
/// releases created it.
const String _schemaV1Totps =
    'CREATE TABLE "totps" ("uuid" TEXT NOT NULL, "secret" TEXT NOT NULL, "label" TEXT NULL, "issuer" TEXT NULL, '
    '"algorithm" TEXT NULL, "digits" INTEGER NULL, "validity" INTEGER NULL, "image_url" TEXT NULL, '
    '"encryption_salt" TEXT NOT NULL, PRIMARY KEY ("uuid"))';

/// Opens a database file at a given schema version, without the app's migrations.
class _RawUser extends QueryExecutorUser {
  @override
  final int schemaVersion;

  /// Creates a new raw user instance.
  _RawUser(this.schemaVersion);

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}

/// Creates a TOTP whose fields are all set.
Totp _totp(String uuid, {DateTime? updatedAt}) => Totp(
  uuid: uuid,
  encryptedData: EncryptedData(
    encryptedSecret: Uint8List.fromList([1, 2, 3]),
    encryptedLabel: Uint8List.fromList([4, 5]),
    encryptedIssuer: Uint8List.fromList([6]),
    encryptedImageUrl: Uint8List.fromList([7, 8]),
    encryptionSalt: Salt.fromRawValue(value: Uint8List.fromList([9, 10, 11])),
  ),
  algorithm: Algorithm.sha512,
  digits: 8,
  validity: const Duration(seconds: 60),
  updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(1762041600000),
);

/// Writes a schema version 1 database with one TOTP to [file].
Future<void> _writeSchemaV1(File file) async {
  NativeDatabase executor = NativeDatabase(
    file,
    setup: (database) {
      database.execute(_schemaV1Totps);
      database.execute(
        'INSERT INTO "totps" VALUES (\'legacy-uuid\', \'AQID\', \'BAU=\', NULL, \'sha256\', 6, 30, NULL, \'CQoL\')',
      );
    },
  );
  await executor.ensureOpen(_RawUser(1));
  await executor.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory support;

  /// The database file the app opens (debug suffix, since tests run in debug mode).
  File appFile() => File('${support.path}${Platform.pathSeparator}app_debug.sqlite');

  setUp(() {
    support = Directory.systemTemp.createTempSync('oa_database_test');
    messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async => const ['getApplicationSupportDirectory', 'getTemporaryDirectory'].contains(call.method) ? support.path : null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_pathProviderChannel, null);
    support.deleteSync(recursive: true);
  });

  group('AppDatabase', () {
    test('stores, updates and deletes TOTPs', () async {
      AppDatabase database = AppDatabase();

      await database.addTotps([_totp('a'), _totp('b')]);
      await database.updateTotp(_totp('a', updatedAt: DateTime.fromMillisecondsSinceEpoch(1762128000000)));
      await database.deleteTotp('b');

      expect(await database.listUuids(), ['a']);
      expect(await database.getTotp('a'), _totp('a', updatedAt: DateTime.fromMillisecondsSinceEpoch(1762128000000)));
      expect(await database.getTotp('b'), isNull);
      await database.close();
    });

    test('keeps the TOTPs in the file after it is closed', () async {
      AppDatabase database = AppDatabase();
      await database.addTotp(_totp('a'));
      await database.close();

      AppDatabase reopened = AppDatabase();

      expect(await reopened.listTotps(), [_totp('a')]);
      expect(appFile().existsSync(), isTrue);
      await reopened.close();
    });

    test('keeps deletion marks until they are removed, and replaces TOTPs with their tombstones', () async {
      AppDatabase database = AppDatabase();
      DateTime deletedAt = DateTime.fromMillisecondsSinceEpoch(1762041600000);
      await database.addTotps([_totp('a'), _totp('b')]);

      await database.replaceTotps([_totp('c')], {'a': deletedAt});

      expect(await database.listUuids(), ['c']);
      expect(await database.getDeletedTotps(), {'a': deletedAt});

      await database.removeDeletionMarks(['a']);

      expect(await database.getDeletedTotps(), isEmpty);
      await database.close();
    });

    test('clear removes every TOTP', () async {
      AppDatabase database = AppDatabase();
      await database.addTotps([_totp('a'), _totp('b')]);

      await database.clear();

      expect(await database.listTotps(), isEmpty);
      await database.close();
    });

    test('migrates a schema version 1 database and keeps its TOTPs', () async {
      await _writeSchemaV1(appFile());

      AppDatabase database = AppDatabase();
      List<Totp> totps = await database.listTotps();

      expect(totps, hasLength(1));
      expect(totps.single.uuid, 'legacy-uuid');
      expect(totps.single.encryptedData.encryptedSecret, [1, 2, 3]);
      expect(totps.single.encryptedData.encryptedLabel, [4, 5]);
      expect(totps.single.algorithm, Algorithm.sha256);
      expect(totps.single.validity, const Duration(seconds: 30));
      // Rows from version 1 get the column default: never updated.
      expect(totps.single.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(await database.getDeletedTotps(), isEmpty);
      expect(await database.listPendingBackendPushOperations(), isEmpty);
      await database.close();
    });

    test('imports the legacy database file and renames it', () async {
      File legacy = File('${support.path}${Platform.pathSeparator}totps_debug.sqlite');
      await _writeSchemaV1(legacy);

      AppDatabase database = AppDatabase();
      List<String> uuids = await database.listUuids();
      await database.close();

      expect(uuids, ['legacy-uuid']);
      expect(legacy.existsSync(), isFalse);
      // Upstream quirk, pinned: the suffix already starts with a dash, so the renamed file gets two.
      expect(File('${legacy.path}--migrated').existsSync(), isTrue);
    });
  });
}
