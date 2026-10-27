import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_authenticator/ezkey/providers.dart';

/// The invitation QR code content (JSON or `id|token`), from the lab script.
const String _enrollmentCode = String.fromEnvironment('EZKEY_LAB_ENROLLMENT_CODE');

/// The 6-digit enrollment code of the same invitation.
const String _enrollmentChallenge = String.fromEnvironment('EZKEY_LAB_ENROLLMENT_CHALLENGE');

/// The Auth API as seen from the device (`10.0.2.2` is the emulator's host loopback).
const String _authApiBaseUrl = String.fromEnvironment('EZKEY_LAB_AUTH_URL', defaultValue: 'http://10.0.2.2:8080');

/// Enrolls and approves one auth attempt against a live local EzKey stack, through the app's
/// providers and the real Android Keystore. Driven by `scripts/ezkey-lab.sh`, which creates the
/// invitation and, once the device is enrolled, the auth attempt; skipped without an invitation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('enrolls with a live stack and approves an auth attempt', () async {
    ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    EzkeyAuthenticator authenticator = await container.read(ezkeyAuthenticatorProvider.future);

    EzkeyBoundEnrollment bound = await authenticator.bindEnrollment(EnrollmentCode.parse(_enrollmentCode), authApiBaseUrlOverride: _authApiBaseUrl);
    EzkeyEnrollment enrollment = await container.read(ezkeyEnrollmentsProvider.notifier).complete(bound, parseChallengeCode(_enrollmentChallenge));
    try {
      expect(await container.read(ezkeyEnrollmentsProvider.future), contains(predicate<EzkeyEnrollment>((e) => e.localId == enrollment.localId)));
      // ignore: avoid_print
      print('EZKEY_LAB enrolled id=${enrollment.enrollmentId} integration=${enrollment.integrationName} tier=${enrollment.devicePrivateKeyStorageTier.name}');

      PendingAuthAttempt? attempt = await authenticator.pollPending(enrollment, timeout: const Duration(seconds: 90));
      expect(attempt, isNotNull, reason: 'no auth attempt arrived');
      // ignore: avoid_print
      print('EZKEY_LAB pending attempt=${attempt!.authAttemptId} title=${attempt.contextTitle}');

      AuthAttemptOutcome outcome = await authenticator.approve(enrollment, attempt);
      expect(outcome.result, AuthAttemptResult.approved);
      expect(attempt.canDecide, isFalse);
    } finally {
      await container.read(ezkeyEnrollmentsProvider.notifier).forget(enrollment);
    }
  }, skip: _enrollmentCode.isEmpty ? 'needs a lab invitation (scripts/ezkey-lab.sh)' : false);
}
