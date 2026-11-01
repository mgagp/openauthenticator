import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/app_links/otpauth_totp.dart';
import 'package:open_authenticator/model/totp/algorithm.dart';

// Characterization tests (#55): they pin upstream's `otpauth://totp/` handling as it is today,
// before a unified scanner (harmonization H6) routes QR codes between TOTP and EzKey. The scanner and
// the link listener both accept a code when `Uri.tryParse(text)` is an [OtpAuthTotpLink.isValid].

/// Parses [text] the way the scan page does, or returns `null`.
OtpAuthTotpLink? scanned(String text) {
  Uri? uri = Uri.tryParse(text);
  return uri == null ? null : OtpAuthTotpLink(uri);
}

void main() {
  group('OtpAuthTotpLink.isValid', () {
    test('accepts an otpauth totp link with a secret', () {
      expect(scanned('otpauth://totp/Orbit:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Orbit')!.isValid, isTrue);
    });

    test('accepts scheme and host in any case', () {
      expect(scanned('OTPAUTH://TOTP/alice?secret=JBSWY3DPEHPK3PXP')!.isValid, isTrue);
    });

    test('accepts an empty secret: only the presence of the parameter is checked', () {
      expect(scanned('otpauth://totp/alice?secret=')!.isValid, isTrue);
    });

    test('rejects a link without a secret', () {
      expect(scanned('otpauth://totp/alice?issuer=Orbit')!.isValid, isFalse);
    });

    test('rejects hotp links', () {
      expect(scanned('otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=0')!.isValid, isFalse);
    });

    test('rejects other schemes and plain text', () {
      expect(scanned('https://totp/alice?secret=JBSWY3DPEHPK3PXP')!.isValid, isFalse);
      expect(scanned('JBSWY3DPEHPK3PXP')!.isValid, isFalse);
    });

    test('rejects an EzKey invitation (JSON), so the TOTP scanner turns it away today', () {
      OtpAuthTotpLink? link = scanned('{"enrollmentCode":"abc","authUrl":"https://ezkey.example"}');

      expect(link?.isValid ?? false, isFalse);
    });
  });

  group('OtpAuthTotpLink fields', () {
    test('reads the label from the path, decoded, without the leading slash', () {
      OtpAuthTotpLink link = scanned('otpauth://totp/Orbit%20Console:alice%40example.com?secret=S')!;

      expect(link.label, 'Orbit Console:alice@example.com');
    });

    test('keeps an "issuer:" prefix in the label and takes the issuer from the query only', () {
      OtpAuthTotpLink link = scanned('otpauth://totp/Orbit:alice?secret=S')!;

      expect(link.label, 'Orbit:alice');
      expect(link.issuer, isNull);
    });

    test('decodes "+" in the query as a space', () {
      expect(scanned('otpauth://totp/alice?secret=S&issuer=Big+Corp')!.issuer, 'Big Corp');
    });

    test('keeps the secret exactly as written', () {
      expect(scanned('otpauth://totp/alice?secret=jbsw y3dp')!.encodedSecret, 'jbsw y3dp');
    });

    test('reads the algorithm in any case, and an unknown one as null', () {
      expect(scanned('otpauth://totp/a?secret=S&algorithm=SHA256')!.algorithm, Algorithm.sha256);
      expect(scanned('otpauth://totp/a?secret=S&algorithm=sha512')!.algorithm, Algorithm.sha512);
      expect(scanned('otpauth://totp/a?secret=S&algorithm=md5')!.algorithm, isNull);
      expect(scanned('otpauth://totp/a?secret=S')!.algorithm, isNull);
    });

    test('reads digits and period as integers, and anything else as null', () {
      OtpAuthTotpLink link = scanned('otpauth://totp/a?secret=S&digits=8&period=60')!;

      expect(link.digits, 8);
      expect(link.validity, const Duration(seconds: 60));
      expect(scanned('otpauth://totp/a?secret=S&digits=eight&period=1m')!.digits, isNull);
      expect(scanned('otpauth://totp/a?secret=S&digits=eight&period=1m')!.validity, isNull);
      expect(scanned('otpauth://totp/a?secret=S')!.validity, isNull);
    });
  });

  group('OtpAuthTotpLink.build', () {
    test('builds a link that reads back to the same fields', () {
      OtpAuthTotpLink link = OtpAuthTotpLink.build(
        secret: 'JBSWY3DPEHPK3PXP',
        label: 'Orbit Console:alice@example.com',
        issuer: 'Orbit & Co',
        algorithm: Algorithm.sha256,
        digits: 8,
        validity: const Duration(seconds: 60),
      );

      OtpAuthTotpLink readBack = scanned(link.toString())!;

      expect(readBack.isValid, isTrue);
      expect(readBack.encodedSecret, 'JBSWY3DPEHPK3PXP');
      expect(readBack.label, 'Orbit Console:alice@example.com');
      expect(readBack.issuer, 'Orbit & Co');
      expect(readBack.algorithm, Algorithm.sha256);
      expect(readBack.digits, 8);
      expect(readBack.validity, const Duration(seconds: 60));
    });

    test('writes the algorithm in lower case and leaves out what is not given', () {
      expect(OtpAuthTotpLink.build(secret: 'S', label: 'a', algorithm: Algorithm.sha1).toString(), 'otpauth://totp/a?secret=S&algorithm=sha1');
    });
  });
}
