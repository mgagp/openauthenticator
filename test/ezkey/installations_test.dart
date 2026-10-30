import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/installations.dart';

import 'support.dart';

void main() {
  group('EzkeyInstallation', () {
    test('group() puts enrollments of the same Auth API together, in order of first appearance', () {
      EzkeyEnrollment a1 = testEnrollment(1, authApiBaseUrl: 'https://a.example');
      EzkeyEnrollment b1 = testEnrollment(2, authApiBaseUrl: 'https://b.example');
      EzkeyEnrollment a2 = testEnrollment(3, authApiBaseUrl: 'https://a.example');

      List<EzkeyInstallation> installations = EzkeyInstallation.group([a1, b1, a2]);

      expect(installations.map((installation) => installation.authApiBaseUrl), ['https://a.example', 'https://b.example']);
      expect(installations.first.enrollments, [a1, a2]);
      expect(installations.last.enrollments, [b1]);
    });

    test('group() returns nothing for no enrollment', () {
      expect(EzkeyInstallation.group([]), isEmpty);
    });
  });
}
