import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_android/local_auth_android.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

/// Asks the user to confirm an approval with the device credential or a biometric.
///
/// Contract §4 (ADR-0002 decision 2): Approve only, never Deny or leave-as-deny. This is an app-level
/// presence check, not a proof the server can verify.
final ezkeyApprovalConfirmationProvider = Provider<Future<bool> Function()>((ref) => confirmEzkeyApproval);

/// Returns whether the user confirmed. A device without a screen lock has nothing to confirm with,
/// so the approval goes on; a cancelled or failed prompt returns `false`.
Future<bool> confirmEzkeyApproval() async {
  LocalAuthentication localAuthentication = LocalAuthentication();
  try {
    if (!await localAuthentication.isDeviceSupported()) {
      return true;
    }
    return await localAuthentication.authenticate(
      localizedReason: translations.ezkey.attempt.confirmReason,
      authMessages: [
        AndroidAuthMessages(
          signInTitle: translations.ezkey.attempt.confirmTitle,
          signInHint: translations.localAuth.android.signInHint,
          cancelButton: translations.appUnlock.button.cancel,
        ),
      ],
    );
  } on LocalAuthException catch (ex) {
    debugPrint('EzKey approval confirmation: ${ex.code.name}');
    return ex.code == LocalAuthExceptionCode.noCredentialsSet;
  }
}
