import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/pages/enroll_page.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/widgets/clickable.dart';

import '../support.dart';

/// An invitation for enrollment 12 that carries its Auth API address.
const String _invitation = '{"enrollmentProofToken":"proof-token-12","authUrl":"https://auth.example.com"}';

void main() {
  /// Shows the page for [_invitation], bound as an administrator of type [adminType] when it is set.
  Future<void> pumpPage(WidgetTester tester, {String? adminType}) async {
    EzkeyBoundEnrollment bound = (await tester.runAsync(() async {
      Ed25519TestKeyPair integrationKey = await generateEd25519TestKeyPair();
      EzkeyAuthenticator authenticator = EzkeyAuthenticator(
        keyStore: SoftwareDeviceKeyStore(),
        enrollmentStore: InMemoryEnrollmentStore(),
        apiFactory: (uri) => BindingAuthApi(integrationKey, adminType: adminType),
      );
      return authenticator.bindEnrollment(EnrollmentCode.parse(_invitation));
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
            ),
            home: EzkeyEnrollPage(bound: bound),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether the submit button can be pressed.
  bool canSubmit(WidgetTester tester) => tester.widget<ClickableButton>(find.byKey(const ValueKey('ezkey-enroll-submit'))).onPress != null;

  group('EzkeyEnrollPage', () {
    testWidgets('shows who is asking, from the signed answer, and the server', (tester) async {
      await pumpPage(tester);

      expect(find.text('Orbit Console'), findsOneWidget);
      expect(find.text('Ezkey System'), findsOneWidget);
      expect(find.text('Alice Chen'), findsOneWidget);
      expect(find.text('auth.example.com'), findsOneWidget);
      expect(find.text(translations.ezkey.enroll.administrator), findsNothing);
    });

    testWidgets('an administrator invitation carries the administrator warning', (tester) async {
      await pumpPage(tester, adminType: 'GLOBAL_ADMIN');

      expect(find.text(translations.ezkey.enroll.administrator), findsOneWidget);
    });

    // A focused forui text field fails a semantics assertion (forui 0.25, docs/ezkey/integration.md
    // § Open points), hence `semanticsEnabled: false`.
    testWidgets('the code can be sent only once it has six digits', semanticsEnabled: false, (tester) async {
      await pumpPage(tester);
      expect(canSubmit(tester), isFalse);

      await tester.enterText(find.byKey(const ValueKey('ezkey-enrollment-code')), '12345');
      await tester.pump();
      expect(canSubmit(tester), isFalse);

      await tester.enterText(find.byKey(const ValueKey('ezkey-enrollment-code')), '123456');
      await tester.pump();

      expect(canSubmit(tester), isTrue);
    });
  });
}
