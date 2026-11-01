import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/app_links/app_auth.dart';
import 'package:open_authenticator/model/app_links/app_purchases.dart';
import 'package:open_authenticator/model/app_links/openauthenticator.dart';

// Characterization tests (#55): they pin upstream's `openauthenticator://` handling as it is today,
// before EzKey links are routed (harmonization H8). The app routes a link to its handlers only when it
// is an [OpenAuthenticatorAppLink.isValid] (or an `otpauth://totp/` link).

void main() {
  group('OpenAuthenticatorAppLink.isValid', () {
    test('accepts any openauthenticator link, whatever its host and path', () {
      expect(OpenAuthenticatorAppLink(Uri.parse('openauthenticator://auth/provider/google')).isValid, isTrue);
      expect(OpenAuthenticatorAppLink(Uri.parse('openauthenticator://anything/at/all?x=1')).isValid, isTrue);
      expect(OpenAuthenticatorAppLink(Uri.parse('openauthenticator:')).isValid, isTrue);
    });

    test('accepts the scheme in any case, since Uri lowercases it', () {
      expect(OpenAuthenticatorAppLink(Uri.parse('OpenAuthenticator://auth/provider/google')).isValid, isTrue);
    });

    test('rejects other schemes', () {
      expect(OpenAuthenticatorAppLink(Uri.parse('otpauth://totp/alice?secret=S')).isValid, isFalse);
      expect(OpenAuthenticatorAppLink(Uri.parse('https://openauthenticator.app/auth/provider/google')).isValid, isFalse);
      expect(OpenAuthenticatorAppLink(Uri.parse('ezkey://invitation?code=abc')).isValid, isFalse);
    });

    test('an unknown host is valid but matches no handler, so the app consumes it and does nothing', () {
      OpenAuthenticatorAppLink link = OpenAuthenticatorAppLink(Uri.parse('openauthenticator://ezkey/invitation?code=abc'));

      expect(link.isValid, isTrue);
      expect((link as AppAuthLink).isValid, isFalse);
      expect((link as AppPurchasesLink).isValid, isFalse);
    });
  });
}
