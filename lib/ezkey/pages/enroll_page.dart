import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/button_text.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/toast.dart';
import 'package:open_authenticator/widgets/waiting_overlay.dart';

/// Second enrollment step: shows who is asking (from the signed bind answer) and takes the
/// 6-digit enrollment code. Pops with the new enrollment, or `null` when the user left.
class EzkeyEnrollPage extends ConsumerStatefulWidget {
  /// The bound invitation.
  final EzkeyBoundEnrollment bound;

  /// Creates a new EzKey enroll page instance.
  const EzkeyEnrollPage({
    super.key,
    required this.bound,
  });

  /// Opens the page for [bound].
  static Future<EzkeyEnrollment?> open(BuildContext context, EzkeyBoundEnrollment bound) => Navigator.push<EzkeyEnrollment>(
    context,
    MaterialPageRoute(builder: (context) => EzkeyEnrollPage(bound: bound)),
  );

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EzkeyEnrollPageState();
}

/// The EzKey enroll page state.
class _EzkeyEnrollPageState extends ConsumerState<EzkeyEnrollPage> {
  /// The enrollment code controller.
  final TextEditingController codeController = TextEditingController();

  /// Whether the code has six digits.
  bool codeComplete = false;

  /// Whether the verify request is in flight (prevents a second submission).
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    codeController.addListener(() {
      bool complete = RegExp(r'^\d{6}$').hasMatch(codeController.text);
      if (complete != codeComplete) {
        setState(() => codeComplete = complete);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    EzkeyBoundEnrollment bound = widget.bound;
    return AppScaffold.scrollable(
      header: FHeader.nested(
        prefixes: [
          ClickableHeaderAction.back(
            onPress: () => Navigator.pop(context),
          ),
        ],
        title: Text(translations.ezkey.enroll.title),
      ),
      children: [
        Text(translations.ezkey.enroll.intro),
        const SizedBox(height: kSpace),
        FTileGroup(
          children: [
            _InformationTile(icon: FLucideIcons.appWindow, label: translations.ezkey.enroll.integration, value: bound.integrationName, details: bound.integrationDescription),
            _InformationTile(icon: FLucideIcons.building, label: translations.ezkey.enroll.organization, value: bound.tenantName),
            _InformationTile(icon: FLucideIcons.user, label: translations.ezkey.enroll.account, value: bound.enrollmentName),
            _InformationTile(icon: FLucideIcons.server, label: translations.ezkey.enroll.server, value: Uri.parse(bound.authApiBaseUrl).authority),
          ],
        ),
        if (bound.isSystemIntegration) ...[
          const SizedBox(height: kSpace),
          FAlert(
            icon: const Icon(FLucideIcons.shieldAlert),
            title: Text(translations.ezkey.enroll.administrator),
          ),
        ],
        const SizedBox(height: kBigSpace),
        FTextField(
          key: const ValueKey('ezkey-enrollment-code'),
          control: .managed(controller: codeController),
          label: Text(translations.ezkey.enroll.codeLabel),
          description: Text(translations.ezkey.enroll.codeHelp),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          enabled: !submitting,
          onSubmit: (_) => submit(),
        ),
        const SizedBox(height: kBigSpace),
        ClickableButton(
          key: const ValueKey('ezkey-enroll-submit'),
          onPress: codeComplete && !submitting ? submit : null,
          child: ButtonText(translations.ezkey.enroll.submit),
        ),
        const SizedBox(height: kSpace),
        Text(
          translations.ezkey.enroll.abandonWarning,
          style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

  /// Sends the enrollment code.
  Future<void> submit() async {
    if (!codeComplete || submitting) {
      return;
    }
    setState(() => submitting = true);
    try {
      EzkeyEnrollment enrollment = await showWaitingOverlay(
        context,
        message: translations.ezkey.enroll.verifying,
        future: ref.read(ezkeyEnrollmentsProvider.notifier).complete(widget.bound, parseChallengeCode(codeController.text)),
      );
      if (mounted) {
        showSuccessToast(context, text: translations.ezkey.enroll.success(integration: enrollment.integrationName ?? ''));
        Navigator.pop(context, enrollment);
      }
    } on EzkeyException catch (ex) {
      debugPrint('EzKey enrollment verify failed: $ex');
      if (!mounted) {
        return;
      }
      showErrorToast(context, text: ezkeyEnrollmentErrorMessage(ex));
      if (isEzkeyInvitationDead(ex)) {
        Navigator.pop(context);
      } else {
        setState(() => submitting = false);
      }
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }
}

/// One line of what the signed bind answer says.
class _InformationTile extends StatelessWidget with FTileMixin {
  /// The icon.
  final IconData icon;

  /// The label.
  final String label;

  /// The value (may be missing on the server side).
  final String? value;

  /// Optional details under the value.
  final String? details;

  /// Creates a new information tile instance.
  const _InformationTile({
    required this.icon,
    required this.label,
    required this.value,
    this.details,
  });

  @override
  Widget build(BuildContext context) => FTile(
    prefix: Icon(icon),
    title: Text(value == null || value!.isEmpty ? '—' : value!),
    subtitle: Text(details == null || details!.isEmpty ? label : '$label · $details'),
  );
}
