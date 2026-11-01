import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/app_links/app_purchases.dart';
import 'package:open_authenticator/model/app_links/openauthenticator.dart';

// Characterization tests (#55): they pin upstream's `openauthenticator://purchases/` links as they are
// today, before EzKey links are routed next to them (harmonization H8). Only the success form shows a
// toast; any other purchases link is consumed silently.

/// Wraps [text] as a purchases link.
AppPurchasesLink purchases(String text) => AppPurchasesLink(OpenAuthenticatorAppLink(Uri.parse(text)));

void main() {
  group('AppPurchasesLink', () {
    test('accepts any path under the purchases host', () {
      expect(purchases('openauthenticator://purchases').isValid, isTrue);
      expect(purchases('openauthenticator://purchases/anything').isValid, isTrue);
    });

    test('rejects another host', () {
      expect(purchases('openauthenticator://auth/provider/google').isValid, isFalse);
    });
  });

  group('AppPurchasesSuccessLink', () {
    test('accepts exactly /success, with or without a query', () {
      expect(AppPurchasesSuccessLink(purchases('openauthenticator://purchases/success')).isValid, isTrue);
      expect(AppPurchasesSuccessLink(purchases('openauthenticator://purchases/success?x=1')).isValid, isTrue);
    });

    test('rejects any other path, including a trailing slash', () {
      expect(AppPurchasesSuccessLink(purchases('openauthenticator://purchases')).isValid, isFalse);
      expect(AppPurchasesSuccessLink(purchases('openauthenticator://purchases/success/')).isValid, isFalse);
      expect(AppPurchasesSuccessLink(purchases('openauthenticator://purchases/cancel')).isValid, isFalse);
    });
  });
}
