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

/// Returns the localized message to show when checking for or answering an auth attempt fails.
///
/// Same rule as [ezkeyEnrollmentErrorMessage]: the exception type and problem kind decide, never the
/// server texts.
String ezkeyAttemptErrorMessage(Object error) => switch (error) {
  EzkeyRespondOutcomeUnknownException() => translations.ezkey.attempt.uncertain,
  EzkeyApiException(isAttemptNoLongerActionable: true) => translations.ezkey.attempt.noLongerActive,
  EzkeyApiException(kind: .rateLimited) => translations.ezkey.error.rateLimited,
  EzkeyApiException() => translations.ezkey.error.server,
  EzkeyNetworkException() => translations.ezkey.error.network,
  EzkeyIntegrityException() => translations.ezkey.attempt.integrity,
  EzkeyLocalStateException() => translations.ezkey.error.keyStore,
  _ => translations.ezkey.error.server,
};

/// Returns the localized message for the signed server [result] of a decision.
String ezkeyAttemptResultMessage(AuthAttemptResult result) => switch (result) {
  .approved => translations.ezkey.attempt.result.approved,
  .denied => translations.ezkey.attempt.result.denied,
  .failed => translations.ezkey.attempt.result.failed,
  .expired => translations.ezkey.attempt.result.expired,
};

/// Returns where the device key of an enrollment lives, as shown on its tile.
String ezkeyStorageTierLabel(DevicePrivateKeyStorageTier tier) => switch (tier) {
  .strong => translations.ezkey.page.tier.strong,
  .standard => translations.ezkey.page.tier.standard,
  .none => translations.ezkey.page.tier.none,
};
