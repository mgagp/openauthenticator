import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/core/app_unlock/interaction.dart';
import 'package:open_authenticator/core/app_unlock/methods/method.dart';
import 'package:open_authenticator/core/app_unlock/reason.dart';
import 'package:open_authenticator/core/settings/app_unlock_method.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/utils/result/result.dart';

import 'support.dart';

/// Keeps the approval protection in memory instead of the shared preferences.
class _MemorySecurity extends EzkeyApprovalSecurityEntry {
  /// The initial protection.
  final EzkeyApprovalSecurity initial;

  /// Creates a new memory security instance.
  _MemorySecurity(this.initial);

  @override
  FutureOr<EzkeyApprovalSecurity> build() => initial;

  @override
  Future<void> changeValue(EzkeyApprovalSecurity value) async => state = AsyncData(value);
}

/// An app unlock method fixed to [methodId], whose unlock records its reason and answers [result].
class _FixedUnlockMethod extends AppUnlockMethodSettingsEntry {
  /// The chosen method id.
  final String methodId;

  /// What the unlock answers.
  final Result result;

  /// The reasons of the unlock calls, in order.
  final List<UnlockReason> reasons = [];

  /// Creates a new fixed unlock method instance.
  _FixedUnlockMethod(this.methodId, this.result);

  @override
  FutureOr<String> build() => methodId;

  @override
  Future<Result> unlockWithCurrentMethod(AppUnlockInteraction interaction, UnlockReason unlockReason, {bool? allowNone}) async {
    reasons.add(unlockReason);
    return result;
  }
}

/// An interaction that never prompts: the unlock method is faked.
class _NoInteraction with AppUnlockInteraction {
  @override
  bool get canInteract => true;

  @override
  Future<String?> promptMasterPassword({String? message}) async => null;
}

void main() {
  group('ezkeyApprovalNeedsConfirmation', () {
    test('only when the user chose to confirm, while enrollments carry no policy', () {
      expect(ezkeyApprovalNeedsConfirmation(testEnrollment(1), .standard), isFalse);
      expect(ezkeyApprovalNeedsConfirmation(testEnrollment(1), .confirmBeforeApprovals), isTrue);
    });
  });

  group('EzkeyApprovalSecurityEntry', () {
    late int downgradeConfirmations;

    /// Returns a container whose protection starts at [initial] and whose downgrade prompt answers [confirmed].
    ProviderContainer createContainer(EzkeyApprovalSecurity initial, {required bool confirmed}) {
      downgradeConfirmations = 0;
      final ProviderContainer container = ProviderContainer(
        overrides: [
          ezkeyApprovalSecurityProvider.overrideWith(() => _MemorySecurity(initial)),
          ezkeyDowngradeConfirmationProvider.overrideWithValue((_) async {
            downgradeConfirmations++;
            return confirmed;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(ezkeyApprovalSecurityProvider, (_, _) {});
      return container;
    }

    test('raising the protection is immediate', () async {
      final ProviderContainer container = createContainer(.standard, confirmed: false);

      final bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.confirmBeforeApprovals, _NoInteraction());

      expect(changed, isTrue);
      expect(downgradeConfirmations, 0);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.confirmBeforeApprovals);
    });

    test('lowering the protection asks for a confirmation first', () async {
      final ProviderContainer container = createContainer(.confirmBeforeApprovals, confirmed: true);

      final bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.standard, _NoInteraction());

      expect(changed, isTrue);
      expect(downgradeConfirmations, 1);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.standard);
    });

    test('a cancelled confirmation keeps the protection', () async {
      final ProviderContainer container = createContainer(.confirmBeforeApprovals, confirmed: false);

      final bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.standard, _NoInteraction());

      expect(changed, isFalse);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.confirmBeforeApprovals);
    });
  });

  group('confirmWithAppUnlockMethod', () {
    late int deviceConfirmations;

    /// Returns a container whose app unlock method is [unlockMethod] and whose device prompt answers [deviceConfirmed].
    ProviderContainer createContainer(_FixedUnlockMethod unlockMethod, {bool deviceConfirmed = true}) {
      deviceConfirmations = 0;
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appUnlockMethodSettingsEntryProvider.overrideWith(() => unlockMethod),
          ezkeyDeviceConfirmationProvider.overrideWithValue(({required title, required reason}) async {
            deviceConfirmations++;
            return deviceConfirmed;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(appUnlockMethodSettingsEntryProvider, (_, _) {});
      return container;
    }

    test('asks for the master password as a sensitive action when the app uses it', () async {
      final _FixedUnlockMethod unlockMethod = _FixedUnlockMethod(MasterPasswordAppUnlockMethod.kMethodId, const ResultSuccess(value: 'password'));
      final ProviderContainer container = createContainer(unlockMethod);

      final bool confirmed = await container.read(ezkeyApprovalConfirmationProvider)(_NoInteraction());

      expect(confirmed, isTrue);
      expect(unlockMethod.reasons, [UnlockReason.sensibleAction]);
      expect(deviceConfirmations, 0);
    });

    test('a wrong or cancelled app unlock refuses the confirmation', () async {
      final _FixedUnlockMethod unlockMethod = _FixedUnlockMethod(LocalAuthenticationAppUnlockMethod.kMethodId, const ResultCancelled());
      final ProviderContainer container = createContainer(unlockMethod);

      final bool approval = await container.read(ezkeyApprovalConfirmationProvider)(_NoInteraction());
      final bool downgrade = await container.read(ezkeyDowngradeConfirmationProvider)(_NoInteraction());

      expect(approval, isFalse);
      expect(downgrade, isFalse);
      expect(unlockMethod.reasons, [UnlockReason.sensibleAction, UnlockReason.sensibleAction]);
    });

    test('asks for the device credential when the app has no unlock method', () async {
      final _FixedUnlockMethod unlockMethod = _FixedUnlockMethod(NoneAppUnlockMethod.kMethodId, const ResultSuccess());
      final ProviderContainer container = createContainer(unlockMethod, deviceConfirmed: false);

      final bool confirmed = await container.read(ezkeyApprovalConfirmationProvider)(_NoInteraction());

      expect(confirmed, isFalse);
      expect(deviceConfirmations, 1);
      expect(unlockMethod.reasons, isEmpty);
    });
  });

  group('EzkeyDeviceConfirmation', () {
    late _FakeWindow window;
    late int prompts;

    /// Returns a confirmation on [promptWindow] whose prompt runs [answer].
    EzkeyDeviceConfirmation createConfirmation(Future<bool> Function() answer, {_FakeWindow? promptWindow, bool refocus = true}) {
      prompts = 0;
      return EzkeyDeviceConfirmation(
        window: () => promptWindow,
        refocusAfterPrompt: refocus,
        prompt: ({required title, required reason}) {
          prompts++;
          promptWindow?.calls.add('prompt');
          return answer();
        },
      );
    }

    setUp(() => window = _FakeWindow());

    test('without a window (mobile), only the prompt runs', () async {
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => true);

      final bool confirmed = await confirmation(title: 'Title', reason: 'Reason');

      expect(confirmed, isTrue);
      expect(prompts, 1);
    });

    test('keeps the window in front during the prompt, then restores it and refocuses it', () async {
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => true, promptWindow: window);

      final bool confirmed = await confirmation(title: 'Title', reason: 'Reason');

      expect(confirmed, isTrue);
      expect(window.calls, ['focus', 'onTop:true', 'prompt', 'onTop:false', 'blur', 'focus']);
      expect(window.isAlwaysOnTop, isFalse);
    });

    test('a window already on top stays on top', () async {
      window.isAlwaysOnTop = true;
      window.calls.clear();
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => true, promptWindow: window);

      await confirmation(title: 'Title', reason: 'Reason');

      expect(window.isAlwaysOnTop, isTrue);
    });

    test('restores the window after a cancelled prompt', () async {
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => false, promptWindow: window);

      final bool confirmed = await confirmation(title: 'Title', reason: 'Reason');

      expect(confirmed, isFalse);
      expect(window.calls, ['focus', 'onTop:true', 'prompt', 'onTop:false', 'blur', 'focus']);
    });

    test('restores the window when the prompt throws', () async {
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => throw StateError('prompt failed'), promptWindow: window);

      await expectLater(confirmation(title: 'Title', reason: 'Reason'), throwsStateError);

      expect(window.calls, ['focus', 'onTop:true', 'prompt', 'onTop:false', 'blur', 'focus']);
    });

    test('does not refocus where the platform does not need it', () async {
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => true, promptWindow: window, refocus: false);

      await confirmation(title: 'Title', reason: 'Reason');

      expect(window.calls, ['focus', 'onTop:true', 'prompt', 'onTop:false']);
    });

    test('refuses a second confirmation while a prompt is open', () async {
      final Completer<bool> answer = Completer<bool>();
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() => answer.future, promptWindow: window);

      final Future<bool> first = confirmation(title: 'Title', reason: 'Reason');
      final bool second = await confirmation(title: 'Title', reason: 'Reason');
      answer.complete(true);

      expect(second, isFalse);
      expect(await first, isTrue);
      expect(prompts, 1);
    });

    test('accepts a new confirmation once the prompt is closed, even after an error', () async {
      final EzkeyDeviceConfirmation confirmation = createConfirmation(() async => throw StateError('prompt failed'), promptWindow: window);
      await expectLater(confirmation(title: 'Title', reason: 'Reason'), throwsStateError);

      await expectLater(confirmation(title: 'Title', reason: 'Reason'), throwsStateError);

      expect(prompts, 2);
    });
  });
}

/// A window that records the operations made on it, in order.
class _FakeWindow implements EzkeyPromptWindow {
  /// The operations, in order.
  final List<String> calls = [];

  /// The current always-on-top state.
  bool _isAlwaysOnTop = false;

  @override
  bool get isAlwaysOnTop => _isAlwaysOnTop;

  @override
  set isAlwaysOnTop(bool value) {
    calls.add('onTop:$value');
    _isAlwaysOnTop = value;
  }

  @override
  void focus() => calls.add('focus');

  @override
  void blur() => calls.add('blur');
}
