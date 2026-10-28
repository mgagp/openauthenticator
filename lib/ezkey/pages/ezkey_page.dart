import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/pages/approval_page.dart';
import 'package:open_authenticator/ezkey/pages/enroll_page.dart';
import 'package:open_authenticator/ezkey/pages/scan_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/confirmation_dialog.dart';
import 'package:open_authenticator/widgets/dialog/text_input_dialog.dart';
import 'package:open_authenticator/widgets/toast.dart';
import 'package:open_authenticator/widgets/waiting_overlay.dart';

/// Lists the EzKey enrollments of this device and adds new ones.
class EzkeyPage extends ConsumerStatefulWidget {
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
  ConsumerState<ConsumerStatefulWidget> createState() => _EzkeyPageState();
}

/// The EzKey page state.
class _EzkeyPageState extends ConsumerState<EzkeyPage> {
  /// The last Auth API address typed by the user, offered again for the next invitation.
  String? lastServerUrl;

  @override
  Widget build(BuildContext context) => AppScaffold.asyncValue(
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
              for (EzkeyEnrollment enrollment in enrollments) _EnrollmentTile(enrollment: enrollment),
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
                onPress: () => checkPending(enrollments),
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
            onPress: () async {
              String? code = await EzkeyScanPage.scan(context);
              if (code != null && context.mounted) {
                await addEnrollment(code);
              }
            },
          ),
          ClickableTile(
            key: const ValueKey('ezkey-add-paste'),
            prefix: const Icon(FLucideIcons.keyboard),
            title: Text(translations.ezkey.page.paste.title),
            subtitle: Text(translations.ezkey.page.paste.subtitle),
            onPress: () async {
              String? code = await TextInputDialog.prompt(
                context,
                title: translations.ezkey.page.paste.dialogTitle,
                message: translations.ezkey.page.paste.dialogMessage,
                validator: (value) => value == null || value.trim().isEmpty ? translations.error.validation.empty : null,
              );
              if (code != null && context.mounted) {
                await addEnrollment(code.trim());
              }
            },
          ),
        ],
      ),
    ],
  );

  /// Parses [rawCode], binds the invitation, then lets the user confirm on [EzkeyEnrollPage].
  Future<void> addEnrollment(String rawCode) async {
    EnrollmentCode code;
    try {
      code = EnrollmentCode.parse(rawCode);
    } on EzkeyValidationException {
      showErrorToast(context, text: translations.ezkey.scan.notAnInvitation);
      return;
    }
    String? serverUrl;
    if (code.authUrl == null) {
      serverUrl = await askServerUrl();
      if (serverUrl == null || !mounted) {
        return;
      }
    }
    EzkeyBoundEnrollment bound;
    try {
      EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
      if (!mounted) {
        return;
      }
      bound = await showWaitingOverlay(
        context,
        message: translations.ezkey.enroll.binding,
        future: authenticator.bindEnrollment(code, authApiBaseUrlOverride: serverUrl),
      );
    } on EzkeyException catch (ex) {
      debugPrint('EzKey bind failed: $ex');
      if (mounted) {
        showErrorToast(context, text: ex is EzkeyValidationException ? translations.ezkey.error.alreadyEnrolled : ezkeyEnrollmentErrorMessage(ex));
      }
      return;
    }
    if (mounted) {
      await EzkeyEnrollPage.open(context, bound);
    }
  }

  /// Claims the first pending auth attempt of [enrollments] and opens [EzkeyApprovalPage] for it.
  ///
  /// Runs on user action only: the SDK advises against polling in the background.
  Future<void> checkPending(List<EzkeyEnrollment> enrollments) async {
    EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
    if (!mounted) {
      return;
    }
    EzkeyException? firstError;
    (EzkeyEnrollment, PendingAuthAttempt)? found = await showWaitingOverlay(
      context,
      message: translations.ezkey.attempt.check.checking,
      future: () async {
        for (EzkeyEnrollment enrollment in enrollments) {
          try {
            PendingAuthAttempt? attempt = await authenticator.checkPending(enrollment);
            if (attempt != null) {
              debugPrint('EzKey claimed $attempt');
              return (enrollment, attempt);
            }
          } on EzkeyException catch (ex) {
            // One failing enrollment (revoked, unreachable server) must not hide the others.
            debugPrint('EzKey pending check failed for enrollment ${enrollment.enrollmentId}: $ex');
            firstError ??= ex;
          }
        }
        return null;
      }(),
    );
    if (!mounted) {
      return;
    }
    if (found != null) {
      await EzkeyApprovalPage.open(context, found.$1, found.$2);
    } else if (firstError != null) {
      showErrorToast(context, text: ezkeyAttemptErrorMessage(firstError!));
    } else {
      showSuccessToast(context, text: translations.ezkey.attempt.check.none);
    }
  }

  /// Asks for the Auth API address when the invitation does not carry one.
  Future<String?> askServerUrl() async {
    EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
    if (!mounted) {
      return null;
    }
    String? url = await TextInputDialog.prompt(
      context,
      title: translations.ezkey.server.title,
      message: translations.ezkey.server.message,
      initialValue: lastServerUrl ?? 'https://',
      keyboardType: TextInputType.url,
      validator: (value) {
        try {
          authenticator.urlPolicy.require(value?.trim() ?? '');
          return null;
        } on EzkeyValidationException {
          return translations.ezkey.server.invalid;
        }
      },
    );
    if (url != null) {
      lastServerUrl = url.trim();
    }
    return lastServerUrl;
  }
}

/// Shows one enrollment, with its "remove from this device" action.
class _EnrollmentTile extends ConsumerWidget with FTileMixin {
  /// The enrollment.
  final EzkeyEnrollment enrollment;

  /// Creates a new enrollment tile instance.
  const _EnrollmentTile({
    required this.enrollment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => FTile(
    prefix: const Icon(FLucideIcons.shieldCheck),
    title: Text(enrollment.integrationName ?? '—'),
    subtitle: Text([enrollment.tenantName, enrollment.enrollmentName, Uri.parse(enrollment.authApiBaseUrl).authority].whereType<String>().where((part) => part.isNotEmpty).join(' · ')),
    suffix: ClickableButton.icon(
      variant: .ghost,
      onPress: () => forget(context, ref),
      child: const Icon(FLucideIcons.trash),
    ),
  );

  /// Removes the enrollment from this device, after confirmation.
  Future<void> forget(BuildContext context, WidgetRef ref) async {
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
        showSuccessToast(context, text: translations.ezkey.page.forget.success);
      }
    } on EzkeyException catch (ex) {
      if (context.mounted) {
        showErrorToast(context, text: ezkeyEnrollmentErrorMessage(ex));
      }
    }
  }
}
