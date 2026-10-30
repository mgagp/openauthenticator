import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/orphan_keys.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deletes the own namespace keys without a readable record, and leaves every other key', () async {
    Set<String> keystoreAliases = {
      'ezkey-device-debug-1-a', // referenced
      'ezkey-device-debug-2-b', // orphan
      'ezkey-device-debug-3-c', // its record is unreadable
      'ezkey-device-main-4-d', // the other build type's key: its record lives in the other namespace
      'ezkey-device-5-e', // made before namespaces (#41)
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, (call) async {
      switch (call.method) {
        case 'aliases':
          String prefix = (call.arguments as Map)['prefix'] as String;
          return keystoreAliases.where((alias) => alias.startsWith(prefix)).toList();
        case 'deleteKeyPair':
          keystoreAliases.remove((call.arguments as Map)['alias']);
          return null;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, null));

    InMemorySecureValues values = InMemorySecureValues();
    SecureEzkeyEnrollmentStore store = SecureEzkeyEnrollmentStore(values);
    await store.save(testEnrollment(1, deviceKeyAlias: 'ezkey-device-debug-1-a'));
    values.values['${SecureEzkeyEnrollmentStore.keyPrefix}http://localhost:8080#3'] = '{broken';

    List<String> deleted = await deleteOrphanEzkeyDeviceKeys(
      keyStore: AndroidEzkeyDeviceKeyStore(namespace: 'debug'),
      enrollmentStore: store,
    );

    expect(deleted, unorderedEquals(['ezkey-device-debug-2-b', 'ezkey-device-debug-3-c']));
    expect(keystoreAliases, {'ezkey-device-debug-1-a', 'ezkey-device-main-4-d', 'ezkey-device-5-e'});
  });
}
