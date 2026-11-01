import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/app_links/otpauth_totp.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/model/totp/algorithm.dart';
import 'package:open_authenticator/model/totp/decrypted.dart';

// Characterization tests (#55): how a scanned or opened `otpauth://` link becomes a TOTP today
// (`DecryptedTotp.fromUri`, used by the TOTP page), before a unified scanner (H6) changes the routing.

void main() {
  late CryptoStore cryptoStore;

  setUpAll(() => cryptoStore = CryptoStore.fromPassword('password', Salt.generate()));

  group('DecryptedTotp.fromUri', () {
    test('creates a TOTP with every field of the link', () {
      OtpAuthTotpLink link = OtpAuthTotpLink(Uri.parse('otpauth://totp/Orbit:alice?secret=JBSWY3DPEHPK3PXP&issuer=Orbit&algorithm=SHA256&digits=8&period=60'));

      DecryptedTotp? totp = DecryptedTotp.fromUri(link, cryptoStore);

      expect(totp, isNotNull);
      expect(totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(totp.label, 'Orbit:alice');
      expect(totp.issuer, 'Orbit');
      expect(totp.algorithm, Algorithm.sha256);
      expect(totp.digits, 8);
      expect(totp.validity, const Duration(seconds: 60));
    });

    test('returns null for a link that is not a valid TOTP link', () {
      OtpAuthTotpLink link = OtpAuthTotpLink(Uri.parse('otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP'));

      expect(DecryptedTotp.fromUri(link, cryptoStore), isNull);
    });

    test('returns null without a crypto store', () {
      OtpAuthTotpLink link = OtpAuthTotpLink(Uri.parse('otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP'));

      expect(DecryptedTotp.fromUri(link, null), isNull);
    });

    test('gives back a link with the same fields through uri', () {
      OtpAuthTotpLink link = OtpAuthTotpLink(Uri.parse('otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&issuer=Orbit&digits=8'));

      OtpAuthTotpLink readBack = DecryptedTotp.fromUri(link, cryptoStore)!.uri;

      expect(readBack.encodedSecret, 'JBSWY3DPEHPK3PXP');
      expect(readBack.label, 'alice');
      expect(readBack.issuer, 'Orbit');
      expect(readBack.digits, 8);
    });
  });
}
