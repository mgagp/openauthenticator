import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/core/crypto/salt.dart';

void main() {
  group('Salt', () {
    test('generates 256-bit salts that differ', () {
      final Salt first = Salt.generate();
      final Salt second = Salt.generate();

      expect(first.value, hasLength(32));
      expect(first, isNot(second));
    });

    test('survives a Base64 round trip', () {
      final Salt salt = Salt.generate();

      final Salt decoded = Salt.base64Decode(string: salt.toString());

      expect(decoded, salt);
    });
  });
}
