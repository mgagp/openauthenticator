import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';

/// Runs the EzKey key store against the real Android Keystore (emulator or device):
/// `scripts/with-env.sh flutter test integration_test/ezkey/keystore_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('generates a P-256 key whose signatures verify and normalize to low-S', () async {
    AndroidEzkeyDeviceKeyStore store = AndroidEzkeyDeviceKeyStore();
    String alias = ezkeyDeviceKeyAlias(1);
    try {
      String spki = await store.generateKeyPair(alias);
      expect(store.storageTier, isNot(DevicePrivateKeyStorageTier.none));
      expect(await store.publicKey(alias), spki);
      expect(await store.deviceKeyAliases(), contains(alias));

      // About half of raw Keystore signatures are high-S: sign enough payloads to see both forms.
      int highS = 0;
      for (int i = 0; i < 16; i++) {
        String payload = 'proof-token-$i|true';
        String signature = await store.sign(alias, payload);
        expect(verifyEcdsaSha256(ecPublicKeyFromSpkiBase64(spki), payload, signature), isTrue);
        String normalized = normalizeEcdsaDerSignatureLowS(signature);
        expect(isLowSEcdsaDerSignature(normalized), isTrue);
        expect(verifyEcdsaSha256(ecPublicKeyFromSpkiBase64(spki), payload, normalized), isTrue);
        if (!isLowSEcdsaDerSignature(signature)) {
          highS++;
        }
      }
      printOnFailure('tier=${store.storageTier.name} highS=$highS/16');
      // ignore: avoid_print
      print('EZKEY_KEYSTORE tier=${store.storageTier.name} highS=$highS/16');
    } finally {
      await store.deleteKeyPair(alias);
    }
    expect(await store.publicKey(alias), isNull);
    expect(await store.deviceKeyAliases(), isNot(contains(alias)));
  });

  test('signing with a missing key is a local-state error', () async {
    AndroidEzkeyDeviceKeyStore store = AndroidEzkeyDeviceKeyStore();
    await expectLater(store.sign('${ezkeyDeviceKeyAliasPrefix}missing', 'payload'), throwsA(isA<EzkeyLocalStateException>()));
  });
}
