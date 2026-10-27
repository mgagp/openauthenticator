import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/orphan_keys.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deletes device keys without a readable record and keeps the others', () async {
    Set<String> keystoreAliases = {'ezkey-device-1-a', 'ezkey-device-2-b', 'ezkey-device-3-c'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, (call) async {
      switch (call.method) {
        case 'aliases':
          return keystoreAliases.toList();
        case 'deleteKeyPair':
          keystoreAliases.remove((call.arguments as Map)['alias']);
          return null;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, null));

    InMemorySecureValues values = InMemorySecureValues();
    SecureEzkeyEnrollmentStore store = SecureEzkeyEnrollmentStore(values);
    await store.save(testEnrollment(1, deviceKeyAlias: 'ezkey-device-1-a'));
    values.values['${SecureEzkeyEnrollmentStore.keyPrefix}http://localhost:8080#3'] = '{broken';

    List<String> deleted = await deleteOrphanEzkeyDeviceKeys(keyStore: AndroidEzkeyDeviceKeyStore(), enrollmentStore: store);

    expect(deleted, unorderedEquals(['ezkey-device-2-b', 'ezkey-device-3-c']));
    expect(keystoreAliases, {'ezkey-device-1-a'});
  });
}
