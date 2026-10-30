import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:ezkey_keystore/ezkey_keystore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Prefix of every EzKey device key alias created by this app (see [ezkeyDeviceKeyAlias]).
const String ezkeyDeviceKeyAliasPrefix = 'ezkey-device-';

/// The enrollment records' storage namespace of this build (#41).
///
/// Upstream's secure storage uses a separate namespace in debug builds
/// (`lib/model/secure_storage.dart`), so debug and profile / release builds see different
/// enrollment records, while the Android Keystore keys are shared by both. Each key is marked with
/// its namespace so that orphan cleanup never takes the other build's keys for orphans.
final String ezkeyDeviceKeyNamespace = kDebugMode ? 'debug' : 'main';

/// Builds a fresh, unguessable device key alias for [enrollmentId], marked with [namespace]:
/// `ezkey-device-<namespace>-<enrollmentId>-<random>`.
///
/// Pass it as `keyAliasFactory` to [EzkeyAuthenticator] so that the app owns the alias format that
/// orphan cleanup relies on ([ezkeyDeviceKeyAliasPrefix]). Aliases made before #41 have no
/// namespace (`ezkey-device-<enrollmentId>-<random>`).
String ezkeyDeviceKeyAlias(int enrollmentId, {String? namespace}) =>
    '$ezkeyDeviceKeyAliasPrefix${namespace ?? ezkeyDeviceKeyNamespace}-$enrollmentId-${base64UrlEncodeBytes(generateSecureRandomBytes(9))}';

/// [EzkeyDeviceKeyStore] on the Android Keystore through the `ezkey_keystore` plugin
/// (docs/adr/0002-ezkey-key-and-secret-storage.md).
///
/// Platform failures become [EzkeyLocalStateException]s, so the SDK treats them as local problems:
/// nothing is sent, and a missing key leads to "remove and re-enroll".
class AndroidEzkeyDeviceKeyStore implements EzkeyDeviceKeyStore {
  /// Creates a new Android device key store.
  AndroidEzkeyDeviceKeyStore({
    this.keystore = const EzkeyKeystore(),
    String? namespace,
  }) : namespace = namespace ?? ezkeyDeviceKeyNamespace;

  /// The platform keystore client.
  final EzkeyKeystore keystore;

  /// The storage namespace whose keys [deviceKeyAliases] lists.
  final String namespace;

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

  /// Lists the device key aliases this build created for its own [namespace]. The other build
  /// type's keys and the unmarked keys made before #41 are left out, so orphan cleanup never
  /// deletes them.
  Future<List<String>> deviceKeyAliases() => _guard(() => keystore.aliases(prefix: '$ezkeyDeviceKeyAliasPrefix$namespace-'));

  /// Runs [action], turning platform failures into [EzkeyLocalStateException]s.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (ex) {
      throw EzkeyLocalStateException('Device key store failed (${ex.code})');
    }
  }
}
