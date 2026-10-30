import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';

/// Serves no enrollment instead of the device stores.
class _NoEnrollments extends EzkeyEnrollmentsNotifier {
  @override
  FutureOr<List<EzkeyEnrollment>> build() => [];
}

void main() {
  late bool manualEntry;

  setUp(() => manualEntry = ezkeyManualInvitationEntry);

  tearDown(() => ezkeyManualInvitationEntry = manualEntry);

  /// Shows the EzKey page.
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyEnrollmentsProvider.overrideWith(_NoEnrollments.new),
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
  });
}
