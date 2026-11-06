import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/providers.dart';

/// The enrollments of one EzKey installation, EzKey's trust zone: its identity is the Auth API
/// address (EzKey `ezkey_mobile/docs/MOBILE_DATA_MODEL.md` § Installation Trust Zone).
///
/// The screens show the enrollments flat, and name the server when there are several installations
/// (ADR-0007).
class EzkeyInstallation {
  /// The Auth API address the enrollments were made with, normalized by the SDK's URL policy.
  final String authApiBaseUrl;

  /// The enrollments, in the order of [ezkeyEnrollmentsProvider].
  final List<EzkeyEnrollment> enrollments;

  /// Creates a new EzKey installation instance.
  const EzkeyInstallation({
    required this.authApiBaseUrl,
    required this.enrollments,
  });

  /// Groups [enrollments] by installation, in order of first appearance.
  static List<EzkeyInstallation> group(List<EzkeyEnrollment> enrollments) {
    Map<String, List<EzkeyEnrollment>> groups = {};
    for (EzkeyEnrollment enrollment in enrollments) {
      groups.putIfAbsent(enrollment.authApiBaseUrl, () => []).add(enrollment);
    }
    return [
      for (MapEntry<String, List<EzkeyEnrollment>> entry in groups.entries) EzkeyInstallation(authApiBaseUrl: entry.key, enrollments: entry.value),
    ];
  }
}

/// The local EzKey enrollments, grouped by installation.
final ezkeyInstallationsProvider = FutureProvider<List<EzkeyInstallation>>((ref) async => EzkeyInstallation.group(await ref.watch(ezkeyEnrollmentsProvider.future)));

/// Whether the screens must name the server, because this device has several installations. Also
/// `true` while the number is unknown: showing it is the side that leaves no ambiguity.
final ezkeySeveralInstallationsProvider = Provider<bool>((ref) {
  List<EzkeyInstallation>? installations = ref.watch(ezkeyInstallationsProvider).value;
  return installations == null || installations.length > 1;
});
