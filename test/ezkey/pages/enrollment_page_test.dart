import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/pages/enrollment_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';

import '../support.dart';

/// Records the pending checks and answers that nothing is waiting.
class _RecordingAuthApi implements EzkeyAuthApi {
  /// The enrollment ids checked, in order.
  final List<int> checked = [];

  @override
  Future<PendingAuthResponse?> pending(PendingAuthRequest request) async {
    checked.add(request.enrollmentId);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _RecordingAuthApi api;
  late EzkeyEnrollment enrollment;
  late EzkeyAuthenticator authenticator;

  setUp(() async {
    api = _RecordingAuthApi();
    SoftwareDeviceKeyStore keyStore = SoftwareDeviceKeyStore();
    await keyStore.generateKeyPair('key-5');
    await keyStore.generateKeyPair('key-6');
    enrollment = testEnrollment(5, deviceKeyAlias: 'key-5', integrationName: 'Internal Tools', authApiBaseUrl: 'https://ezkey.example');
    InMemoryEnrollmentStore store = InMemoryEnrollmentStore();
    await store.save(enrollment);
    await store.save(testEnrollment(6, deviceKeyAlias: 'key-6', integrationName: 'Administration'));
    authenticator = EzkeyAuthenticator(keyStore: keyStore, enrollmentStore: store, apiFactory: (uri) => api);
  });

  /// Shows the page for [enrollment].
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyAuthenticatorProvider.overrideWith((ref) async => authenticator),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
            ),
            home: EzkeyEnrollmentPage(enrollment: enrollment),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EzkeyEnrollmentPage', () {
    testWidgets('shows who the enrollment is for and where its key lives', (tester) async {
      await pumpPage(tester);

      expect(find.text('Internal Tools'), findsWidgets);
      expect(find.text('Alice Chen'), findsOneWidget);
      expect(find.text(ezkeyStorageTierLabel(.strong)), findsOneWidget);
      expect(find.text('ezkey.example'), findsOneWidget);
    });

    testWidgets('checks for requests on this enrollment only', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-enrollment-check')));
      await tester.pumpAndSettle();

      expect(api.checked, [5]);
      expect(find.text(translations.ezkey.attempt.check.none), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
