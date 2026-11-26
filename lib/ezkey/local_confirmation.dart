import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_android/local_auth_android.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_darwin/local_auth_darwin.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_darwin/types/auth_messages_macos.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_windows/local_auth_windows.dart';
import 'package:open_authenticator/core/app_unlock/interaction.dart';
import 'package:open_authenticator/core/app_unlock/methods/method.dart';
import 'package:open_authenticator/core/app_unlock/reason.dart';
import 'package:open_authenticator/core/settings/app_unlock_method.dart';
import 'package:open_authenticator/core/settings/entry.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/utils/platform.dart';
import 'package:open_authenticator/utils/result/result.dart';
import 'package:open_authenticator/utils/window.dart';
import 'package:window_manager/window_manager.dart';

/// The approval protection the user chose, as in the EzKey reference app (#34).
enum EzkeyApprovalSecurity {
  /// No confirmation before responding (the default, like the reference app).
  standard,

  /// Confirm with the device credential or a biometric before approving.
  confirmBeforeApprovals,
}

/// The approval protection setting provider, remembered across launches.
final AsyncNotifierProvider<EzkeyApprovalSecurityEntry, EzkeyApprovalSecurity> ezkeyApprovalSecurityProvider = AsyncNotifierProvider.autoDispose<EzkeyApprovalSecurityEntry, EzkeyApprovalSecurity>(
  EzkeyApprovalSecurityEntry.new,
);

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
  /// lowering it first asks for a confirmation (see [confirmWithAppUnlockMethod]) through
  /// [interaction], so a holder of an unlocked phone cannot turn the protection off just before
  /// approving (EzKey reference app, "settings downgrade" finding).
  Future<bool> change(EzkeyApprovalSecurity value, AppUnlockInteraction interaction) async {
    final EzkeyApprovalSecurity current = await future;
    if (value == current) {
      return false;
    }
    if (value == .standard && !await ref.read(ezkeyDowngradeConfirmationProvider)(interaction)) {
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

/// Asks the user to confirm an approval (see [confirmWithAppUnlockMethod]).
///
/// Contract §4 (ADR-0002 decision 2): Approve only, never Deny or leave-as-deny. This is an app-level
/// presence check, not a proof the server can verify.
final ezkeyApprovalConfirmationProvider = Provider<Future<bool> Function(AppUnlockInteraction interaction)>(
  (ref) =>
      (interaction) => confirmWithAppUnlockMethod(
        ref,
        interaction,
        title: translations.ezkey.attempt.confirmTitle,
        reason: translations.ezkey.attempt.confirmReason,
      ),
);

/// Asks the user to confirm turning the approval protection off (see [confirmWithAppUnlockMethod]).
final ezkeyDowngradeConfirmationProvider = Provider<Future<bool> Function(AppUnlockInteraction interaction)>(
  (ref) =>
      (interaction) => confirmWithAppUnlockMethod(
        ref,
        interaction,
        title: translations.ezkey.security.downgradeTitle,
        reason: translations.ezkey.security.downgradeReason,
      ),
);

/// The device credential prompt with the desktop window kept in front (see [EzkeyDeviceConfirmation]),
/// replaceable in tests.
final ezkeyDeviceConfirmationProvider = Provider<Future<bool> Function({required String title, required String reason})>((ref) => EzkeyDeviceConfirmation().call);

/// Returns whether the user confirmed with the app unlock method they chose (#83): an EzKey approval
/// is one of upstream's sensitive actions, so the master password or upstream's local auth prompt is
/// asked through [interaction]. Without an app unlock method, upstream would ask for the master
/// password; the device credential is asked instead, with [title] and [reason], as before #83.
Future<bool> confirmWithAppUnlockMethod(Ref ref, AppUnlockInteraction interaction, {required String title, required String reason}) async {
  final String unlockMethodId = await ref.read(appUnlockMethodSettingsEntryProvider.future);
  if (unlockMethodId == NoneAppUnlockMethod.kMethodId) {
    return ref.read(ezkeyDeviceConfirmationProvider)(title: title, reason: reason);
  }
  final Result result = await ref.read(appUnlockMethodSettingsEntryProvider.notifier).unlockWithCurrentMethod(interaction, UnlockReason.sensibleAction);
  return result is ResultSuccess;
}

/// Returns whether the user confirmed with the device credential or a biometric. A device without a
/// screen lock has nothing to confirm with, so the action goes on; a cancelled or failed prompt
/// returns `false`.
///
/// Passes the prompt messages of every platform `local_auth` supports, like upstream's
/// `LocalAuthenticationDefault`, so a port needs no change here (ADR-0004). The desktop window is
/// handled around this prompt by [EzkeyDeviceConfirmation].
Future<bool> confirmWithDevice({required String title, required String reason}) async {
  final LocalAuthentication localAuthentication = LocalAuthentication();
  try {
    if (!await localAuthentication.isDeviceSupported()) {
      return true;
    }
    return await localAuthentication.authenticate(
      localizedReason: reason,
      authMessages: [
        IOSAuthMessages(
          cancelButton: translations.appUnlock.button.cancel,
        ),
        MacOSAuthMessages(
          cancelButton: translations.appUnlock.button.cancel,
        ),
        AndroidAuthMessages(
          signInTitle: title,
          signInHint: translations.localAuth.android.signInHint,
          cancelButton: translations.appUnlock.button.cancel,
        ),
        const WindowsAuthMessages(),
      ],
    );
  } on LocalAuthException catch (ex) {
    debugPrint('EzKey local confirmation: ${ex.code.name}');
    return ex.code == LocalAuthExceptionCode.noCredentialsSet;
  }
}

/// The window operations the device confirmation needs (see [EzkeyDeviceConfirmation]).
abstract interface class EzkeyPromptWindow {
  /// Whether the window stays above the other windows.
  bool get isAlwaysOnTop;

  /// Sets whether the window stays above the other windows.
  set isAlwaysOnTop(bool value);

  /// Gives the focus to the window.
  void focus();

  /// Takes the focus away from the window.
  void blur();
}

/// The app's desktop window, through `window_manager`.
class _NativePromptWindow implements EzkeyPromptWindow {
  /// The app window.
  final Window _window;

  /// Creates a new native prompt window instance.
  _NativePromptWindow(this._window);

  @override
  bool get isAlwaysOnTop => _window.isAlwaysOnTop;

  @override
  set isAlwaysOnTop(bool value) => _window.isAlwaysOnTop = value;

  @override
  void focus() => _window.focus();

  @override
  void blur() => _window.blur();
}

/// Returns the app's desktop window, or `null` on mobile.
EzkeyPromptWindow? _currentPromptWindow() {
  final Window? window = currentWindow;
  return window == null ? null : _NativePromptWindow(window);
}

/// Asks for the device credential (see [confirmWithDevice]) with the desktop window kept in front
/// while the prompt is open, as upstream's `LocalAuthenticationDefault.authenticate` does (ADR-0004 D4,
/// #163): otherwise Windows Hello can open behind the app.
///
/// The window is focused and kept on top during the prompt. Afterwards, whatever the outcome, its
/// always-on-top state is restored and, on Windows and macOS, it is blurred then focused again,
/// upstream's workaround for flutter/flutter#122322. A second confirmation while one is open is
/// refused without a prompt. This guard cannot see a prompt opened by upstream's own local
/// authentication.
class EzkeyDeviceConfirmation {
  /// Returns the window to keep in front, or `null` when there is none (mobile).
  final EzkeyPromptWindow? Function() _window;

  /// Whether the window is blurred then focused after the prompt.
  final bool _refocusAfterPrompt;

  /// Opens the device credential prompt.
  final Future<bool> Function({required String title, required String reason}) _prompt;

  /// Whether a prompt is open.
  bool _confirming = false;

  /// Creates a new device confirmation instance. The defaults are the app window, a refocus on
  /// Windows and macOS, and [confirmWithDevice]; tests replace them.
  EzkeyDeviceConfirmation({
    EzkeyPromptWindow? Function()? window,
    bool? refocusAfterPrompt,
    Future<bool> Function({required String title, required String reason})? prompt,
  }) : _window = window ?? _currentPromptWindow,
       _refocusAfterPrompt = refocusAfterPrompt ?? const {Platform.windows, Platform.macOS}.contains(currentPlatform),
       _prompt = prompt ?? confirmWithDevice;

  /// Returns whether the user confirmed, with [title] and [reason] shown by the prompt.
  Future<bool> call({required String title, required String reason}) async {
    if (_confirming) {
      return false;
    }
    final EzkeyPromptWindow? window = _window();
    final bool wasAlwaysOnTop = window?.isAlwaysOnTop ?? false;
    _confirming = true;
    try {
      window
        ?..focus()
        ..isAlwaysOnTop = true;
      return await _prompt(title: title, reason: reason);
    } finally {
      _confirming = false;
      if (window != null) {
        window.isAlwaysOnTop = wasAlwaysOnTop;
        if (_refocusAfterPrompt) {
          window
            ..blur()
            ..focus();
        }
      }
    }
  }
}
