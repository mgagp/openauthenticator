import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/installations.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/ezkey/pages/approval_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';

import '../support.dart';

/// Records the respond calls. Unless [answer] is set, it refuses them with a 409 conflict, so no
/// result signature is needed.
class _RecordingAuthApi implements EzkeyAuthApi {
  /// The respond requests, in order.
  final List<RespondAuthRequest> responds = [];

  /// Answers the respond calls, when set.
  Future<RespondAuthResponse> Function(RespondAuthRequest request)? answer;

  @override
  Future<RespondAuthResponse> respond(RespondAuthRequest request) async {
    responds.add(request);
    if (answer != null) {
      return answer!(request);
    }
    throw _refusal(409, type: 'https://ezkey.io/problems/auth/auth-attempt-state-conflict');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Returns the refusal of a respond call with [statusCode] and the problem [type].
EzkeyApiException _refusal(int statusCode, {String? type}) => EzkeyApiException(
  method: 'POST',
  path: '/api/v1/auth-attempts/respond',
  statusCode: statusCode,
  problem: type == null ? null : EzkeyProblem(type: type),
);

/// Keeps the approval protection in memory instead of the shared preferences.
class _MemorySecurity extends EzkeyApprovalSecurityEntry {
  /// The protection.
  final EzkeyApprovalSecurity security;

  /// Creates a new memory security instance.
  _MemorySecurity(this.security);

  @override
  FutureOr<EzkeyApprovalSecurity> build() => security;
}

void main() {
  late _RecordingAuthApi api;
  late int confirmations;
  late EzkeyEnrollment enrollment;
  late PendingAuthAttempt attempt;
  late EzkeyAuthenticator authenticator;

  /// Returns an attempt of [enrollment], claimed at [receivedAt] (now by default).
  PendingAuthAttempt testAttempt({bool challengeRequired = false, DateTime? receivedAt}) => PendingAuthAttempt(
    enrollmentLocalId: enrollment.localId,
    authAttemptId: 7,
    authAttemptProofToken: 'attempt-proof-token',
    challengeRequired: challengeRequired,
    receivedAt: receivedAt ?? DateTime.now().toUtc(),
    contextTitle: 'Sign in to Orbit Console',
  );

  setUp(() async {
    api = _RecordingAuthApi();
    confirmations = 0;
    SoftwareDeviceKeyStore keyStore = SoftwareDeviceKeyStore();
    await keyStore.generateKeyPair('test-key');
    enrollment = testEnrollment(5, deviceKeyAlias: 'test-key');
    attempt = testAttempt();
    authenticator = EzkeyAuthenticator(keyStore: keyStore, enrollmentStore: InMemoryEnrollmentStore(), apiFactory: (uri) => api);
  });

  /// Opens the approval page above a home page, with the user's [security] choice and the local
  /// confirmation answering [confirmed].
  Future<void> openPage(WidgetTester tester, {EzkeyApprovalSecurity security = .confirmBeforeApprovals, bool confirmed = true, List<EzkeyEnrollment>? onDevice}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyAuthenticatorProvider.overrideWith((ref) async => authenticator),
          ezkeyInstallationsProvider.overrideWith((ref) async => EzkeyInstallation.group(onDevice ?? [enrollment])),
          ezkeyApprovalSecurityProvider.overrideWith(() => _MemorySecurity(security)),
          ezkeyApprovalConfirmationProvider.overrideWithValue((_) async {
            confirmations++;
            return confirmed;
          }),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
            ),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => EzkeyApprovalPage.open(context, enrollment, attempt),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Leaves the approval page as the system back gesture would.
  Future<void> leave(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
  }

  /// Lets the toasts expire, so no timer is left pending.
  Future<void> drainToasts(WidgetTester tester) => tester.pump(const Duration(seconds: 30));

  group('EzkeyApprovalPage', () {
    group('the identity', () {
      testWidgets('a regular request shows the application, the account and the organization, and no server', (tester) async {
        await openPage(tester);

        expect(find.text('Orbit Console'), findsOneWidget);
        expect(find.text('Alice Chen'), findsOneWidget);
        expect(find.text('${translations.ezkey.enroll.account} · Ezkey System'), findsOneWidget);
        expect(find.text('localhost:8080'), findsNothing);
      });

      testWidgets('with several installations, it names the server', (tester) async {
        await openPage(
          tester,
          onDevice: [
            enrollment,
            testEnrollment(9, authApiBaseUrl: 'https://other.example'),
          ],
        );

        expect(find.text('localhost:8080'), findsOneWidget);
        expect(find.text('other.example'), findsNothing);
      });

      testWidgets('an administrator request shows Administration and the role, and no organization', (tester) async {
        enrollment = testAdminEnrollment(5, adminType: 'GLOBAL_ADMIN');

        await openPage(tester);

        expect(find.text(translations.ezkey.identity.administration), findsOneWidget);
        expect(find.text(translations.ezkey.identity.globalAdmin), findsOneWidget);
        expect(find.text('Alice Chen'), findsOneWidget);
        expect(find.textContaining('Ezkey System'), findsNothing);
        expect(find.text('Ezkey Administration'), findsNothing);
      });
    });

    testWidgets('leaving an undecided attempt denies it once', (tester) async {
      await openPage(tester);

      await leave(tester);

      expect(api.responds, hasLength(1));
      expect(api.responds.single.authAttemptAccepted, isFalse);
      expect(attempt.canDecide, isFalse);
      await drainToasts(tester);
    });

    testWidgets('a cancelled confirmation sends nothing and keeps the attempt open', (tester) async {
      await openPage(tester, confirmed: false);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(confirmations, 1);
      expect(api.responds, isEmpty);
      expect(attempt.canDecide, isTrue);
      expect(find.byType(EzkeyApprovalPage), findsOneWidget);
      await leave(tester);
      expect(api.responds.single.authAttemptAccepted, isFalse);
      await drainToasts(tester);
    });

    testWidgets('in standard mode, approving asks for no confirmation', (tester) async {
      await openPage(tester, security: .standard, confirmed: false);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(confirmations, 0);
      expect(api.responds.single.authAttemptAccepted, isTrue);
      await drainToasts(tester);
    });

    testWidgets('a failed leave-as-deny says the request will expire on its own', (tester) async {
      await openPage(tester);

      await leave(tester);

      expect(find.text(translations.ezkey.attempt.leaveDenyFailed), findsOneWidget);
      await drainToasts(tester);
    });

    testWidgets('leaving an expired attempt sends nothing', (tester) async {
      attempt = testAttempt(receivedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)));
      await openPage(tester);

      await leave(tester);

      expect(api.responds, isEmpty);
    });

    testWidgets('denying asks for no confirmation, sends the denial and leaves the page', (tester) async {
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-deny')));
      await tester.pumpAndSettle();

      expect(confirmations, 0);
      expect(api.responds.single.authAttemptAccepted, isFalse);
      expect(find.byType(EzkeyApprovalPage), findsNothing);
      await drainToasts(tester);
    });

    testWidgets('deciding on an expired attempt sends nothing, says so and leaves the page', (tester) async {
      attempt = testAttempt(receivedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)));
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(confirmations, 0);
      expect(api.responds, isEmpty);
      expect(find.byType(EzkeyApprovalPage), findsNothing);
      expect(find.text(translations.ezkey.attempt.result.expired), findsOneWidget);
      await drainToasts(tester);
    });

    testWidgets('an attempt with a code cannot be approved without it, and sends it', (tester) async {
      attempt = testAttempt(challengeRequired: true);
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();
      expect(api.responds, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('ezkey-attempt-code')), '123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(api.responds.single.authAttemptAccepted, isTrue);
      expect(api.responds.single.authAttemptChallengeResponse, 123456);
      await drainToasts(tester);
      // Without the semantics tree: with it, Flutter's own semantics assertions fail while the page with the code field closes.
    }, semanticsEnabled: false);

    testWidgets('a signed approval says the sign-in is approved and leaves the page', (tester) async {
      Ed25519TestKeyPair integrationKey = (await tester.runAsync(generateEd25519TestKeyPair))!;
      enrollment = EzkeyEnrollment.fromJson({
        ...enrollment.toJson(),
        'integrationPublicKey': integrationKey.publicKeyBase64Url,
      });
      attempt = testAttempt();
      api.answer = (request) async => RespondAuthResponse(
        authAttemptId: request.authAttemptId,
        authAttemptResult: 'APPROVED',
        authAttemptMessage: '',
        authAttemptProofTokenResultSignedByIntegration: await signEd25519WithPkcs8(
          buildRespondResultPayload(attempt.authAttemptProofToken, '${request.authAttemptId}', 'APPROVED', ''),
          integrationKey.pkcs8Base64Std,
        ),
      );
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(find.text(translations.ezkey.attempt.result.approved), findsOneWidget);
      expect(find.byType(EzkeyApprovalPage), findsNothing);
      expect(api.responds, hasLength(1));
      await drainToasts(tester);
    });

    testWidgets('a refusal that can be retried keeps the page open for another decision', (tester) async {
      api.answer = (request) async => throw _refusal(429);
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(find.text(translations.ezkey.error.rateLimited), findsOneWidget);
      expect(find.byType(EzkeyApprovalPage), findsOneWidget);
      expect(attempt.canDecide, isTrue);
      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-deny')));
      await tester.pumpAndSettle();
      expect(api.responds, hasLength(2));
      expect(api.responds.last.authAttemptAccepted, isFalse);
      await drainToasts(tester);
    });

    testWidgets('an answer whose result is unknown says so, leaves the page and sends nothing more', (tester) async {
      api.answer = (request) async => throw const EzkeyNetworkException('connection reset');
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(find.text(translations.ezkey.attempt.uncertain), findsOneWidget);
      expect(find.byType(EzkeyApprovalPage), findsNothing);
      expect(api.responds, hasLength(1));
      await drainToasts(tester);
    });

    testWidgets('a sent decision is not followed by a leave-as-deny', (tester) async {
      await openPage(tester);

      await tester.tap(find.byKey(const ValueKey('ezkey-attempt-approve')));
      await tester.pumpAndSettle();

      expect(api.responds, hasLength(1));
      expect(api.responds.single.authAttemptAccepted, isTrue);
      expect(find.byType(EzkeyApprovalPage), findsNothing);
      expect(find.text(translations.ezkey.attempt.noLongerActive), findsOneWidget);
      await drainToasts(tester);
    });
  });
}
