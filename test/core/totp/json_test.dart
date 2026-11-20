import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/core/crypto/salt.dart';
import 'package:open_authenticator/core/totp/algorithm.dart';
import 'package:open_authenticator/core/totp/json.dart';
import 'package:open_authenticator/core/totp/totp.dart';

/// A TOTP with every field set.
final Totp _fullTotp = Totp(
  uuid: '6f1c2a54-0b5e-4a7e-9b1d-2f3c4d5e6f70',
  encryptedData: EncryptedData(
    encryptedSecret: Uint8List.fromList([1, 2, 3]),
    encryptedLabel: Uint8List.fromList([4, 5]),
    encryptedIssuer: Uint8List.fromList([6]),
    encryptedImageUrl: Uint8List.fromList([7, 8]),
    encryptionSalt: Salt.fromRawValue(value: Uint8List.fromList([9, 10, 11])),
  ),
  algorithm: Algorithm.sha256,
  digits: 8,
  validity: const Duration(seconds: 60),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1762041600000),
);

/// A TOTP with only the required fields.
final Totp _minimalTotp = Totp(
  uuid: 'a0b1c2d3-e4f5-4a6b-8c9d-0e1f2a3b4c5d',
  encryptedData: EncryptedData(
    encryptedSecret: Uint8List.fromList([1, 2, 3]),
    encryptedLabel: null,
    encryptionSalt: Salt.fromRawValue(value: Uint8List.fromList([9, 10, 11])),
  ),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1762041600000),
);

/// Encodes [data] to a JSON string and decodes it back, as backups and the backend do.
Map<String, dynamic> _throughJson(Map<String, dynamic> data) => jsonDecode(jsonEncode(data));

void main() {
  group('JsonTotp', () {
    test('keeps the key names shared with backups and the backend', () {
      final Map<String, dynamic> json = _fullTotp.toJson();

      expect(json, {
        'uuid': '6f1c2a54-0b5e-4a7e-9b1d-2f3c4d5e6f70',
        'secret': [1, 2, 3],
        'label': [4, 5],
        'issuer': [6],
        'imageUrl': [7, 8],
        'encryptionSalt': [9, 10, 11],
        'algorithm': 'SHA256',
        'digits': 8,
        'validity': 60,
        'updatedAt': 1762041600000,
      });
    });

    test('leaves out the fields that are not set', () {
      final Map<String, dynamic> json = _minimalTotp.toJson();

      expect(json.keys, unorderedEquals(['uuid', 'secret', 'encryptionSalt', 'updatedAt']));
    });

    test('survives a round trip through a JSON string', () {
      expect(JsonTotp.fromJson(_throughJson(_fullTotp.toJson())), _fullTotp);
      expect(JsonTotp.fromJson(_throughJson(_minimalTotp.toJson())), _minimalTotp);
    });

    test('can leave the UUID out and take it as a parameter', () {
      final Map<String, dynamic> json = _throughJson(_fullTotp.toJson(includeUuid: false));

      expect(json.containsKey('uuid'), isFalse);
      expect(JsonTotp.tryFromJson(json), isNull);
      expect(JsonTotp.tryFromJson(json, uuid: _fullTotp.uuid), _fullTotp);
    });

    // Upstream made the parsing stricter in the 2026-11 sync (#148, `963d86c`): an unknown algorithm or a
    // wrong-type field used to be ignored; it now rejects the entry. Unusable digits and periods from older
    // clients are dropped by `fromJson`, which keeps the encrypted data and falls back to the TOTP defaults.
    test('reads the algorithm whatever its case, and rejects an unknown one', () {
      final Map<String, dynamic> json = _throughJson(_fullTotp.toJson());

      expect(JsonTotp.fromJson({...json, 'algorithm': 'sha512'}).algorithm, Algorithm.sha512);
      expect(JsonTotp.tryFromJson({...json, 'algorithm': 'MD5'}), isNull);
    });

    test('drops unusable digits and periods, and rejects a wrong-type algorithm or label', () {
      final Map<String, dynamic> json = _throughJson(_fullTotp.toJson());

      final Totp totp = JsonTotp.fromJson({...json, 'digits': '8', 'validity': 0});

      expect(totp.digits, isNull);
      expect(totp.validity, isNull);
      expect(totp.encryptedData.encryptedSecret, _fullTotp.encryptedData.encryptedSecret);
      expect(JsonTotp.tryFromJson({...json, 'algorithm': 1}), isNull);
      expect(JsonTotp.tryFromJson({...json, 'label': 'text'}), isNull);
    });

    test('returns null without a secret, a salt or a UUID', () {
      final Map<String, dynamic> json = _throughJson(_fullTotp.toJson());

      expect(JsonTotp.tryFromJson({...json}..remove('secret')), isNull);
      expect(JsonTotp.tryFromJson({...json, 'encryptionSalt': 'AAEC'}), isNull);
      expect(JsonTotp.tryFromJson({...json}..remove('uuid')), isNull);
      expect(() => JsonTotp.fromJson({...json}..remove('secret')), throwsA(isA<TypeError>()));
    });

    // Upstream fixed this quirk in the 2026-11 sync (#148): a missing date used to throw a TypeError.
    test('returns null when the update date is missing', () {
      final Map<String, dynamic> json = _throughJson(_fullTotp.toJson())..remove('updatedAt');

      expect(JsonTotp.tryFromJson(json), isNull);
    });
  });
}
