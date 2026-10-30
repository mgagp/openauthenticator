import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/clear_data.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/utils/platform.dart';

import 'support.dart';

void main() {
  late Platform platform;
  late InMemorySecureValues values;
  late SecureEzkeyEnrollmentStore store;

  setUp(() {
    platform = currentPlatform;
    currentPlatform = .android;
    values = InMemorySecureValues();
    store = SecureEzkeyEnrollmentStore(values);
  });

  tearDown(() => currentPlatform = platform);

  /// Shows a button that runs [action] with a ref whose providers use [store] and a key store in the
  /// `debug` namespace.
  Future<void> pumpHost(WidgetTester tester, Future<void> Function(BuildContext context, WidgetRef ref) action) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyEnrollmentStoreProvider.overrideWith((ref) async => store),
          ezkeyDeviceKeyStoreProvider.overrideWithValue(NativeEzkeyDeviceKeyStore(namespace: 'debug')),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: child!,
            ),
            home: Consumer(
              builder: (context, ref, child) => Center(
                child: TextButton(
                  onPressed: () => action(context, ref),
                  child: const Text('Clear'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('ezkeyClearDataServices', () {
    test('lists each service once, sorted, then one line per unreadable record', () {
      List<String> services = ezkeyClearDataServices(
        enrollments: [
          testEnrollment(1, integrationName: 'orbit Console'),
          testEnrollment(2, integrationName: 'Administration'),
          testEnrollment(3, integrationName: 'orbit Console'),
        ],
        unreadableCount: 1,
      );

      expect(services, ['Administration', 'orbit Console', translations.ezkey.clearData.unreadable]);
    });

    test('is empty without enrollments', () {
      expect(ezkeyClearDataServices(enrollments: const [], unreadableCount: 0), isEmpty);
    });
  });

  group('confirmEzkeyClearData', () {
    testWidgets('warns with the services involved, and Cancel stops the clear', (tester) async {
      await store.save(testEnrollment(1, integrationName: 'Internal Tools'));
      bool? goOn;
      await pumpHost(tester, (context, ref) async => goOn = await confirmEzkeyClearData(context, ref));

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text(translations.ezkey.clearData.title), findsOneWidget);
      expect(find.textContaining('• Internal Tools'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(goOn, isFalse);
    });

    testWidgets('goes on when the user confirms', (tester) async {
      await store.save(testEnrollment(1));
      bool? goOn;
      await pumpHost(tester, (context, ref) async => goOn = await confirmEzkeyClearData(context, ref));

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(goOn, isTrue);
    });

    testWidgets('goes on without asking when there is no enrollment', (tester) async {
      bool? goOn;
      await pumpHost(tester, (context, ref) async => goOn = await confirmEzkeyClearData(context, ref));

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(goOn, isTrue);
      expect(find.text(translations.ezkey.clearData.title), findsNothing);
    });

    testWidgets('goes on without asking where EzKey is not available', (tester) async {
      currentPlatform = .windows;
      await store.save(testEnrollment(1));
      bool? goOn;
      await pumpHost(tester, (context, ref) async => goOn = await confirmEzkeyClearData(context, ref));

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(goOn, isTrue);
      expect(find.text(translations.ezkey.clearData.title), findsNothing);
    });
  });

  group('deleteEzkeyKeysAfterClearData', () {
    /// Fakes the key store channel over [aliases]; deletions fail when [failDeletes] is set.
    void mockKeystore(Set<String> aliases, {bool failDeletes = false}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, (call) async {
        switch (call.method) {
          case 'aliases':
            String prefix = (call.arguments as Map)['prefix'] as String;
            return aliases.where((alias) => alias.startsWith(prefix)).toList();
          case 'deleteKeyPair':
            if (failDeletes) {
              throw PlatformException(code: 'KEYSTORE_ERROR');
            }
            aliases.remove((call.arguments as Map)['alias']);
            return null;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, null));
    }

    testWidgets('deletes this build\'s keys once the records are gone, and leaves the others', (tester) async {
      Set<String> aliases = {'ezkey-device-debug-1-a', 'ezkey-device-debug-2-b', 'ezkey-device-main-3-c', 'ezkey-device-4-d'};
      mockKeystore(aliases);
      await pumpHost(tester, (context, ref) => deleteEzkeyKeysAfterClearData(ref));

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(aliases, {'ezkey-device-main-3-c', 'ezkey-device-4-d'});
    });

    testWidgets('never fails the clear when the key store fails', (tester) async {
      Set<String> aliases = {'ezkey-device-debug-1-a'};
      mockKeystore(aliases, failDeletes: true);
      Object? error;
      bool done = false;
      await pumpHost(tester, (context, ref) async {
        try {
          await deleteEzkeyKeysAfterClearData(ref);
          done = true;
        } catch (ex) {
          error = ex;
        }
      });

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(error, isNull);
      expect(done, isTrue);
    });
  });
}
