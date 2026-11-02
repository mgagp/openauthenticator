import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/crypto/derived_key.dart';
import 'package:open_authenticator/model/crypto/salt.dart';

/// The password of the fixed vector.
const String _password = 'correct horse';

/// The key Argon2 derived on 2026-11-02 from [_password] and [_fixedSalt] with the app's parameters. Every
/// user's key is derived the same way, so a change here would lock users out of their data.
const String _fixedDerivedKey = '19rjOLucn1i6qMRoJRI8xkkFlhmXXqik6m8uJTSQ+20=';

/// The salt of the fixed vector: the bytes 0 to 31.
final Salt _fixedSalt = Salt.fromRawValue(value: Uint8List.fromList(List<int>.generate(32, (i) => i)));

void main() {
  group('DerivedKey', () {
    test('derives the same key as before from the same password and salt', () {
      DerivedKey key = DerivedKey.fromPassword(_password, _fixedSalt);

      expect(key.toString(), _fixedDerivedKey);
    });

    test('derives a different key from another password or another salt', () {
      DerivedKey key = DerivedKey.fromPassword(_password, _fixedSalt);

      expect(DerivedKey.fromPassword('correct horse!', _fixedSalt), isNot(key));
      expect(DerivedKey.fromPassword(_password, Salt.generate()), isNot(key));
    });
  });
}
