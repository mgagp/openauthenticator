import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/pages/settings/entries/widgets.dart';

/// "Confirm before approvals": the user's approval protection, shown as an upstream settings
/// checkbox. Turning it off asks for the device credential first (#34).
class EzkeyApprovalSecurityTile extends CheckboxSettingsEntryWidget<EzkeyApprovalSecurityEntry, EzkeyApprovalSecurity> {
  /// Creates a new EzKey approval security tile instance.
  EzkeyApprovalSecurityTile({
    super.key,
  }) : super(
         provider: ezkeyApprovalSecurityProvider,
         title: translations.ezkey.security.confirm.title,
         subtitle: translations.ezkey.security.confirm.subtitle,
         icon: FLucideIcons.fingerprint,
       );

  @override
  bool isEnabled(EzkeyApprovalSecurity? value) => value == .confirmBeforeApprovals;

  @override
  void changeValue(BuildContext context, WidgetRef ref, bool newValue) => ref.read(ezkeyApprovalSecurityProvider.notifier).change(newValue ? .confirmBeforeApprovals : .standard);
}
