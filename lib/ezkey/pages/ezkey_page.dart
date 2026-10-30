import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/widgets/enrollment_tile.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/confirmation_dialog.dart';
import 'package:open_authenticator/ezkey/toast.dart';

/// Lists the EzKey enrollments of this device in detail, and adds new ones.
class EzkeyPage extends ConsumerWidget {
  /// Creates a new EzKey page instance.
  const EzkeyPage({
    super.key,
  });

  /// Opens the page.
  static Future<void> open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const EzkeyPage()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppScaffold.asyncValue(
    header: FHeader.nested(
      prefixes: [
        ClickableHeaderAction.back(
          onPress: () => Navigator.pop(context),
        ),
      ],
      title: Text(translations.ezkey.page.title),
    ),
    asyncValue: ref.watch(ezkeyEnrollmentsProvider),
    onRetryPressed: () => ref.invalidate(ezkeyEnrollmentsProvider),
    builder: (enrollments) => [
      if (enrollments.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: kBigSpace),
          child: Text(translations.ezkey.page.empty),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: kBigSpace),
          child: FTileGroup(
            label: Text(translations.ezkey.page.enrollments),
            children: [
              for (EzkeyEnrollment enrollment in enrollments)
                EzkeyEnrollmentTile(
                  enrollment: enrollment,
                  showDetails: true,
                  suffix: ClickableButton.icon(
                    variant: .ghost,
                    onPress: () => forget(context, ref, enrollment),
                    child: const Icon(FLucideIcons.trash),
                  ),
                ),
            ],
          ),
        ),
      if (enrollments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: kBigSpace),
          child: FTileGroup(
            children: [
              ClickableTile(
                key: const ValueKey('ezkey-check-pending'),
                prefix: const Icon(FLucideIcons.bellRing),
                title: Text(translations.ezkey.attempt.check.title),
                subtitle: Text(translations.ezkey.attempt.check.subtitle),
                onPress: () => EzkeyActions.checkPending(context, ref, enrollments),
              ),
            ],
          ),
        ),
      FTileGroup(
        label: Text(translations.ezkey.page.add),
        children: [
          ClickableTile(
            key: const ValueKey('ezkey-add-scan'),
            prefix: const Icon(FLucideIcons.qrCode),
            title: Text(translations.ezkey.page.scan.title),
            subtitle: Text(translations.ezkey.page.scan.subtitle),
            onPress: () => EzkeyActions.addFromScan(context, ref),
          ),
          ClickableTile(
            key: const ValueKey('ezkey-add-paste'),
            prefix: const Icon(FLucideIcons.keyboard),
            title: Text(translations.ezkey.page.paste.title),
            subtitle: Text(translations.ezkey.page.paste.subtitle),
            onPress: () => EzkeyActions.addFromText(context, ref),
          ),
        ],
      ),
    ],
  );

  /// Removes [enrollment] from this device, after confirmation.
  Future<void> forget(BuildContext context, WidgetRef ref, EzkeyEnrollment enrollment) async {
    bool confirmed = await ConfirmationDialog.ask(
      context,
      title: translations.ezkey.page.forget.confirmTitle,
      message: translations.ezkey.page.forget.confirmMessage(integration: enrollment.integrationName ?? ''),
      okButtonVariant: .destructive,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(ezkeyEnrollmentsProvider.notifier).forget(enrollment);
      if (context.mounted) {
        showEzkeySuccessToast(context, text: translations.ezkey.page.forget.success);
      }
    } on EzkeyException catch (ex) {
      if (context.mounted) {
        showEzkeyErrorToast(context, text: ezkeyEnrollmentErrorMessage(ex));
      }
    }
  }
}
