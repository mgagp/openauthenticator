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

/// Shows a claimed auth attempt and sends the user's decision.
///
/// Basic flow (#22): leaving the page sends nothing and lets the attempt expire. The SDK holds the
/// decision lock, so a second decision on the same attempt is never sent.
class EzkeyApprovalPage extends ConsumerStatefulWidget {
  /// The enrollment the attempt belongs to.
  final EzkeyEnrollment enrollment;

  /// The claimed attempt.
  final PendingAuthAttempt attempt;

  /// Creates a new EzKey approval page instance.
  const EzkeyApprovalPage({
    super.key,
    required this.enrollment,
    required this.attempt,
  });

  /// Opens the page for [attempt].
  static Future<void> open(BuildContext context, EzkeyEnrollment enrollment, PendingAuthAttempt attempt) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => EzkeyApprovalPage(enrollment: enrollment, attempt: attempt),
    ),
  );

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EzkeyApprovalPageState();
}

/// The EzKey approval page state.
class _EzkeyApprovalPageState extends ConsumerState<EzkeyApprovalPage> {
  /// The challenge code controller (used when the attempt requires the code).
  final TextEditingController codeController = TextEditingController();

  /// Whether a decision is being sent.
  bool sending = false;

  @override
  void initState() {
    super.initState();
    codeController.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    EzkeyEnrollment enrollment = widget.enrollment;
    PendingAuthAttempt attempt = widget.attempt;
    bool canDecide = attempt.canDecide && !sending;
    return AppScaffold.scrollable(
      header: FHeader.nested(
        prefixes: [
          ClickableHeaderAction.back(
            onPress: () => Navigator.pop(context),
          ),
        ],
        title: Text(translations.ezkey.attempt.title),
      ),
      children: [
        Text(translations.ezkey.attempt.intro),
        const SizedBox(height: kSpace),
        FTileGroup(
          children: [
            if (attempt.contextTitle != null || attempt.contextMessage != null)
              FTile(
                prefix: const Icon(FLucideIcons.messageSquare),
                title: Text(attempt.contextTitle ?? translations.ezkey.attempt.request),
                subtitle: attempt.contextMessage == null ? null : Text(attempt.contextMessage!),
              ),
            FTile(
              prefix: const Icon(FLucideIcons.appWindow),
              title: Text(enrollment.integrationName ?? '—'),
              subtitle: Text(translations.ezkey.enroll.integration),
            ),
            FTile(
              prefix: const Icon(FLucideIcons.user),
              title: Text(enrollment.enrollmentName ?? '—'),
              subtitle: Text([translations.ezkey.enroll.account, enrollment.tenantName].whereType<String>().where((part) => part.isNotEmpty).join(' · ')),
            ),
          ],
        ),
        if (attempt.challengeRequired) ...[
          const SizedBox(height: kBigSpace),
          FTextField(
            key: const ValueKey('ezkey-attempt-code'),
            control: .managed(controller: codeController),
            label: Text(translations.ezkey.attempt.codeLabel),
            description: Text(translations.ezkey.attempt.codeHelp),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            enabled: canDecide,
          ),
        ],
        const SizedBox(height: kBigSpace),
        ClickableButton(
          key: const ValueKey('ezkey-attempt-approve'),
          onPress: canDecide && (!attempt.challengeRequired || codeController.text.isNotEmpty) ? () => decide(approve: true) : null,
          child: ButtonText(translations.ezkey.attempt.approve),
        ),
        const SizedBox(height: kSpace),
        ClickableButton(
          key: const ValueKey('ezkey-attempt-deny'),
          variant: .secondary,
          onPress: canDecide ? () => decide(approve: false) : null,
          child: ButtonText(translations.ezkey.attempt.deny),
        ),
        const SizedBox(height: kSpace),
        Text(
          translations.ezkey.attempt.leaveHint,
          style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
        ),
      ],
    );
  }

  /// Sends the decision, shows the signed result, then leaves the page.
  Future<void> decide({required bool approve}) async {
    PendingAuthAttempt attempt = widget.attempt;
    if (sending || !attempt.canDecide) {
      return;
    }
    if (attempt.isCertainlyExpired(DateTime.now().toUtc())) {
      showErrorToast(context, text: translations.ezkey.attempt.result.expired);
      Navigator.pop(context);
      return;
    }
    setState(() => sending = true);
    try {
      EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
      if (!mounted) {
        return;
      }
      AuthAttemptOutcome outcome = await showWaitingOverlay(
        context,
        message: translations.ezkey.attempt.sending,
        future: approve
            ? authenticator.approve(widget.enrollment, attempt, challengeResponse: attempt.challengeRequired ? int.parse(codeController.text) : null)
            : authenticator.deny(widget.enrollment, attempt),
      );
      debugPrint('EzKey decision sent: $outcome');
      if (!mounted) {
        return;
      }
      String message = ezkeyAttemptResultMessage(outcome.result);
      if (outcome.result == AuthAttemptResult.approved || outcome.result == AuthAttemptResult.denied) {
        showSuccessToast(context, text: message);
      } else {
        showErrorToast(context, text: message);
      }
      Navigator.pop(context);
    } on EzkeyException catch (ex) {
      debugPrint('EzKey decision failed: $ex');
      if (!mounted) {
        return;
      }
      showErrorToast(context, text: ezkeyAttemptErrorMessage(ex));
      if (attempt.canDecide) {
        // Nothing was sent, or the server asked to retry: the user may decide again.
        setState(() => sending = false);
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }
}
