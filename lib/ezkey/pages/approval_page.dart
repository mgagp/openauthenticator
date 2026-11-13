import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/identity.dart';
import 'package:open_authenticator/ezkey/installations.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/toast.dart';
import 'package:open_authenticator/ezkey/widgets/information_tile.dart';
import 'package:open_authenticator/ezkey/widgets/purpose_tile.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/utils/app_unlock_interaction.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/button_text.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/waiting_overlay.dart';

/// Shows a claimed auth attempt and sends the user's decision.
///
/// Approve asks for a local confirmation first when protection applies (contract §4, #34). Leaving the page while the attempt is
/// still undecided denies it once (contract §3). The SDK holds the decision lock, so a second
/// decision on the same attempt is never sent.
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
    PendingAuthAttempt attempt = widget.attempt;
    bool canDecide = attempt.canDecide && !sending;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          leaveAsDeny();
        }
      },
      child: AppScaffold.scrollable(
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
          _AttemptDetails(enrollment: widget.enrollment, attempt: attempt),
          if (attempt.challengeRequired) ...[
            const SizedBox(height: kBigSpace),
            _CodeField(controller: codeController, enabled: canDecide),
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
      ),
    );
  }

  /// Sends the decision, after the local confirmation when approving. The page stays open for another
  /// decision only while the attempt may still be decided.
  Future<void> decide({required bool approve}) async {
    PendingAuthAttempt attempt = widget.attempt;
    if (sending || !attempt.canDecide) {
      return;
    }
    if (attempt.isCertainlyExpired(DateTime.now().toUtc())) {
      showEzkeyErrorToast(context, text: translations.ezkey.attempt.result.expired);
      Navigator.pop(context);
      return;
    }
    setState(() => sending = true);
    bool confirmed = !approve || await _confirmApproval();
    if (confirmed && mounted) {
      await _send(approve: approve);
    }
    if (mounted && attempt.canDecide) {
      // Nothing was sent, or the server asked to retry: the user may decide again.
      setState(() => sending = false);
    }
  }

  /// Sends the decision and shows its result, or why it failed. Leaves the page unless the attempt
  /// may still be decided.
  Future<void> _send({required bool approve}) async {
    try {
      EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
      if (!mounted) {
        return;
      }
      AuthAttemptOutcome outcome = await showWaitingOverlay(
        context,
        message: translations.ezkey.attempt.sending,
        future: _respond(authenticator, approve: approve),
      );
      debugPrint('EzKey decision sent: $outcome');
      if (!mounted) {
        return;
      }
      _showResult(outcome.result);
      Navigator.pop(context);
    } on EzkeyException catch (ex) {
      debugPrint('EzKey decision failed: $ex');
      if (!mounted) {
        return;
      }
      showEzkeyErrorToast(context, text: ezkeyAttemptErrorMessage(ex));
      if (!widget.attempt.canDecide) {
        Navigator.pop(context);
      }
    }
  }

  /// Approves the attempt, with the typed code when it requires one, or denies it.
  Future<AuthAttemptOutcome> _respond(EzkeyAuthenticator authenticator, {required bool approve}) {
    PendingAuthAttempt attempt = widget.attempt;
    if (!approve) {
      return authenticator.deny(widget.enrollment, attempt);
    }
    return authenticator.approve(widget.enrollment, attempt, challengeResponse: attempt.challengeRequired ? int.parse(codeController.text) : null);
  }

  /// Shows the signed [result] of a decision: a success when the server did what the user decided.
  void _showResult(AuthAttemptResult result) {
    String message = ezkeyAttemptResultMessage(result);
    if (result == AuthAttemptResult.approved || result == AuthAttemptResult.denied) {
      showEzkeySuccessToast(context, text: message);
    } else {
      showEzkeyErrorToast(context, text: message);
    }
  }

  /// Returns whether the approval may go on: confirmed by the user, or no confirmation needed
  /// (contract §4: enrollment policy or user preference, see [ezkeyApprovalNeedsConfirmation]).
  Future<bool> _confirmApproval() async {
    EzkeyApprovalSecurity security = await ref.read(ezkeyApprovalSecurityProvider.future);
    if (!ezkeyApprovalNeedsConfirmation(widget.enrollment, security)) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    return ref.read(ezkeyApprovalConfirmationProvider)(context.appUnlockInteraction);
  }

  /// Denies the attempt once when the user leaves it undecided (contract §3): no prompt, no retry,
  /// and navigation is never held back.
  void leaveAsDeny() {
    PendingAuthAttempt attempt = widget.attempt;
    if (!attempt.canDecide || attempt.isCertainlyExpired(DateTime.now().toUtc())) {
      return;
    }
    EzkeyEnrollment enrollment = widget.enrollment;
    Future<EzkeyAuthenticator> authenticator = ref.read(ezkeyAuthenticatorProvider.future);
    BuildContext navigatorContext = Navigator.of(context).context;
    unawaited(_denyOnLeave(authenticator, enrollment, attempt, navigatorContext));
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }
}

/// Denies [attempt] after its page was left. The page is gone by then, so a failure is said on
/// [navigatorContext], the navigator's own context.
Future<void> _denyOnLeave(Future<EzkeyAuthenticator> authenticator, EzkeyEnrollment enrollment, PendingAuthAttempt attempt, BuildContext navigatorContext) async {
  try {
    AuthAttemptOutcome outcome = await (await authenticator).deny(enrollment, attempt);
    debugPrint('EzKey leave-as-deny sent: $outcome');
  } on EzkeyException catch (ex) {
    debugPrint('EzKey leave-as-deny failed: $ex');
    if (navigatorContext.mounted) {
      showEzkeyErrorToast(navigatorContext, text: translations.ezkey.attempt.leaveDenyFailed);
    }
  }
}

/// What the user is asked to approve: the request's context, then who it is for.
class _AttemptDetails extends ConsumerWidget {
  /// The enrollment the attempt belongs to.
  final EzkeyEnrollment enrollment;

  /// The claimed attempt.
  final PendingAuthAttempt attempt;

  /// Creates a new attempt details instance.
  const _AttemptDetails({
    required this.enrollment,
    required this.attempt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    EzkeyIdentity identity = EzkeyIdentity.of(enrollment);
    return FTileGroup(
      children: [
        if (attempt.contextTitle != null || attempt.contextMessage != null)
          FTile(
            prefix: const Icon(FLucideIcons.messageSquare),
            title: Text(attempt.contextTitle ?? translations.ezkey.attempt.request),
            subtitle: attempt.contextMessage == null ? null : Text(attempt.contextMessage!),
          ),
        EzkeyPurposeTile(identity: identity),
        if (identity.account != null)
          FTile(
            prefix: const Icon(FLucideIcons.user),
            title: Text(identity.account!),
            subtitle: Text([translations.ezkey.enroll.account, ?identity.organization].join(' · ')),
          )
        else if (identity.organization != null)
          EzkeyInformationTile(icon: FLucideIcons.building, label: translations.ezkey.enroll.organization, value: identity.organization),
        if (ref.watch(ezkeySeveralInstallationsProvider)) EzkeyInformationTile(icon: FLucideIcons.server, label: translations.ezkey.enroll.server, value: enrollment.authApiBaseUri.authority),
      ],
    );
  }
}

/// The field for the code an attempt requires before it can be approved.
class _CodeField extends StatelessWidget {
  /// The code controller.
  final TextEditingController controller;

  /// Whether the code can be typed.
  final bool enabled;

  /// Creates a new code field instance.
  const _CodeField({
    required this.controller,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => FTextField(
    key: const ValueKey('ezkey-attempt-code'),
    control: .managed(controller: controller),
    label: Text(translations.ezkey.attempt.codeLabel),
    description: Text(translations.ezkey.attempt.codeHelp),
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(9),
    ],
    enabled: enabled,
  );
}
