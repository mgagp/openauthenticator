import 'dart:convert';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:simple_secure_storage/simple_secure_storage.dart';

/// The key-value operations the EzKey enrollment store needs from the app's secure storage.
abstract interface class EzkeySecureValues {
  /// Returns every stored key / value pair.
  Map<String, String> list();

  /// Returns the value of [key], or `null`.
  String? read(String key);

  /// Writes [value] under [key].
  Future<void> write(String key, String value);

  /// Deletes [key].
  Future<void> delete(String key);
}

/// [EzkeySecureValues] over the app's [CachedSimpleSecureStorage] (`secureStorageProvider`).
class CachedSecureValues implements EzkeySecureValues {
  /// Creates a new view of [storage].
  const CachedSecureValues(this.storage);

  /// The app's secure storage.
  final CachedSimpleSecureStorage storage;

  @override
  Map<String, String> list() => storage.list();

  @override
  String? read(String key) => storage.read(key);

  @override
  Future<void> write(String key, String value) => storage.write(key, value);

  @override
  Future<void> delete(String key) => storage.delete(key);
}

/// [EzkeyEnrollmentStore] on the app's secure storage (docs/adr/0002-ezkey-key-and-secret-storage.md).
///
/// One entry per enrollment, keyed `ezkey.enrollment.<localId>`, holding [EzkeyEnrollment.toJson].
/// Records contain the enrollment proof token (a bearer secret): never log them.
class SecureEzkeyEnrollmentStore implements EzkeyEnrollmentStore {
  /// Creates a new enrollment store over [values].
  const SecureEzkeyEnrollmentStore(this.values);

  /// Prefix of every enrollment entry in the secure storage.
  static const String keyPrefix = 'ezkey.enrollment.';

  /// The underlying secure storage.
  final EzkeySecureValues values;

  @override
  Future<void> save(EzkeyEnrollment enrollment) => values.write('$keyPrefix${enrollment.localId}', jsonEncode(enrollment.toJson()));

  /// Returns the record of [localId], or `null`. Throws [EzkeyLocalStateException] when it exists but
  /// cannot be read.
  @override
  Future<EzkeyEnrollment?> load(String localId) async {
    String? json = values.read('$keyPrefix$localId');
    return json == null ? null : _decode(json);
  }

  /// Returns the readable records. Unreadable ones are left out here and reported by
  /// [unreadableLocalIds], so the UI can show them as unusable instead of hiding them.
  @override
  Future<List<EzkeyEnrollment>> list() async {
    List<EzkeyEnrollment> result = [];
    for (String json in _entries().values) {
      try {
        result.add(_decode(json));
      } on EzkeyLocalStateException {
        // Reported by unreadableLocalIds().
      }
    }
    return result;
  }

  /// Returns the local ids of the records that exist but cannot be read.
  List<String> unreadableLocalIds() => [
    for (MapEntry<String, String> entry in _entries().entries)
      if (!_isReadable(entry.value)) entry.key.substring(keyPrefix.length),
  ];

  @override
  Future<void> delete(String localId) => values.delete('$keyPrefix$localId');

  /// Returns the enrollment entries of the secure storage.
  Map<String, String> _entries() => {
    for (MapEntry<String, String> entry in values.list().entries)
      if (entry.key.startsWith(keyPrefix)) entry.key: entry.value,
  };

  /// Returns whether [json] decodes to a record.
  bool _isReadable(String json) {
    try {
      _decode(json);
      return true;
    } on EzkeyLocalStateException {
      return false;
    }
  }

  /// Decodes a stored record.
  EzkeyEnrollment _decode(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const EzkeyLocalStateException('Stored enrollment is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const EzkeyLocalStateException('Stored enrollment is not a JSON object');
    }
    return EzkeyEnrollment.fromJson(decoded);
  }
}
