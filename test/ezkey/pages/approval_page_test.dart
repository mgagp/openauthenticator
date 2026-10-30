import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/ezkey/pages/approval_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';

import '../support.dart';

/// Records the respond calls and refuses them with a 409 conflict, so no result signature is needed.
class _RecordingAuthApi implements EzkeyAuthApi {
  /// The respond requests, in order.
  final List<RespondAuthRequest> responds = [];

  @override
  Future<RespondAuthResponse> respond(RespondAuthRequest request) async {
    responds.add(request);
    throw EzkeyApiException(
      method: 'POST',
      path: '/api/v1/auth-attempts/respond',
      statusCode: 409,
      problem: const EzkeyProblem(type: 'https://ezkey.io/problems/auth/auth-attempt-state-conflict'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

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

  setUp(() async {
    api = _RecordingAuthApi();
    confirmations = 0;
    SoftwareDeviceKeyStore keyStore = SoftwareDeviceKeyStore();
    await keyStore.generateKeyPair('test-key');
    enrollment = testEnrollment(5, deviceKeyAlias: 'test-key');
    attempt = PendingAuthAttempt(
      enrollmentLocalId: enrollment.localId,
      authAttemptId: 7,
      authAttemptProofToken: 'attempt-proof-token',
      challengeRequired: false,
      receivedAt: DateTime.now().toUtc(),
      contextTitle: 'Sign in to Orbit Console',
    );
    authenticator = EzkeyAuthenticator(keyStore: keyStore, enrollmentStore: InMemoryEnrollmentStore(), apiFactory: (uri) => api);
  });

  /// Opens the approval page above a home page, with the user's [security] choice and the local
  /// confirmation answering [confirmed].
  Future<void> openPage(WidgetTester tester, {EzkeyApprovalSecurity security = .confirmBeforeApprovals, bool confirmed = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyAuthenticatorProvider.overrideWith((ref) async => authenticator),
          ezkeyApprovalSecurityProvider.overrideWith(() => _MemorySecurity(security)),
          ezkeyApprovalConfirmationProvider.overrideWithValue(() async {
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
