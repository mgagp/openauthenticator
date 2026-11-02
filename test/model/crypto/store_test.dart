import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';

/// The password the fixed vectors were made with.
const String _password = 'correct horse';

/// A secret encrypted on 2026-11-02 with [_password] and [_fixedSalt]. Users' data is encrypted the same
/// way, so it must keep decrypting.
const String _fixedCiphertext = 'cMA1wJXKZWoG809Gut2wpNYf0+o/QSVfUFulEOQjo34ECHlh6Oifh66VTjI=';

/// The salt of the fixed vectors: the bytes 0 to 31.
final Salt _fixedSalt = Salt.fromRawValue(value: Uint8List.fromList(List<int>.generate(32, (i) => i)));

void main() {
  group('CryptoStore', () {
    late CryptoStore store;

    setUpAll(() => store = CryptoStore.fromPassword(_password, _fixedSalt));

    test('decrypts what it encrypts', () {
      Uint8List encrypted = store.encrypt('JBSWY3DPEHPK3PXP')!;

      expect(store.decrypt(encrypted), 'JBSWY3DPEHPK3PXP');
      expect(store.canDecrypt(encrypted), isTrue);
    });

    test('still decrypts data encrypted by an earlier version', () {
      String? decrypted = store.decrypt(base64.decode(_fixedCiphertext));

      expect(decrypted, 'JBSWY3DPEHPK3PXP');
    });

    test('uses a fresh initialization vector each time, so the same text encrypts differently', () {
      Uint8List first = store.encrypt('JBSWY3DPEHPK3PXP')!;
      Uint8List second = store.encrypt('JBSWY3DPEHPK3PXP')!;

      expect(first, isNot(second));
      expect(first.sublist(0, 12), isNot(second.sublist(0, 12)));
    });

    test('returns null with the wrong password', () {
      CryptoStore other = CryptoStore.fromPassword('wrong password', _fixedSalt);

      Uint8List encrypted = store.encrypt('JBSWY3DPEHPK3PXP')!;

      expect(other.decrypt(encrypted), isNull);
      expect(other.canDecrypt(encrypted), isFalse);
    });

    test('returns null when the data was tampered with or truncated', () {
      Uint8List encrypted = store.encrypt('JBSWY3DPEHPK3PXP')!;
      Uint8List tampered = Uint8List.fromList(encrypted)..[encrypted.length - 1] ^= 1;
      Uint8List tamperedVector = Uint8List.fromList(encrypted)..[0] ^= 1;

      expect(store.decrypt(tampered), isNull);
      expect(store.decrypt(tamperedVector), isNull);
      expect(store.decrypt(encrypted.sublist(0, encrypted.length - 4)), isNull);
      expect(store.decrypt(Uint8List(5)), isNull);
    });

    test('checks a password against its key', () {
      expect(store.checkPasswordValidity(_password), isTrue);
      expect(store.checkPasswordValidity('wrong password'), isFalse);
    });

    test('equals another store with the same key and salt', () {
      expect(CryptoStore.fromPassword(_password, _fixedSalt), store);
      expect(CryptoStore.fromPassword(_password, Salt.generate()), isNot(store));
    });
  });
}
