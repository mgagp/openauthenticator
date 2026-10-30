import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';

/// In-memory [EzkeySecureValues] for tests.
class InMemorySecureValues implements EzkeySecureValues {
  /// The stored values.
  final Map<String, String> values = {};

  @override
  Map<String, String> list() => Map.of(values);

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Returns a valid enrollment record for [enrollmentId], using [deviceKeyAlias].
EzkeyEnrollment testEnrollment(int enrollmentId, {String? deviceKeyAlias, String authApiBaseUrl = 'http://localhost:8080', String integrationName = 'Orbit Console'}) => EzkeyEnrollment.fromJson({
  'schemaVersion': 1,
  'authApiBaseUrl': authApiBaseUrl,
  'enrollmentId': enrollmentId,
  'enrollmentProofToken': 'proof-token-$enrollmentId',
  'integrationPublicKey': 'o_g1NmS1Gm95e2Ftiq9e2UG31cZtE-sJYjn486I4g_o',
  'integrationKeyAlgorithm': 'ed25519',
  'deviceKeyAlias': deviceKeyAlias ?? 'ezkey-device-$enrollmentId-test',
  'devicePublicKey': 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE',
  'devicePrivateKeyStorageTier': 'STRONG',
  'enrolledAt': '2026-10-27T12:00:00.000Z',
  'integrationName': integrationName,
  'integrationDescription': null,
  'enrollmentName': 'Alice Chen',
  'tenantId': 1,
  'tenantName': 'Ezkey System',
  'tenantDescription': null,
  'isSystemIntegration': false,
  'adminType': null,
});
