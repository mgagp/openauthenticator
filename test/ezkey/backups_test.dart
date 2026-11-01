import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:open_authenticator/ezkey/backups.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/model/backup/backup.dart';
import 'package:open_authenticator/pages/settings/entries/backup_now.dart';
import 'package:open_authenticator/pages/settings/entries/manage_backups.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/utils/platform.dart';
import 'package:open_authenticator/widgets/expandable_tile.dart';

import 'support.dart';

/// A backup store that holds fixed paths, without the file system listing.
class _FixedBackups extends BackupStore {
  /// The backup paths.
  final List<BackupPath> paths;

  /// Creates a new fixed backup store instance.
  _FixedBackups(this.paths);

  @override
  FutureOr<List<BackupPath>> build() => paths;
}

void main() {
  late Platform platform;
  late InMemorySecureValues values;
  late SecureEzkeyEnrollmentStore store;
  late bool storeFails;

  setUpAll(initializeDateFormatting);

  setUp(() {
    platform = currentPlatform;
    currentPlatform = .android;
    values = InMemorySecureValues();
    store = SecureEzkeyEnrollmentStore(values);
    storeFails = false;
  });

  tearDown(() => currentPlatform = platform);

  /// Shows [child] in a scope whose EzKey enrollment store is [store], or fails when [storeFails].
  Future<void> pumpScope(WidgetTester tester, Widget child, {List overrides = const []}) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        ezkeyEnrollmentStoreProvider.overrideWith((ref) async => storeFails ? throw StateError('secure storage unavailable') : store),
        ...overrides,
      ],
      child: TranslationProvider(
        child: MaterialApp(
          builder: (context, child) => FTheme(
            data: greenTheme.light.touch,
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );

  /// Returns what [hook] makes of [message], through a widget ref.
  Future<String?> run(WidgetTester tester, Future<String> Function(WidgetRef ref, String message) hook, String message) async {
    String? result;
    await pumpScope(
      tester,
      Consumer(
        builder: (context, ref, child) => TextButton(
          onPressed: () async => result = await hook(ref, message),
          child: const Text('Run'),
        ),
      ),
    );
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    return result;
  }

  group('withEzkeyBackupNote', () {
    testWidgets('adds the note when this device holds EzKey enrollments', (tester) async {
      await store.save(testEnrollment(1));

      String? message = await run(tester, withEzkeyBackupNote, 'Upstream message.');

      expect(message, 'Upstream message.\n\n${translations.ezkey.backups.backupNote}');
    });

    testWidgets('adds the note for an unreadable record too', (tester) async {
      values.values['${SecureEzkeyEnrollmentStore.keyPrefix}http://localhost:8080#2'] = '{not json';

      String? message = await run(tester, withEzkeyBackupNote, 'Upstream message.');

      expect(message, 'Upstream message.\n\n${translations.ezkey.backups.backupNote}');
    });

    testWidgets('keeps upstream\'s message without enrollments', (tester) async {
      String? message = await run(tester, withEzkeyBackupNote, 'Upstream message.');

      expect(message, 'Upstream message.');
    });

    testWidgets('keeps upstream\'s message where EzKey is not available', (tester) async {
      currentPlatform = .windows;
      await store.save(testEnrollment(1));

      String? message = await run(tester, withEzkeyBackupNote, 'Upstream message.');

      expect(message, 'Upstream message.');
    });

    testWidgets('keeps upstream\'s message when the enrollment store fails', (tester) async {
      storeFails = true;

      String? message = await run(tester, withEzkeyBackupNote, 'Upstream message.');

      expect(message, 'Upstream message.');
    });
  });

  group('withEzkeyRestoreNote', () {
    testWidgets('adds the restore note when this device holds EzKey enrollments', (tester) async {
      await store.save(testEnrollment(1));

      String? message = await run(tester, withEzkeyRestoreNote, 'Upstream message.');

      expect(message, 'Upstream message.\n\n${translations.ezkey.backups.restoreNote}');
    });

    testWidgets('keeps upstream\'s message without enrollments', (tester) async {
      String? message = await run(tester, withEzkeyRestoreNote, 'Upstream message.');

      expect(message, 'Upstream message.');
    });
  });

  // These open upstream's TextInputDialog, whose forui text field fails a semantics assertion in debug
  // (forui 0.25, docs/ezkey/integration.md § Open points), hence `semanticsEnabled: false`.
  group('Upstream hooks', () {
    testWidgets('"Backup now" shows the note in its password dialog', semanticsEnabled: false, (tester) async {
      await store.save(testEnrollment(1));
      await pumpScope(tester, const BackupNowSettingsEntryWidget());

      await tester.tap(find.text(translations.settings.backups.backupNow.title));
      await tester.pumpAndSettle();

      expect(find.text(translations.settings.backups.backupNow.passwordDialog.title), findsOneWidget);
      expect(find.textContaining(translations.ezkey.backups.backupNote), findsOneWidget);
    });

    testWidgets('"Backup now" shows upstream\'s dialog unchanged without enrollments', semanticsEnabled: false, (tester) async {
      await pumpScope(tester, const BackupNowSettingsEntryWidget());

      await tester.tap(find.text(translations.settings.backups.backupNow.title));
      await tester.pumpAndSettle();

      expect(find.text(translations.settings.backups.backupNow.passwordDialog.message), findsOneWidget);
      expect(find.textContaining(translations.ezkey.backups.backupNote), findsNothing);
    });

    testWidgets('"Restore" shows the restore note in its password dialog', semanticsEnabled: false, (tester) async {
      await store.save(testEnrollment(1));
      Directory directory = Directory.systemTemp.createTempSync('oa_ezkey_backups');
      addTearDown(() => directory.deleteSync(recursive: true));
      File file = File('${directory.path}/1793500000000.bak')..writeAsStringSync('{}');
      await pumpScope(
        tester,
        const ManageBackupSettingsEntryWidget(),
        overrides: [
          backupStoreProvider.overrideWith(() => _FixedBackups([BackupPath.fromPath(path: file.path)!])),
        ],
      );

      await tester.tap(find.text(translations.settings.backups.manageBackups.title));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(ExpandableTile), matching: find.byIcon(FLucideIcons.chevronRight)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(translations.settings.backups.manageBackups.button.restore));
      await tester.pumpAndSettle();

      expect(find.text(translations.settings.backups.manageBackups.restoreBackupPasswordDialog.title), findsOneWidget);
      expect(find.textContaining(translations.ezkey.backups.restoreNote), findsOneWidget);
    });
  });
}
