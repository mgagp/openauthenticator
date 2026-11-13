import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/pages/enroll_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';

import 'support.dart';

/// An Auth API that cannot be reached.
class _UnreachableAuthApi implements EzkeyAuthApi {
  @override
  Future<EnrollmentBindResponse> bind(EnrollmentBindRequest request) async => throw const EzkeyNetworkException('timeout');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// An invitation for enrollment 14 that does not carry its Auth API address.
const String _invitationWithoutServer = '{"enrollmentProofToken":"proof-token-14"}';

/// An invitation for enrollment 12 that carries its Auth API address.
const String _invitation = '{"enrollmentProofToken":"proof-token-12","authUrl":"https://auth.example.com"}';

void main() {
  late Ed25519TestKeyPair integrationKey;
  late List<Uri> apiUris;
  late EzkeyAuthApi Function() api;
  late bool? opened;

  setUpAll(() async {
    integrationKey = await generateEd25519TestKeyPair();
  });

  setUp(() {
    apiUris = [];
    api = () => BindingAuthApi(integrationKey);
    opened = null;
  });

  /// Shows a page whose "Add" button adds [code], then presses it.
  Future<void> add(WidgetTester tester, String code) async {
    EzkeyAuthenticator authenticator = EzkeyAuthenticator(
      keyStore: SoftwareDeviceKeyStore(),
      enrollmentStore: InMemoryEnrollmentStore(),
      apiFactory: (uri) {
        apiUris.add(uri);
        return api();
      },
    );
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
            home: Consumer(
              builder: (context, ref, child) => Scaffold(
                body: TextButton(
                  onPressed: () async => opened = await EzkeyActions.addEnrollment(context, ref, code),
                  child: const Text('Add'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  /// Lets the toasts close.
  Future<void> closeToasts(WidgetTester tester) => tester.pump(const Duration(seconds: 10));

  group('EzkeyActions.addEnrollment', () {
    testWidgets('an invitation with its server address opens the enrollment page', (tester) async {
      await add(tester, _invitation);

      expect(find.byType(EzkeyEnrollPage), findsOneWidget);
      expect(apiUris.single.host, 'auth.example.com');
    });

    testWidgets('content that is not an invitation says so, and opens nothing', (tester) async {
      await add(tester, 'hello');

      expect(find.text(translations.ezkey.scan.notAnInvitation), findsOneWidget);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
      expect(opened, isFalse);
      await closeToasts(tester);
    });

    // The server address dialog has a forui text field, which fails a semantics assertion when focused
    // (forui 0.25, docs/ezkey/integration.md § Open points), hence `semanticsEnabled: false`.
    testWidgets('an invitation without its server address asks for it, and binds there', semanticsEnabled: false, (tester) async {
      await add(tester, _invitationWithoutServer);

      expect(find.text(translations.ezkey.server.title), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'https://auth.example.org');
      await tester.pump();
      await tester.tap(find.text(MaterialLocalizations.of(tester.element(find.byType(EditableText))).okButtonLabel));
      await tester.pumpAndSettle();

      expect(find.byType(EzkeyEnrollPage), findsOneWidget);
      expect(apiUris.single.host, 'auth.example.org');
    });

    testWidgets('cancelling the server address question binds nothing, and opens nothing', semanticsEnabled: false, (tester) async {
      await add(tester, _invitationWithoutServer);

      await tester.tap(find.text(MaterialLocalizations.of(tester.element(find.byType(EditableText))).cancelButtonLabel));
      await tester.pumpAndSettle();

      expect(find.byType(EzkeyEnrollPage), findsNothing);
      expect(find.byType(FToast), findsNothing);
      expect(apiUris, isEmpty);
      expect(opened, isFalse);
    });

    testWidgets('a bind that fails says why, and opens nothing', (tester) async {
      api = _UnreachableAuthApi.new;

      await add(tester, _invitation);

      expect(find.text(translations.ezkey.error.network), findsOneWidget);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
      expect(opened, isFalse);
      await closeToasts(tester);
    });
  });
}
