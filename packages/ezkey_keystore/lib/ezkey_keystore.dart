/// Hardware-protected EC P-256 signing keys for EzKey device keys, through the `org.ezkey.keystore`
/// platform channel.
///
/// The channel is the cross-platform contract (docs/adr/0004-ezkey-multi-platform-posture.md): every
/// platform implementation answers the same methods, arguments, results and error codes, so this
/// client serves them all. Implemented today on Android (Android Keystore: StrongBox first, then the
/// TEE).
///
/// Keys are non-exportable and sign-only. Only aliases, strings to sign, signatures and public keys
/// cross the channel.
///
/// Failures are [PlatformException]s with one of these codes:
/// * `key_not_found`: no key for the alias;
/// * `invalid_arguments`: a required argument is missing;
/// * `keystore_error`: any other key store failure (message is the error type only, never key
///   material or payloads).
library;

import 'package:flutter/services.dart';

/// Where a generated key lives, in platform-neutral terms. On the channel: `strong` or `standard`.
enum EzkeyKeyTier {
  /// A discrete secure element (Android StrongBox).
  strong,

  /// The platform's main hardware key store (Android TEE; Apple Secure Enclave; a TPM).
  standard,
}

/// Result of [EzkeyKeystore.generateKeyPair].
class EzkeyGeneratedKey {
  /// Creates a new generated key description.
  const EzkeyGeneratedKey({
    required this.publicKey,
    required this.tier,
  });

  /// SPKI DER public key, standard Base64 with padding.
  final String publicKey;

  /// Where the key lives.
  final EzkeyKeyTier tier;
}

/// Client of the `org.ezkey.keystore` platform channel.
class EzkeyKeystore {
  /// Creates a new keystore client.
  const EzkeyKeystore();

  /// The platform channel.
  static const MethodChannel channel = MethodChannel('org.ezkey.keystore');

  /// Generates a new key pair under [alias], in the strongest tier the device offers.
  Future<EzkeyGeneratedKey> generateKeyPair(String alias) async {
    Map<Object?, Object?> result = (await channel.invokeMapMethod<Object?, Object?>('generateKeyPair', {'alias': alias}))!;
    return EzkeyGeneratedKey(
      publicKey: result['publicKey'] as String,
      tier: EzkeyKeyTier.values.byName(result['tier'] as String),
    );
  }

  /// Signs the UTF-8 bytes of [payload] with ECDSA-SHA256; returns ASN.1 DER, standard Base64.
  ///
  /// The signature may be high-S; normalizing it is the caller's job (`ezkey_dart` does it).
  Future<String> sign(String alias, String payload) async => (await channel.invokeMethod<String>('sign', {'alias': alias, 'payload': payload}))!;

  /// Returns the SPKI DER public key of [alias] (standard Base64), or `null` when it does not exist.
  Future<String?> publicKey(String alias) => channel.invokeMethod<String>('publicKey', {'alias': alias});

  /// Deletes the key pair of [alias] (no-op when it does not exist).
  Future<void> deleteKeyPair(String alias) => channel.invokeMethod<void>('deleteKeyPair', {'alias': alias});

  /// Lists the Keystore aliases that start with [prefix].
  Future<List<String>> aliases({String prefix = ''}) async => (await channel.invokeListMethod<String>('aliases', {'prefix': prefix})) ?? const [];
}
