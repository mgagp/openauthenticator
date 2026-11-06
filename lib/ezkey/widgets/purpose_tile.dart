import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/identity.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

/// Shows what an enrollment signs in to: the application, or "Administration" with its role.
class EzkeyPurposeTile extends StatelessWidget with FTileMixin {
  /// The enrollment's identity.
  final EzkeyIdentity identity;

  /// The application's description, which an administrator's enrollment does not show.
  final String? details;

  /// Creates a new EzKey purpose tile instance.
  const EzkeyPurposeTile({
    super.key,
    required this.identity,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    String? subtitle = identity.isAdministration ? identity.role : translations.ezkey.enroll.integration;
    if (!identity.isAdministration && details != null && details!.isNotEmpty) {
      subtitle = '$subtitle · $details';
    }
    return FTile(
      prefix: Icon(identity.isAdministration ? FLucideIcons.shieldAlert : FLucideIcons.appWindow),
      title: Text(identity.purpose),
      subtitle: subtitle == null ? null : Text(subtitle),
    );
  }
}
