import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeEzkeyDeviceKeyStore', () {
    late List<MethodCall> calls;
    late Object? Function(MethodCall call) answer;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, (call) async {
        calls.add(call);
        return answer(call);
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(EzkeyKeystore.channel, null);
    });

    test('reports the tier of the last generated key', () async {
      NativeEzkeyDeviceKeyStore store = NativeEzkeyDeviceKeyStore();
      answer = (call) => {'publicKey': 'SPKI-strong', 'tier': 'strong'};
      expect(await store.generateKeyPair('ezkey-device-1-a'), 'SPKI-strong');
      expect(store.storageTier, DevicePrivateKeyStorageTier.strong);

      answer = (call) => {'publicKey': 'SPKI-tee', 'tier': 'standard'};
      expect(await store.generateKeyPair('ezkey-device-2-b'), 'SPKI-tee');
      expect(store.storageTier, DevicePrivateKeyStorageTier.standard);
      expect(calls.map((call) => call.arguments), [
        {'alias': 'ezkey-device-1-a'},
        {'alias': 'ezkey-device-2-b'},
      ]);
    });

    test('passes alias and payload through to the platform', () async {
      NativeEzkeyDeviceKeyStore store = NativeEzkeyDeviceKeyStore();
      answer = (call) => switch (call.method) {
        'sign' => 'DER-signature',
        'aliases' => ['ezkey-device-1-a'],
        _ => null,
      };
      expect(await store.sign('ezkey-device-1-a', 'token|true'), 'DER-signature');
      expect(await store.publicKey('missing'), isNull);
      await store.deleteKeyPair('ezkey-device-1-a');
      expect(await store.deviceKeyAliases(), ['ezkey-device-1-a']);
      expect(calls.map((call) => call.method), ['sign', 'publicKey', 'deleteKeyPair', 'aliases']);
      expect(calls.map((call) => call.arguments), [
        {'alias': 'ezkey-device-1-a', 'payload': 'token|true'},
        {'alias': 'missing'},
        {'alias': 'ezkey-device-1-a'},
        {'prefix': '${ezkeyDeviceKeyAliasPrefix}debug-'},
      ]);
    });

    test('platform failures become local-state errors without leaking the payload', () async {
      NativeEzkeyDeviceKeyStore store = NativeEzkeyDeviceKeyStore();
      answer = (call) => throw PlatformException(code: 'key_not_found', message: 'No key for alias ezkey-device-1-a');
      await expectLater(
        store.sign('ezkey-device-1-a', 'secret-payload'),
        throwsA(isA<EzkeyLocalStateException>().having((e) => e.message, 'message', allOf(contains('key_not_found'), isNot(contains('secret-payload'))))),
      );
    });
  });

  test('device key aliases carry the app prefix and the namespace, and are unguessable', () {
    String first = ezkeyDeviceKeyAlias(42, namespace: 'main');
    String second = ezkeyDeviceKeyAlias(42, namespace: 'main');
    expect(first, startsWith('${ezkeyDeviceKeyAliasPrefix}main-42-'));
    expect(first, isNot(second));
  });

  test('debug builds use their own namespace, like upstream secure storage', () {
    expect(ezkeyDeviceKeyNamespace, 'debug');
    expect(NativeEzkeyDeviceKeyStore().namespace, 'debug');
  });
}
