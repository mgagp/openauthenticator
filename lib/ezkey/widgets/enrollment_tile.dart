import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/widgets/clickable.dart';

/// Shows one enrollment. The home zone and the EzKey page share it, so a richer display (trust
/// zone, admin role, #26) changes in one place.
class EzkeyEnrollmentTile extends StatelessWidget with FTileMixin {
  /// The enrollment.
  final EzkeyEnrollment enrollment;

  /// Whether to add the key tier and the server host.
  final bool showDetails;

  /// Triggered when the tile is pressed.
  final VoidCallback? onPress;

  /// The trailing widget.
  final Widget? suffix;

  /// Creates a new EzKey enrollment tile instance.
  const EzkeyEnrollmentTile({
    super.key,
    required this.enrollment,
    this.showDetails = false,
    this.onPress,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    String account = [enrollment.tenantName, enrollment.enrollmentName].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    return ClickableTile(
      prefix: const Icon(FLucideIcons.shieldCheck),
      title: Text(enrollment.integrationName ?? '—'),
      // One line each: the key tier comes first so a long server address is what gets cut.
      subtitle: showDetails
          ? Column(
              crossAxisAlignment: .start,
              children: [
                Text(account, maxLines: 1, overflow: .ellipsis),
                Text('${ezkeyStorageTierLabel(enrollment.devicePrivateKeyStorageTier)} · ${Uri.parse(enrollment.authApiBaseUrl).authority}', maxLines: 1, overflow: .ellipsis),
              ],
            )
          : Text(account, maxLines: 1, overflow: .ellipsis),
      onPress: onPress,
      suffix: suffix,
    );
  }
}
