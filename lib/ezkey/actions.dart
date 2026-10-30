import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/messages.dart';
import 'package:open_authenticator/ezkey/pages/approval_page.dart';
import 'package:open_authenticator/ezkey/pages/enroll_page.dart';
import 'package:open_authenticator/ezkey/pages/scan_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/widgets/dialog/text_input_dialog.dart';
import 'package:open_authenticator/ezkey/toast.dart';
import 'package:open_authenticator/widgets/waiting_overlay.dart';

/// The EzKey user actions, shared by the home zone and the EzKey page.
class EzkeyActions {
  /// The last Auth API address typed by the user, offered again for the next invitation.
  static String? _lastServerUrl;

  /// Scans an invitation QR code, then adds the enrollment.
  static Future<void> addFromScan(BuildContext context, WidgetRef ref) async {
    String? code = await EzkeyScanPage.scan(context);
    if (code != null && context.mounted) {
      await addEnrollment(context, ref, code);
    }
  }

  /// Asks for the invitation content, then adds the enrollment.
  static Future<void> addFromText(BuildContext context, WidgetRef ref) async {
    String? code = await TextInputDialog.prompt(
      context,
      title: translations.ezkey.page.paste.dialogTitle,
      message: translations.ezkey.page.paste.dialogMessage,
      validator: (value) => value == null || value.trim().isEmpty ? translations.error.validation.empty : null,
    );
    if (code != null && context.mounted) {
      await addEnrollment(context, ref, code.trim());
    }
  }

  /// Parses [rawCode], binds the invitation, then lets the user confirm on [EzkeyEnrollPage].
  static Future<void> addEnrollment(BuildContext context, WidgetRef ref, String rawCode) async {
    EnrollmentCode code;
    try {
      code = EnrollmentCode.parse(rawCode);
    } on EzkeyValidationException {
      showEzkeyErrorToast(context, text: translations.ezkey.scan.notAnInvitation);
      return;
    }
    String? serverUrl;
    if (code.authUrl == null) {
      serverUrl = await askServerUrl(context, ref);
      if (serverUrl == null || !context.mounted) {
        return;
      }
    }
    EzkeyBoundEnrollment bound;
    try {
      EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
      if (!context.mounted) {
        return;
      }
      bound = await showWaitingOverlay(
        context,
        message: translations.ezkey.enroll.binding,
        future: authenticator.bindEnrollment(code, authApiBaseUrlOverride: serverUrl),
      );
    } on EzkeyException catch (ex) {
      debugPrint('EzKey bind failed: $ex');
      if (context.mounted) {
        showEzkeyErrorToast(context, text: ex is EzkeyValidationException ? translations.ezkey.error.alreadyEnrolled : ezkeyEnrollmentErrorMessage(ex));
      }
      return;
    }
    if (context.mounted) {
      await EzkeyEnrollPage.open(context, bound);
    }
  }

  /// Claims the first pending auth attempt of [enrollments] and opens [EzkeyApprovalPage] for it.
  ///
  /// Runs on user action only: EzKey has no push and rejects automatic polling (EzKey ADR-0002).
  static Future<void> checkPending(BuildContext context, WidgetRef ref, List<EzkeyEnrollment> enrollments) async {
    EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
    if (!context.mounted) {
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
    if (!context.mounted) {
      return;
    }
    if (found != null) {
      await EzkeyApprovalPage.open(context, found.$1, found.$2);
    } else if (firstError != null) {
      showEzkeyErrorToast(context, text: ezkeyAttemptErrorMessage(firstError!));
    } else {
      showEzkeySuccessToast(context, text: translations.ezkey.attempt.check.none);
    }
  }

  /// Asks for the Auth API address when the invitation does not carry one.
  static Future<String?> askServerUrl(BuildContext context, WidgetRef ref) async {
    EzkeyAuthenticator authenticator = await ref.read(ezkeyAuthenticatorProvider.future);
    if (!context.mounted) {
      return null;
    }
    String? url = await TextInputDialog.prompt(
      context,
      title: translations.ezkey.server.title,
      message: translations.ezkey.server.message,
      initialValue: _lastServerUrl ?? 'https://',
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
    if (url == null) {
      return null;
    }
    _lastServerUrl = url.trim();
    return _lastServerUrl;
  }
}
