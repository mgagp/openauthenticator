import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_authenticator/ezkey/device_key_store.dart';
import 'package:open_authenticator/ezkey/orphan_keys.dart';

/// Runs the EzKey key store against the real platform key store (Android Keystore today; emulator or device):
/// `scripts/with-env.sh flutter test integration_test/ezkey/keystore_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('generates a P-256 key whose signatures verify and normalize to low-S', () async {
    final NativeEzkeyDeviceKeyStore store = NativeEzkeyDeviceKeyStore();
    final String alias = ezkeyDeviceKeyAlias(1);
    try {
      final String spki = await store.generateKeyPair(alias);
      // The reported tier is the one the platform reads back from the key now (#108): `none` on an
      // emulator, which has no secure hardware.
      expect(await store.keyTier(alias), store.storageTier);
      // The Windows software fallback is checked on a PC with a TPM by forcing it in a debug build:
      // EZKEY_KEYSTORE_FORCE_SOFTWARE=1 and --dart-define=EZKEY_KEYSTORE_EXPECTED_TIER=none.
      const String expectedTier = String.fromEnvironment('EZKEY_KEYSTORE_EXPECTED_TIER');
      if (expectedTier.isNotEmpty) {
        expect(store.storageTier.name, expectedTier);
      }
      expect(await store.publicKey(alias), spki);
      expect(await store.deviceKeyAliases(), contains(alias));

      // About half of raw Keystore signatures are high-S: sign enough payloads to see both forms.
      int highS = 0;
      for (int i = 0; i < 16; i++) {
        final String payload = 'proof-token-$i|true';
        final String signature = await store.sign(alias, payload);
        expect(verifyEcdsaSha256(ecPublicKeyFromSpkiBase64(spki), payload, signature), isTrue);
        final String normalized = normalizeEcdsaDerSignatureLowS(signature);
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
    expect(await store.keyTier(alias), isNull);
    expect(await store.deviceKeyAliases(), isNot(contains(alias)));
  });

  test('orphan cleanup leaves the keys of the other build type in the real Keystore (#41)', () async {
    final NativeEzkeyDeviceKeyStore debugStore = NativeEzkeyDeviceKeyStore(namespace: 'debug');
    final NativeEzkeyDeviceKeyStore mainStore = NativeEzkeyDeviceKeyStore(namespace: 'main');
    final String orphan = ezkeyDeviceKeyAlias(1, namespace: 'debug');
    final String otherBuild = ezkeyDeviceKeyAlias(2, namespace: 'main');
    try {
      await debugStore.generateKeyPair(orphan);
      await mainStore.generateKeyPair(otherBuild);

      // The debug build sees no record at all, as when its namespace is empty.
      final List<String> deleted = await deleteOrphanEzkeyDeviceKeys(keyStore: debugStore, enrollmentStore: InMemoryEnrollmentStore());

      expect(deleted, [orphan]);
      expect(await debugStore.publicKey(orphan), isNull);
      expect(await mainStore.publicKey(otherBuild), isNotNull);
    } finally {
      await debugStore.deleteKeyPair(orphan);
      await mainStore.deleteKeyPair(otherBuild);
    }
  });

  test('key generation leaves the app responsive (#134)', () async {
    final NativeEzkeyDeviceKeyStore store = NativeEzkeyDeviceKeyStore();
    final String alias = ezkeyDeviceKeyAlias(3);
    int ticks = 0;
    final Timer timer = Timer.periodic(const Duration(milliseconds: 10), (_) => ticks++);
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      await store.generateKeyPair(alias);
      stopwatch.stop();
    } finally {
      timer.cancel();
      await store.deleteKeyPair(alias);
    }

    // A key store call that blocks the platform thread also blocks Dart's timers, which then fire once at the
    // end. Running off that thread, the timer keeps ticking (at least one tick per 40 ms, a loose bound).
    // ignore: avoid_print
    print('EZKEY_KEYSTORE generate=${stopwatch.elapsedMilliseconds}ms ticks=$ticks');
    expect(ticks, greaterThanOrEqualTo(stopwatch.elapsedMilliseconds ~/ 40));
  });

  test('signing with a missing key is a local-state error', () async {
    final NativeEzkeyDeviceKeyStore store = NativeEzkeyDeviceKeyStore();
    await expectLater(store.sign('${ezkeyDeviceKeyAliasPrefix}missing', 'payload'), throwsA(isA<EzkeyLocalStateException>()));
  });
}
