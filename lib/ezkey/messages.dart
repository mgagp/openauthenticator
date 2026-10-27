import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

/// Returns the localized message to show for an enrollment failure.
///
/// Branches on the exception type and problem kind only: server `title` / `detail` texts are never
/// shown (client behaviour contract §7).
String ezkeyEnrollmentErrorMessage(Object error) => switch (error) {
  EzkeyApiException(kind: .enrollmentAlreadyBound) => translations.ezkey.error.invitationAlreadyUsed,
  EzkeyApiException(kind: .enrollmentInvitationExpired) => translations.ezkey.error.invitationExpired,
  EzkeyApiException(kind: .enrollmentVerifyFailed) => translations.ezkey.error.wrongCode,
  EzkeyApiException(kind: .enrollmentBindingFailed || .enrollmentNotAvailable || .enrollmentIntegrationNotFound || .enrollmentStateConflict) => translations.ezkey.error.invitationRejected,
  EzkeyApiException(kind: .rateLimited) => translations.ezkey.error.rateLimited,
  EzkeyApiException() => translations.ezkey.error.server,
  EzkeyNetworkException() => translations.ezkey.error.network,
  EzkeyIntegrityException() => translations.ezkey.error.integrity,
  EzkeyLocalStateException() => translations.ezkey.error.keyStore,
  EzkeyValidationException() => translations.ezkey.error.invalidInvitation,
  _ => translations.ezkey.error.server,
};

/// Whether the invitation behind a failed enrollment step can no longer be used, so the flow has to
/// start over with a new invitation.
bool isEzkeyInvitationDead(Object error) => switch (error) {
  EzkeyApiException(retryable: false) => true,
  EzkeyIntegrityException() => true,
  _ => false,
};
