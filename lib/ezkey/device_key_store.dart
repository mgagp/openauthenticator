import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter/services.dart';

/// Prefix of every EzKey device key alias created by this app (see [ezkeyDeviceKeyAlias]).
const String ezkeyDeviceKeyAliasPrefix = 'ezkey-device-';

/// Builds a fresh, unguessable device key alias for [enrollmentId].
///
/// Pass it as `keyAliasFactory` to [EzkeyAuthenticator] so that the app owns the alias format that
/// orphan cleanup relies on ([ezkeyDeviceKeyAliasPrefix]).
String ezkeyDeviceKeyAlias(int enrollmentId) => '$ezkeyDeviceKeyAliasPrefix$enrollmentId-${base64UrlEncodeBytes(generateSecureRandomBytes(9))}';

/// [EzkeyDeviceKeyStore] on the Android Keystore through the `ezkey_keystore` plugin
/// (docs/adr/0002-ezkey-key-and-secret-storage.md).
///
/// Platform failures become [EzkeyLocalStateException]s, so the SDK treats them as local problems:
/// nothing is sent, and a missing key leads to "remove and re-enroll".
class AndroidEzkeyDeviceKeyStore implements EzkeyDeviceKeyStore {
  /// Creates a new Android device key store.
  AndroidEzkeyDeviceKeyStore({
    this.keystore = const EzkeyKeystore(),
  });

  /// The platform keystore client.
  final EzkeyKeystore keystore;

  /// The tier of the most recently generated key.
  DevicePrivateKeyStorageTier _lastGeneratedTier = DevicePrivateKeyStorageTier.standard;

  /// The tier of the most recently generated key: `strong` (StrongBox) or `standard` (TEE).
  ///
  /// The SDK reads it right after [generateKeyPair] during enrollment, so it describes the key
  /// being enrolled. It is per store rather than per key because that is the SDK's interface.
  @override
  DevicePrivateKeyStorageTier get storageTier => _lastGeneratedTier;

  @override
  Future<String> generateKeyPair(String alias) => _guard(() async {
    EzkeyGeneratedKey key = await keystore.generateKeyPair(alias);
    _lastGeneratedTier = key.strongBox ? DevicePrivateKeyStorageTier.strong : DevicePrivateKeyStorageTier.standard;
    return key.publicKey;
  });

  @override
  Future<String> sign(String alias, String payload) => _guard(() => keystore.sign(alias, payload));

  @override
  Future<String?> publicKey(String alias) => _guard(() => keystore.publicKey(alias));

  @override
  Future<void> deleteKeyPair(String alias) => _guard(() => keystore.deleteKeyPair(alias));

  /// Lists the device key aliases created by this app.
  Future<List<String>> deviceKeyAliases() => _guard(() => keystore.aliases(prefix: ezkeyDeviceKeyAliasPrefix));

  /// Runs [action], turning platform failures into [EzkeyLocalStateException]s.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (ex) {
      throw EzkeyLocalStateException('Device key store failed (${ex.code})');
    }
  }
}
