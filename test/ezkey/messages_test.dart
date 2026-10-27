import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

/// An Auth API failure with the given problem [type] (under `https://ezkey.io/problems/auth/`).
EzkeyApiException apiError(int statusCode, String type) => EzkeyApiException(
  method: 'POST',
  path: '/api/v1/enrollments/verify',
  statusCode: statusCode,
  problem: EzkeyProblem(type: 'https://ezkey.io/problems/auth/$type', title: 'Server title', detail: 'Server detail'),
);

void main() {
  group('ezkeyEnrollmentErrorMessage', () {
    test('maps enrollment problem types to local copy', () {
      expect(ezkeyEnrollmentErrorMessage(apiError(409, 'enrollment-already-bound')), translations.ezkey.error.invitationAlreadyUsed);
      expect(ezkeyEnrollmentErrorMessage(apiError(410, 'enrollment-invitation-expired')), translations.ezkey.error.invitationExpired);
      expect(ezkeyEnrollmentErrorMessage(apiError(400, 'enrollment-verify-failed')), translations.ezkey.error.wrongCode);
      expect(ezkeyEnrollmentErrorMessage(apiError(400, 'enrollment-binding-failed')), translations.ezkey.error.invitationRejected);
    });

    test('never shows the server title or detail', () {
      String message = ezkeyEnrollmentErrorMessage(apiError(500, 'internal-error'));

      expect(message, translations.ezkey.error.server);
      expect(message, isNot(contains('Server')));
    });

    test('maps local failures by exception type', () {
      expect(ezkeyEnrollmentErrorMessage(const EzkeyNetworkException('timeout')), translations.ezkey.error.network);
      expect(ezkeyEnrollmentErrorMessage(const EzkeyIntegrityException(EzkeyIntegrityCheck.verifySignature, 'bad signature')), translations.ezkey.error.integrity);
      expect(ezkeyEnrollmentErrorMessage(const EzkeyLocalStateException('keystore')), translations.ezkey.error.keyStore);
      expect(ezkeyEnrollmentErrorMessage(const EzkeyValidationException('bad code')), translations.ezkey.error.invalidInvitation);
    });
  });

  group('isEzkeyInvitationDead', () {
    test('a wrong code or a refused invitation ends the flow', () {
      expect(isEzkeyInvitationDead(apiError(400, 'enrollment-verify-failed')), isTrue);
      expect(isEzkeyInvitationDead(apiError(409, 'enrollment-already-bound')), isTrue);
      expect(isEzkeyInvitationDead(const EzkeyIntegrityException(EzkeyIntegrityCheck.verifyNotActive, 'not active')), isTrue);
    });

    test('network failures and rate limits let the user retry', () {
      expect(isEzkeyInvitationDead(const EzkeyNetworkException('timeout')), isFalse);
      expect(isEzkeyInvitationDead(EzkeyApiException(method: 'POST', path: '/api/v1/enrollments/verify', statusCode: 429)), isFalse);
    });
  });
}
