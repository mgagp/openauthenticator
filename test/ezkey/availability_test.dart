import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/utils/platform.dart';

void main() {
  group('ezkeyAvailable', () {
    late Platform platform;

    setUp(() => platform = currentPlatform);

    tearDown(() => currentPlatform = platform);

    test('is true on Android', () {
      currentPlatform = .android;

      expect(ezkeyAvailable, isTrue);
    });

    test('is false on every platform without a checked key store yet', () {
      for (Platform other in Platform.values.where((value) => value != .android)) {
        currentPlatform = other;

        expect(ezkeyAvailable, isFalse, reason: other.name);
      }
    });
  });
}
