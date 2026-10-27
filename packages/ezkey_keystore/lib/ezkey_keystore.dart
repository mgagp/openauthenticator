/// Android Keystore EC P-256 signing keys for EzKey device keys.
///
/// Keys are non-exportable and sign-only; generation requests StrongBox first and falls back to the
/// TEE. Only aliases, strings to sign, signatures and public keys cross the platform channel.
///
/// Failures are [PlatformException]s with one of these codes:
/// * `key_not_found`: no key for the alias;
/// * `invalid_arguments`: a required argument is missing;
/// * `keystore_error`: any other Keystore failure (message is the exception class name only).
library;

import 'package:flutter/services.dart';

/// Result of [EzkeyKeystore.generateKeyPair].
class EzkeyGeneratedKey {
  /// Creates a new generated key description.
  const EzkeyGeneratedKey({
    required this.publicKey,
    required this.strongBox,
  });

  /// SPKI DER public key, standard Base64 with padding.
  final String publicKey;

  /// Whether the key lives in StrongBox (`false`: TEE).
  final bool strongBox;
}

/// Client of the `org.ezkey.keystore` platform channel (Android only).
class EzkeyKeystore {
  /// Creates a new keystore client.
  const EzkeyKeystore();

  /// The platform channel.
  static const MethodChannel channel = MethodChannel('org.ezkey.keystore');

  /// Generates a new key pair under [alias] (StrongBox first, then TEE).
  Future<EzkeyGeneratedKey> generateKeyPair(String alias) async {
    Map<Object?, Object?> result = (await channel.invokeMapMethod<Object?, Object?>('generateKeyPair', {'alias': alias}))!;
    return EzkeyGeneratedKey(
      publicKey: result['publicKey'] as String,
      strongBox: result['strongBox'] as bool,
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
