import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';

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
          ezkeyDowngradeConfirmationProvider.overrideWithValue(() async {
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

      bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.confirmBeforeApprovals);

      expect(changed, isTrue);
      expect(downgradeConfirmations, 0);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.confirmBeforeApprovals);
    });

    test('lowering the protection asks for the device credential first', () async {
      ProviderContainer container = createContainer(.confirmBeforeApprovals, confirmed: true);

      bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.standard);

      expect(changed, isTrue);
      expect(downgradeConfirmations, 1);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.standard);
    });

    test('a cancelled confirmation keeps the protection', () async {
      ProviderContainer container = createContainer(.confirmBeforeApprovals, confirmed: false);

      bool changed = await container.read(ezkeyApprovalSecurityProvider.notifier).change(.standard);

      expect(changed, isFalse);
      expect(container.read(ezkeyApprovalSecurityProvider).value, EzkeyApprovalSecurity.confirmBeforeApprovals);
    });
  });
}
