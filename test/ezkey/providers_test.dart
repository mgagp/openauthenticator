import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/providers.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ezkeyUrlPolicyFor', () {
    test('release and profile builds accept HTTPS only', () {
      EzkeyUrlPolicy policy = ezkeyUrlPolicyFor(debug: false);

      expect(policy.normalize('https://auth.example.com'), 'https://auth.example.com');
      expect(policy.normalize('http://10.0.2.2:8080'), isNull);
      expect(policy.normalize('http://localhost:8080'), isNull);
      expect(policy.normalize('http://auth.example.com'), isNull);
    });

    test('debug builds also accept plain HTTP to the development hosts, and nowhere else', () {
      EzkeyUrlPolicy policy = ezkeyUrlPolicyFor(debug: true);

      expect(policy.normalize('https://auth.example.com'), 'https://auth.example.com');
      expect(policy.normalize('http://10.0.2.2:8080'), 'http://10.0.2.2:8080');
      expect(policy.normalize('http://localhost:8080'), 'http://localhost:8080');
      expect(policy.normalize('http://auth.example.com'), isNull);
    });
  });

  test('the policy of this build is the debug one when tests run, in debug mode', () {
    ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(ezkeyUrlPolicyProvider).normalize('http://10.0.2.2:8080'), isNotNull);
  });

  test('the authenticator uses the URL policy of this build', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, (call) async => <String>[]);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, null));
    ProviderContainer container = ProviderContainer(
      overrides: [
        ezkeyEnrollmentStoreProvider.overrideWith((ref) async => SecureEzkeyEnrollmentStore(InMemorySecureValues())),
        ezkeyUrlPolicyProvider.overrideWithValue(EzkeyUrlPolicy.httpsOnly),
      ],
    );
    addTearDown(container.dispose);

    EzkeyAuthenticator authenticator = await container.read(ezkeyAuthenticatorProvider.future);

    expect(authenticator.urlPolicy, same(EzkeyUrlPolicy.httpsOnly));
  });
}
