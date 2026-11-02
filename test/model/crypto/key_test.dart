import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/crypto/key.dart';

void main() {
  group('CryptoKey', () {
    test('equals another key with the same bytes only', () {
      CryptoKey key = CryptoKey.fromRawValue(value: Uint8List.fromList([1, 2, 3]));

      expect(key, CryptoKey.fromRawValue(value: Uint8List.fromList([1, 2, 3])));
      expect(key.hashCode, CryptoKey.fromRawValue(value: Uint8List.fromList([1, 2, 3])).hashCode);
      expect(key, isNot(CryptoKey.fromRawValue(value: Uint8List.fromList([1, 2, 4]))));
    });
  });
}
