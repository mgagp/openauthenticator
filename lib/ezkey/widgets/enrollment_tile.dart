import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/identity.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/widgets/clickable.dart';

/// Shows one enrollment. The home zone and the EzKey page share it, so its identity changes in one
/// place.
class EzkeyEnrollmentTile extends StatelessWidget with FTileMixin {
  /// The enrollment.
  final EzkeyEnrollment enrollment;

  /// Whether to add the key tier and the server host.
  final bool showDetails;

  /// Whether to add the server host, to tell installations apart.
  final bool showServer;

  /// Triggered when the tile is pressed.
  final VoidCallback? onPress;

  /// The trailing widget.
  final Widget? suffix;

  /// Creates a new EzKey enrollment tile instance.
  const EzkeyEnrollmentTile({
    super.key,
    required this.enrollment,
    this.showDetails = false,
    this.showServer = false,
    this.onPress,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    EzkeyIdentity identity = EzkeyIdentity.of(enrollment);
    String host = enrollment.authApiBaseUri.authority;
    // One line each, so the summary cannot push the server away. The key tier comes first so a long
    // server address is what gets cut.
    String? server = showDetails ? '${ezkeyStorageTierLabel(enrollment.devicePrivateKeyStorageTier)} · $host' : (showServer ? host : null);
    return ClickableTile(
      prefix: const Icon(FLucideIcons.shieldCheck),
      title: Text(identity.purpose),
      subtitle: identity.summary.isEmpty && server == null
          ? null
          : Column(
              crossAxisAlignment: .start,
              children: [
                if (identity.summary.isNotEmpty) Text(identity.summary, maxLines: 1, overflow: .ellipsis),
                if (server != null) Text(server, maxLines: 1, overflow: .ellipsis),
              ],
            ),
      onPress: onPress,
      suffix: suffix,
    );
  }
}
