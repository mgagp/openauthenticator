import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/model/app_unlock/interaction.dart';
import 'package:open_authenticator/model/app_unlock/methods/method.dart';
import 'package:open_authenticator/model/app_unlock/reason.dart';
import 'package:open_authenticator/model/settings/app_unlock_method.dart';
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
      ProviderContainer container = ProviderContainer(
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
      ProviderContainer container = createContainer(.standard, confirmed: false);

      bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.confirmBeforeApprovals, _NoInteraction());

      expect(changed, isTrue);
      expect(downgradeConfirmations, 0);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.confirmBeforeApprovals);
    });

    test('lowering the protection asks for a confirmation first', () async {
      ProviderContainer container = createContainer(.confirmBeforeApprovals, confirmed: true);

      bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.standard, _NoInteraction());

      expect(changed, isTrue);
      expect(downgradeConfirmations, 1);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.standard);
    });

    test('a cancelled confirmation keeps the protection', () async {
      ProviderContainer container = createContainer(.confirmBeforeApprovals, confirmed: false);

      bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.standard, _NoInteraction());

      expect(changed, isFalse);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.confirmBeforeApprovals);
    });
  });

  group('confirmWithAppUnlockMethod', () {
    late int deviceConfirmations;

    /// Returns a container whose app unlock method is [unlockMethod] and whose device prompt answers [deviceConfirmed].
    ProviderContainer createContainer(_FixedUnlockMethod unlockMethod, {bool deviceConfirmed = true}) {
      deviceConfirmations = 0;
      ProviderContainer container = ProviderContainer(
        overrides: [
          appUnlockMethodSettingsEntryProvider.overrideWith(() => unlockMethod),
          ezkeyDeviceConfirmationProvider.overrideWithValue(({required String title, required String reason}) async {
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
      _FixedUnlockMethod unlockMethod = _FixedUnlockMethod(MasterPasswordAppUnlockMethod.kMethodId, const ResultSuccess(value: 'password'));
      ProviderContainer container = createContainer(unlockMethod);

      bool confirmed = await container.read(ezkeyApprovalConfirmationProvider)(_NoInteraction());

      expect(confirmed, isTrue);
      expect(unlockMethod.reasons, [UnlockReason.sensibleAction]);
      expect(deviceConfirmations, 0);
    });

    test('a wrong or cancelled app unlock refuses the confirmation', () async {
      _FixedUnlockMethod unlockMethod = _FixedUnlockMethod(LocalAuthenticationAppUnlockMethod.kMethodId, const ResultCancelled());
      ProviderContainer container = createContainer(unlockMethod);

      bool approval = await container.read(ezkeyApprovalConfirmationProvider)(_NoInteraction());
      bool downgrade = await container.read(ezkeyDowngradeConfirmationProvider)(_NoInteraction());

      expect(approval, isFalse);
      expect(downgrade, isFalse);
      expect(unlockMethod.reasons, [UnlockReason.sensibleAction, UnlockReason.sensibleAction]);
    });

    test('asks for the device credential when the app has no unlock method', () async {
      _FixedUnlockMethod unlockMethod = _FixedUnlockMethod(NoneAppUnlockMethod.kMethodId, const ResultSuccess());
      ProviderContainer container = createContainer(unlockMethod, deviceConfirmed: false);

      bool confirmed = await container.read(ezkeyApprovalConfirmationProvider)(_NoInteraction());

      expect(confirmed, isFalse);
      expect(deviceConfirmations, 1);
      expect(unlockMethod.reasons, isEmpty);
    });
  });
}
