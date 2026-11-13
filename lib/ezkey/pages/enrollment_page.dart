import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/identity.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/toast.dart';
import 'package:open_authenticator/ezkey/widgets/administrator_alert.dart';
import 'package:open_authenticator/ezkey/widgets/information_tile.dart';
import 'package:open_authenticator/ezkey/widgets/purpose_tile.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/confirmation_dialog.dart';

/// Shows one enrollment: who it is for, where its key lives, a request check for this enrollment
/// only, and its removal from this device (#33).
class EzkeyEnrollmentPage extends ConsumerWidget {
  /// The enrollment.
  final EzkeyEnrollment enrollment;

  /// Creates a new EzKey enrollment page instance.
  const EzkeyEnrollmentPage({
    super.key,
    required this.enrollment,
  });

  /// Opens the page for [enrollment].
  static Future<void> open(BuildContext context, EzkeyEnrollment enrollment) => Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => EzkeyEnrollmentPage(enrollment: enrollment)),
  );

  /// The enrollment's identity.
  EzkeyIdentity get identity => EzkeyIdentity.of(enrollment);

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppScaffold.scrollable(
    header: FHeader.nested(
      prefixes: [
        ClickableHeaderAction.back(
          onPress: () => Navigator.pop(context),
        ),
      ],
      // Not the purpose: the first tile shows it, and the same string must not appear at two levels.
      title: Text(translations.ezkey.page.title),
    ),
    children: [
      _EnrollmentDetails(enrollment: enrollment),
      if (enrollment.isSystemIntegration) EzkeyAdministratorAlert(text: translations.ezkey.enrollment.administrator),
      const SizedBox(height: kBigSpace),
      FTileGroup(
        children: [
          ClickableTile(
            key: const ValueKey('ezkey-enrollment-check'),
            prefix: const Icon(FLucideIcons.bellRing),
            title: Text(translations.ezkey.attempt.check.title),
            subtitle: Text(translations.ezkey.enrollment.checkSubtitle),
            onPress: () => EzkeyActions.checkPending(context, ref, enrollment),
          ),
        ],
      ),
      const SizedBox(height: kBigSpace),
      FTileGroup(
        children: [
          ClickableTile(
            key: const ValueKey('ezkey-enrollment-forget'),
            prefix: const Icon(FLucideIcons.trash),
            title: Text(translations.ezkey.page.forget.title),
            onPress: () => forget(context, ref),
          ),
        ],
      ),
    ],
  );

  /// Removes the enrollment from this device after confirmation, then leaves the page.
  Future<void> forget(BuildContext context, WidgetRef ref) async {
    bool confirmed = await ConfirmationDialog.ask(
      context,
      title: translations.ezkey.page.forget.confirmTitle,
      message: translations.ezkey.page.forget.confirmMessage(integration: identity.purpose),
      okButtonVariant: .destructive,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(ezkeyEnrollmentsProvider.notifier).forget(enrollment);
      if (context.mounted) {
        showEzkeySuccessToast(context, text: translations.ezkey.page.forget.success);
        Navigator.pop(context);
      }
    } on EzkeyException catch (ex) {
      if (context.mounted) {
        showEzkeyErrorToast(context, text: ezkeyEnrollmentErrorMessage(ex));
      }
    }
  }
}

/// Who the enrollment is for, where its key lives, its server and its date.
class _EnrollmentDetails extends StatelessWidget {
  /// The enrollment.
  final EzkeyEnrollment enrollment;

  /// Creates a new enrollment details instance.
  const _EnrollmentDetails({
    required this.enrollment,
  });

  @override
  Widget build(BuildContext context) {
    EzkeyIdentity identity = EzkeyIdentity.of(enrollment);
    return FTileGroup(
      children: [
        EzkeyPurposeTile(identity: identity, details: enrollment.integrationDescription),
        if (identity.organization != null) EzkeyInformationTile(icon: FLucideIcons.building, label: translations.ezkey.enroll.organization, value: identity.organization),
        if (identity.account != null) EzkeyInformationTile(icon: FLucideIcons.user, label: translations.ezkey.enroll.account, value: identity.account),
        EzkeyInformationTile(icon: FLucideIcons.keyRound, label: translations.ezkey.enrollment.keyStorage, value: ezkeyStorageTierLabel(enrollment.devicePrivateKeyStorageTier)),
        EzkeyInformationTile(icon: FLucideIcons.server, label: translations.ezkey.enroll.server, value: enrollment.authApiBaseUri.authority),
        EzkeyInformationTile(
          icon: FLucideIcons.calendarCheck,
          label: translations.ezkey.enrollment.enrolledAt,
          value: MaterialLocalizations.of(context).formatMediumDate(enrollment.enrolledAt.toLocal()),
        ),
      ],
    );
  }
}
