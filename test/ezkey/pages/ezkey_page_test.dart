import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/to_reenroll.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/widgets/dialog/confirmation_dialog.dart';

import '../support.dart';

/// Serves no enrollment instead of the device stores.
class _NoEnrollments extends EzkeyEnrollmentsNotifier {
  @override
  FutureOr<List<EzkeyEnrollment>> build() => [];
}

/// Keeps the approval protection in memory instead of the shared preferences.
class _StandardSecurity extends EzkeyApprovalSecurityEntry {
  @override
  FutureOr<EzkeyApprovalSecurity> build() => EzkeyApprovalSecurity.standard;
}

void main() {
  late bool manualEntry;
  late InMemorySecureValues values;

  setUp(() {
    manualEntry = ezkeyManualInvitationEntry;
    values = InMemorySecureValues();
  });

  tearDown(() => ezkeyManualInvitationEntry = manualEntry);

  /// Shows the EzKey page.
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyEnrollmentsProvider.overrideWith(_NoEnrollments.new),
          ezkeyEnrollmentStoreProvider.overrideWith((ref) async => SecureEzkeyEnrollmentStore(values)),
          ezkeyApprovalSecurityProvider.overrideWith(_StandardSecurity.new),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: child!,
            ),
            home: const EzkeyPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EzkeyPage', () {
    testWidgets('offers manual invitation entry when it is allowed (debug builds)', (tester) async {
      ezkeyManualInvitationEntry = true;

      await pumpPage(tester);

      expect(find.byKey(const ValueKey('ezkey-add-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-add-paste')), findsOneWidget);
    });

    testWidgets('only offers to scan when manual entry is not allowed (release builds)', (tester) async {
      ezkeyManualInvitationEntry = false;

      await pumpPage(tester);

      expect(find.byKey(const ValueKey('ezkey-add-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-add-paste')), findsNothing);
    });

    testWidgets('offers the approval confirmation setting, off by default', (tester) async {
      await pumpPage(tester);

      expect(find.text(translations.ezkey.security.confirm.title), findsOneWidget);
      expect(tester.widget<FCheckbox>(find.byType(FCheckbox)).value, isFalse);
    });

    testWidgets('shows no list to re-enroll when it is empty', (tester) async {
      await pumpPage(tester);

      expect(find.text(translations.ezkey.toReenroll.title), findsNothing);
    });

    group('with enrollments to re-enroll', () {
      setUp(() {
        EzkeyToReenrollStore(values).write([
          EzkeyInventoryEntry(
            enrollmentId: 3,
            authApiHost: 'auth.orbit.example',
            enrolledAt: DateTime.utc(2026, 10, 27, 12),
            integrationName: 'Orbit Console',
            tenantName: 'Orbit',
            enrollmentName: 'Alice Chen',
          ),
          EzkeyInventoryEntry(enrollmentId: 7, authApiHost: 'localhost:8080', enrolledAt: DateTime.utc(2026, 11, 2, 9, 30)),
        ]);
      });

      testWidgets('shows what the user and an administrator need to find each one', (tester) async {
        await pumpPage(tester);

        expect(find.text(translations.ezkey.toReenroll.title), findsOneWidget);
        expect(find.text(translations.ezkey.toReenroll.help), findsOneWidget);
        expect(find.text('Orbit Console'), findsOneWidget);
        expect(find.text('Orbit · Alice Chen'), findsOneWidget);
        expect(find.text('auth.orbit.example'), findsOneWidget);
        expect(find.textContaining(RegExp(r'2026.* ID 3$')), findsOneWidget);
        expect(find.text('localhost:8080'), findsOneWidget);
      });

      testWidgets('a screen reader finds each remove button by what it removes, and can activate it', (tester) async {
        await pumpPage(tester);

        expect(find.semantics.byLabel(translations.ezkey.toReenroll.remove.action(integration: 'localhost:8080')), findsOne);
        tester.semantics.tap(find.semantics.byLabel(translations.ezkey.toReenroll.remove.action(integration: 'Orbit Console')));
        await tester.pumpAndSettle();

        expect(find.text(translations.ezkey.toReenroll.remove.confirmTitle), findsOneWidget);
      });

      testWidgets('removes an entry once the user confirms, and keeps the others', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.byKey(const ValueKey('ezkey-to-reenroll-remove-3')));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(ConfirmationDialog), matching: find.text(MaterialLocalizations.of(tester.element(find.byType(ConfirmationDialog))).okButtonLabel)));
        await tester.pumpAndSettle();

        expect(find.text('Orbit Console'), findsNothing);
        expect(find.text('localhost:8080'), findsOneWidget);
        expect(EzkeyToReenrollStore(values).read().single.enrollmentId, 7);
      });

      testWidgets('keeps the entry when the user does not confirm', (tester) async {
        await pumpPage(tester);

        await tester.tap(find.byKey(const ValueKey('ezkey-to-reenroll-remove-3')));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(ConfirmationDialog), matching: find.text(MaterialLocalizations.of(tester.element(find.byType(ConfirmationDialog))).cancelButtonLabel)));
        await tester.pumpAndSettle();

        expect(find.text('Orbit Console'), findsOneWidget);
        expect(EzkeyToReenrollStore(values).read(), hasLength(2));
      });
    });
  });
}
