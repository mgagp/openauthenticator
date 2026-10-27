import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';

import 'support.dart';

void main() {
  group('SecureEzkeyEnrollmentStore', () {
    late InMemorySecureValues values;
    late SecureEzkeyEnrollmentStore store;

    setUp(() {
      values = InMemorySecureValues();
      store = SecureEzkeyEnrollmentStore(values);
    });

    test('save, load, list and delete round-trip a record', () async {
      EzkeyEnrollment enrollment = testEnrollment(7);
      await store.save(enrollment);

      EzkeyEnrollment? loaded = await store.load(enrollment.localId);
      expect(loaded?.toJson(), enrollment.toJson());
      expect((await store.list()).map((e) => e.localId), [enrollment.localId]);

      await store.delete(enrollment.localId);
      expect(await store.load(enrollment.localId), isNull);
      expect(await store.list(), isEmpty);
    });

    test('stores each record under its own prefixed key and ignores other entries', () async {
      values.values['app.session.token'] = 'unrelated';
      await store.save(testEnrollment(1));
      await store.save(testEnrollment(2));

      expect(values.values.keys.where((key) => key.startsWith(SecureEzkeyEnrollmentStore.keyPrefix)), hasLength(2));
      expect(values.values['app.session.token'], 'unrelated');
      expect(await store.list(), hasLength(2));
    });

    test('an unreadable record is reported, not hidden, and does not hide the others', () async {
      await store.save(testEnrollment(1));
      values.values['${SecureEzkeyEnrollmentStore.keyPrefix}http://localhost:8080#2'] = '{not json';
      values.values['${SecureEzkeyEnrollmentStore.keyPrefix}http://localhost:8080#3'] = '{"enrollmentId": 3}';

      expect((await store.list()).map((e) => e.enrollmentId), [1]);
      expect(store.unreadableLocalIds(), unorderedEquals(['http://localhost:8080#2', 'http://localhost:8080#3']));
      await expectLater(store.load('http://localhost:8080#2'), throwsA(isA<EzkeyLocalStateException>()));
    });
  });
}
