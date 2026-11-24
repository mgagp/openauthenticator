import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/pages/enroll_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/widgets/paste_invitation_dialog.dart';
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

  /// Shows a page whose "Add" button calls [onAdd], then presses it.
  Future<void> pressAdd(WidgetTester tester, Future<void> Function(BuildContext context, WidgetRef ref) onAdd) async {
    final EzkeyAuthenticator authenticator = EzkeyAuthenticator(
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
                  onPressed: () => onAdd(context, ref),
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

  /// Adds [code] as an invitation.
  Future<void> add(WidgetTester tester, String code) => pressAdd(
    tester,
    (context, ref) async => opened = await EzkeyActions.addEnrollment(context, ref, code),
  );

  /// Opens the paste dialog, pastes [text] and confirms.
  Future<void> paste(WidgetTester tester, String text) async {
    await pressAdd(tester, EzkeyActions.addFromText);
    await tester.enterText(find.byType(EditableText), text);
    await tester.pump();
    await tester.tap(find.text(MaterialLocalizations.of(tester.element(find.byType(EditableText))).okButtonLabel));
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

  group('EzkeyActions.addFromText', () {
    /// Runs [body] and returns what it logged.
    Future<String> logged(Future<void> Function() body) async {
      final DebugPrintCallback original = debugPrint;
      final StringBuffer log = StringBuffer();
      debugPrint = (message, {wrapWidth}) => log.writeln(message);
      try {
        await body();
      } finally {
        debugPrint = original;
      }
      return log.toString();
    }

    testWidgets('a pasted invitation opens the enrollment page, with spaces and line breaks around it', (tester) async {
      await paste(tester, '\n  $_invitation \n');

      expect(find.byType(EzkeyEnrollPage), findsOneWidget);
      expect(apiUris.single.host, 'auth.example.com');
    });

    testWidgets('a pasted invitation without its server address asks for it', (tester) async {
      await paste(tester, _invitationWithoutServer);

      expect(find.text(translations.ezkey.server.title), findsOneWidget);
      expect(apiUris, isEmpty);
    });

    testWidgets('malformed text says it is not an invitation, and never logs it', (tester) async {
      final String log = await logged(() => paste(tester, '{"enrollmentProofToken":"proof-token-12"'));

      expect(find.text(translations.ezkey.scan.notAnInvitation), findsOneWidget);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
      expect(log, isNot(contains('proof-token')));
      await closeToasts(tester);
    });

    testWidgets('a bind that fails never logs the pasted token', (tester) async {
      api = _UnreachableAuthApi.new;

      final String log = await logged(() => paste(tester, _invitation));

      expect(log, contains('EzKey bind failed'));
      expect(log, isNot(contains('proof-token')));
      await closeToasts(tester);
    });

    testWidgets('a server address that is not secure is refused', (tester) async {
      await paste(tester, '{"enrollmentProofToken":"proof-token-12","authUrl":"http://auth.example.com"}');

      expect(find.byType(EzkeyEnrollPage), findsNothing);
      expect(apiUris, isEmpty);
      await closeToasts(tester);
    });

    testWidgets('cancelling, or confirming an empty field, adds nothing', (tester) async {
      await pressAdd(tester, EzkeyActions.addFromText);
      final MaterialLocalizations localizations = MaterialLocalizations.of(tester.element(find.byType(EditableText)));

      await tester.tap(find.text(localizations.okButtonLabel), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(EzkeyPasteInvitationDialog), findsOneWidget);

      await tester.tap(find.text(localizations.cancelButtonLabel));
      await tester.pumpAndSettle();
      expect(find.byType(EzkeyPasteInvitationDialog), findsNothing);
      expect(find.byType(FToast), findsNothing);
      expect(apiUris, isEmpty);
    });

    testWidgets('the field lets nothing keep or alter the text', (tester) async {
      await pressAdd(tester, EzkeyActions.addFromText);
      final EditableText field = tester.widget(find.byType(EditableText));

      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.autofillHints, isNull);
    });

    testWidgets('the field is emptied as soon as it is read', (tester) async {
      await pressAdd(tester, EzkeyActions.addFromText);
      await tester.enterText(find.byType(EditableText), _invitation);
      await tester.pump();
      final TextEditingController controller = tester.widget<EditableText>(find.byType(EditableText)).controller;

      await tester.tap(find.text(MaterialLocalizations.of(tester.element(find.byType(EditableText))).okButtonLabel));

      expect(controller.text, isEmpty);
      await tester.pumpAndSettle();
    });
  });
}
