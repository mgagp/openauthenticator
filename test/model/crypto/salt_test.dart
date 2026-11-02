import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/model/crypto/salt.dart';

void main() {
  group('Salt', () {
    test('generates 256-bit salts that differ', () {
      Salt first = Salt.generate();
      Salt second = Salt.generate();

      expect(first.value, hasLength(32));
      expect(first, isNot(second));
    });

    test('survives a Base64 round trip', () {
      Salt salt = Salt.generate();

      Salt decoded = Salt.base64Decode(string: salt.toString());

      expect(decoded, salt);
    });
  });
}
