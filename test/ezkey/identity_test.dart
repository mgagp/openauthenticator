import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/identity.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

import 'support.dart';

void main() {
  const String url = 'https://auth.example.com';

  group('EzkeyIdentity', () {
    test('a regular enrollment shows its application, account and organization, and no role', () {
      final EzkeyIdentity identity = EzkeyIdentity.fromFields(authApiBaseUrl: url, integrationName: 'Payroll', enrollmentName: 'Alice', tenantName: 'Acme');

      expect(identity.purpose, 'Payroll');
      expect(identity.account, 'Alice');
      expect(identity.organization, 'Acme');
      expect(identity.role, isNull);
      expect(identity.isAdministration, isFalse);
    });

    test('an administrator shows Administration and the role, whatever the server names it, and no organization', () {
      for (final MapEntry<String, String> admin in {'GLOBAL_ADMIN': translations.ezkey.identity.globalAdmin, 'TENANT_ADMIN': translations.ezkey.identity.tenantAdmin}.entries) {
        final EzkeyIdentity identity = EzkeyIdentity.fromFields(
          authApiBaseUrl: url,
          integrationName: 'Ezkey Administration',
          enrollmentName: 'Alice',
          tenantName: 'Ezkey System',
          isSystemIntegration: true,
          adminType: admin.key,
        );

        expect(identity.purpose, translations.ezkey.identity.administration);
        expect(identity.role, admin.value);
        expect(identity.account, 'Alice');
        expect(identity.organization, isNull);
        expect(identity.isAdministration, isTrue);
      }
    });

    test('an administrator with an unknown type still reads Administration, with no role', () {
      final EzkeyIdentity identity = EzkeyIdentity.fromFields(authApiBaseUrl: url, enrollmentName: 'Alice', isSystemIntegration: true, adminType: 'NEW_KIND');

      expect(identity.purpose, translations.ezkey.identity.administration);
      expect(identity.role, isNull);
    });

    test('the same string never fills two fields, ignoring case and spaces', () {
      final EzkeyIdentity identity = EzkeyIdentity.fromFields(authApiBaseUrl: url, integrationName: 'Payroll', enrollmentName: ' payroll ', tenantName: 'PAYROLL');

      expect(identity.purpose, 'Payroll');
      expect(identity.account, isNull);
      expect(identity.organization, isNull);
      expect(identity.summary, isEmpty);
    });

    test('an organization that repeats the account is dropped', () {
      final EzkeyIdentity identity = EzkeyIdentity.fromFields(authApiBaseUrl: url, integrationName: 'Payroll', enrollmentName: 'Acme', tenantName: 'acme');

      expect(identity.account, 'Acme');
      expect(identity.organization, isNull);
    });

    test('without an application name, the purpose falls back on the account, then on the server', () {
      final EzkeyIdentity withAccount = EzkeyIdentity.fromFields(authApiBaseUrl: url, integrationName: '  ', enrollmentName: 'Alice');
      final EzkeyIdentity withNothing = EzkeyIdentity.fromFields(authApiBaseUrl: url);

      expect(withAccount.purpose, 'Alice');
      expect(withAccount.account, isNull);
      expect(withNothing.purpose, 'auth.example.com');
    });

    test('the row line keeps what matters first, since a long end is what gets cut', () {
      final EzkeyIdentity regular = EzkeyIdentity.fromFields(authApiBaseUrl: url, integrationName: 'Payroll', enrollmentName: 'Alice', tenantName: 'A very long organization name');
      final EzkeyIdentity admin = EzkeyIdentity.fromFields(authApiBaseUrl: url, enrollmentName: 'Alice', isSystemIntegration: true, adminType: 'GLOBAL_ADMIN');

      expect(regular.summary, 'Alice · A very long organization name');
      expect(admin.summary, '${translations.ezkey.identity.globalAdmin} · Alice');
    });

    test('two administrators get different spoken names', () {
      final EzkeyIdentity global = EzkeyIdentity.of(testAdminEnrollment(1, adminType: 'GLOBAL_ADMIN'));
      final EzkeyIdentity tenant = EzkeyIdentity.of(testAdminEnrollment(2, adminType: 'TENANT_ADMIN'));

      expect(global.spokenName, isNot(tenant.spokenName));
      expect(global.spokenName, contains(translations.ezkey.identity.globalAdmin));
    });
  });
}
