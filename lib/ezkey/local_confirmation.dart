import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_android/local_auth_android.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/model/settings/entry.dart';

/// The approval protection the user chose, as in the EzKey reference app (#34).
enum EzkeyApprovalSecurity {
  /// No confirmation before responding (the default, like the reference app).
  standard,

  /// Confirm with the device credential or a biometric before approving.
  confirmBeforeApprovals,
}

/// The approval protection setting provider, remembered across launches.
final ezkeyApprovalSecurityProvider = AsyncNotifierProvider.autoDispose<EzkeyApprovalSecurityEntry, EzkeyApprovalSecurity>(EzkeyApprovalSecurityEntry.new);

/// Remembers the user's approval protection. Lowering it is protected: see [EzkeyApprovalSecurityEntry.change].
class EzkeyApprovalSecurityEntry extends EnumSettingsEntry<EzkeyApprovalSecurity> {
  /// Creates a new EzKey approval security entry instance.
  EzkeyApprovalSecurityEntry()
    : super(
        key: 'ezkeyApprovalSecurity',
        defaultValue: EzkeyApprovalSecurity.standard,
      );

  @override
  @protected
  List<EzkeyApprovalSecurity> get values => EzkeyApprovalSecurity.values;

  /// Changes the protection to [value] and returns whether it changed. Raising it is immediate;
  /// lowering it first asks for the device credential, so a holder of an unlocked phone cannot turn
  /// the protection off just before approving (EzKey reference app, "settings downgrade" finding).
  Future<bool> change(EzkeyApprovalSecurity value) async {
    EzkeyApprovalSecurity current = await future;
    if (value == current) {
      return false;
    }
    if (value == .standard && !await ref.read(ezkeyDowngradeConfirmationProvider)()) {
      return false;
    }
    await changeValue(value);
    return true;
  }
}

/// Whether approving an attempt of [enrollment] needs a local confirmation, with the user's
/// [security] choice.
///
/// Contract §4: confirmation applies "when protected mode applies (enrollment policy and/or device
/// preference)". The EzKey protocol does not carry an enrollment policy yet, so it never requires
/// one; the rule keeps its place for when EzKey's backend provides it.
bool ezkeyApprovalNeedsConfirmation(EzkeyEnrollment enrollment, EzkeyApprovalSecurity security) => _enrollmentPolicyRequiresConfirmation(enrollment) || security == .confirmBeforeApprovals;

/// The enrollment-level policy: not carried by the protocol yet, so never required.
bool _enrollmentPolicyRequiresConfirmation(EzkeyEnrollment enrollment) => false;

/// Asks the user to confirm an approval with the device credential or a biometric.
///
/// Contract §4 (ADR-0002 decision 2): Approve only, never Deny or leave-as-deny. This is an app-level
/// presence check, not a proof the server can verify.
final ezkeyApprovalConfirmationProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () => confirmWithDevice(
        title: translations.ezkey.attempt.confirmTitle,
        reason: translations.ezkey.attempt.confirmReason,
      ),
);

/// Asks the user to confirm turning the approval protection off.
final ezkeyDowngradeConfirmationProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () => confirmWithDevice(
        title: translations.ezkey.security.downgradeTitle,
        reason: translations.ezkey.security.downgradeReason,
      ),
);

/// Returns whether the user confirmed with the device credential or a biometric. A device without a
/// screen lock has nothing to confirm with, so the action goes on; a cancelled or failed prompt
/// returns `false`.
Future<bool> confirmWithDevice({required String title, required String reason}) async {
  LocalAuthentication localAuthentication = LocalAuthentication();
  try {
    if (!await localAuthentication.isDeviceSupported()) {
      return true;
    }
    return await localAuthentication.authenticate(
      localizedReason: reason,
      authMessages: [
        AndroidAuthMessages(
          signInTitle: title,
          signInHint: translations.localAuth.android.signInHint,
          cancelButton: translations.appUnlock.button.cancel,
        ),
      ],
    );
  } on LocalAuthException catch (ex) {
    debugPrint('EzKey local confirmation: ${ex.code.name}');
    return ex.code == LocalAuthExceptionCode.noCredentialsSet;
  }
}
