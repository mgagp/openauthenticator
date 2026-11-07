import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

/// Who and what an enrollment is, in the words of the EzKey reference app: every EzKey screen shows
/// these, so a person can tell which hat they are wearing (`ezkey_mobile/docs/MOBILE_POSITIONING.md`
/// § Enrollment identity vocabulary, `app/utils/enrollmentDisplay.ts`).
///
/// The same string never fills two fields: a label that repeats a higher one is dropped.
class EzkeyIdentity {
  /// What the enrollment signs in to: "Administration" for an EzKey administrator, otherwise the
  /// integration name. Never empty: it falls back on the account, then on the server.
  final String purpose;

  /// The account the enrollment belongs to.
  final String? account;

  /// The administrator role. Only an administrator has one.
  final String? role;

  /// The organization. An administrator has none: their enrollment belongs to EzKey's system tenant,
  /// which is not the business organization they may manage.
  final String? organization;

  /// Whether this enrollment protects an EzKey administrator.
  final bool isAdministration;

  /// Creates a new EzKey identity instance.
  const EzkeyIdentity._({
    required this.purpose,
    required this.isAdministration,
    this.account,
    this.role,
    this.organization,
  });

  /// Returns the identity of [enrollment].
  factory EzkeyIdentity.of(EzkeyEnrollment enrollment) => EzkeyIdentity.fromFields(
    authApiBaseUrl: enrollment.authApiBaseUrl,
    integrationName: enrollment.integrationName,
    enrollmentName: enrollment.enrollmentName,
    tenantName: enrollment.tenantName,
    isSystemIntegration: enrollment.isSystemIntegration,
    adminType: enrollment.adminType,
  );

  /// Returns the identity of [bound], an invitation that is not enrolled yet.
  factory EzkeyIdentity.ofBound(EzkeyBoundEnrollment bound) => EzkeyIdentity.fromFields(
    authApiBaseUrl: bound.authApiBaseUrl,
    integrationName: bound.integrationName,
    enrollmentName: bound.enrollmentName,
    tenantName: bound.tenantName,
    isSystemIntegration: bound.isSystemIntegration,
    adminType: bound.adminType,
  );

  /// Builds an identity from the labels of an enrollment.
  factory EzkeyIdentity.fromFields({
    required String authApiBaseUrl,
    String? integrationName,
    String? enrollmentName,
    String? tenantName,
    bool isSystemIntegration = false,
    String? adminType,
  }) {
    String? account = _clean(enrollmentName);
    String purpose = isSystemIntegration ? translations.ezkey.identity.administration : _clean(integrationName) ?? account ?? Uri.parse(authApiBaseUrl).authority;
    String? distinctAccount = _distinct(account, [purpose]);
    return EzkeyIdentity._(
      purpose: purpose,
      isAdministration: isSystemIntegration,
      account: distinctAccount,
      role: isSystemIntegration ? _distinct(_roleLabel(adminType), [purpose, distinctAccount]) : null,
      organization: isSystemIntegration ? null : _distinct(tenantName, [purpose, distinctAccount]),
    );
  }

  /// The line under the purpose on a row. In this order because one line can be cut: the role is
  /// short and tells two administrators apart, and the account matters more than the organization.
  String get summary => [?role, ?account, ?organization].join(' · ');

  /// The name a screen reader says for an action on this enrollment.
  String get spokenName => [purpose, ?role, ?account].join(', ');

  /// Returns the localized role for [adminType], or `null` when it is unknown.
  static String? _roleLabel(String? adminType) => switch (adminType) {
    'GLOBAL_ADMIN' => translations.ezkey.identity.globalAdmin,
    'TENANT_ADMIN' => translations.ezkey.identity.tenantAdmin,
    _ => null,
  };

  /// Trims [label], and treats a blank one as missing.
  static String? _clean(String? label) {
    String? trimmed = label?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Returns [label] when it is present and repeats none of [others], ignoring case.
  static String? _distinct(String? label, List<String?> others) {
    String? cleaned = _clean(label);
    if (cleaned == null) {
      return null;
    }
    bool repeated = others.any((other) => other?.toLowerCase() == cleaned.toLowerCase());
    return repeated ? null : cleaned;
  }
}
