import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/app_links/app_auth.dart';
import 'package:open_authenticator/model/app_links/openauthenticator.dart';

// Characterization tests (#55): they pin upstream's `openauthenticator://auth/` links as they are today,
// before EzKey links are routed next to them (harmonization H8). The app sends an [AppAuthLink] to the
// authentication provider named by [AppAuthLink.providerId], which then checks the finish or email-sent form.

/// Wraps [text] as an auth link.
AppAuthLink auth(String text) => AppAuthLink(OpenAuthenticatorAppLink(Uri.parse(text)));

void main() {
  group('AppAuthLink', () {
    test('accepts openauthenticator://auth/provider/<id> and reads the provider id', () {
      AppAuthLink link = auth('openauthenticator://auth/provider/google');

      expect(link.isValid, isTrue);
      expect(link.providerId, 'google');
    });

    test('accepts extra path segments after the provider id', () {
      AppAuthLink link = auth('openauthenticator://auth/provider/google/finish');

      expect(link.isValid, isTrue);
      expect(link.providerId, 'google');
    });

    test('accepts the host in any case, since Uri lowercases it', () {
      expect(auth('openauthenticator://AUTH/provider/google').isValid, isTrue);
    });

    test('rejects a link without a provider id segment, but takes an empty one', () {
      expect(auth('openauthenticator://auth/provider').isValid, isFalse);
      expect(auth('openauthenticator://auth/provider/').isValid, isTrue, reason: 'an empty trailing segment counts as a provider id');
    });

    test('rejects another first segment, compared case-sensitively', () {
      expect(auth('openauthenticator://auth/providers/google').isValid, isFalse);
      expect(auth('openauthenticator://auth/Provider/google').isValid, isFalse);
    });

    test('rejects another host or scheme', () {
      expect(auth('openauthenticator://purchases/provider/google').isValid, isFalse);
      expect(auth('https://auth/provider/google').isValid, isFalse);
    });
  });

  group('FinishAuthAppLink', () {
    test('accepts .../finish with an authorization code and reads both parameters', () {
      FinishAuthAppLink link = FinishAuthAppLink(auth('openauthenticator://auth/provider/google/finish?authorizationCode=abc&codeVerifier=xyz'));

      expect(link.isValid, isTrue);
      expect(link.providerId, 'google');
      expect(link.authorizationCode, 'abc');
      expect(link.codeVerifier, 'xyz');
    });

    test('has no code verifier when the parameter is missing', () {
      FinishAuthAppLink link = FinishAuthAppLink(auth('openauthenticator://auth/provider/google/finish?authorizationCode=abc'));

      expect(link.isValid, isTrue);
      expect(link.codeVerifier, isNull);
    });

    test('rejects a link without an authorization code', () {
      expect(FinishAuthAppLink(auth('openauthenticator://auth/provider/google/finish?codeVerifier=xyz')).isValid, isFalse);
    });

    test('rejects a link that does not end with finish', () {
      expect(FinishAuthAppLink(auth('openauthenticator://auth/provider/google?authorizationCode=abc')).isValid, isFalse);
      expect(FinishAuthAppLink(auth('openauthenticator://auth/provider/google/finish/?authorizationCode=abc')).isValid, isFalse);
    });
  });

  group('EmailSentAppLink', () {
    test('accepts /provider/email/sent with an email and reads every parameter', () {
      EmailSentAppLink link = EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent?email=alice%40example.com&cancelCode=k1&previously=true'));

      expect(link.isValid, isTrue);
      expect(link.email, 'alice@example.com');
      expect(link.cancelCode, 'k1');
      expect(link.previously, isTrue);
    });

    test('reads previously case-insensitively, and as false when missing or anything else', () {
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent?email=a&previously=TRUE')).previously, isTrue);
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent?email=a&previously=1')).previously, isFalse);
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent?email=a')).previously, isFalse);
    });

    test('has no cancel code when the parameter is missing', () {
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent?email=a')).cancelCode, isNull);
    });

    test('rejects a link without an email', () {
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent?cancelCode=k1')).isValid, isFalse);
    });

    test('rejects any other path, including a trailing slash', () {
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/email/sent/?email=a')).isValid, isFalse);
      expect(EmailSentAppLink(auth('openauthenticator://auth/provider/google/sent?email=a')).isValid, isFalse);
    });
  });
}
