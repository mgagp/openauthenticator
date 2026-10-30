import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';

/// The invitation QR code content, from `scripts/ezkey_lab.dart e2e`.
const String _enrollmentCode = String.fromEnvironment('EZKEY_LAB_ENROLLMENT_CODE');

/// The 6-digit enrollment code of the same invitation.
const String _enrollmentChallenge = String.fromEnvironment('EZKEY_LAB_ENROLLMENT_CHALLENGE');

/// The Auth API as seen from the device.
const String _authApiBaseUrl = String.fromEnvironment('EZKEY_LAB_AUTH_URL', defaultValue: 'http://10.0.2.2:8080');

/// Goes through the enrollment screens against a live local EzKey stack, then approves one auth
/// attempt through the approval screen and removes the enrollment from the list. Driven by
/// `scripts/ezkey_lab.dart e2e --test integration_test/ezkey/enrollment_ui_test.dart`, which takes a
/// screenshot at each `EZKEY_LAB_SCREEN` line.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'enrolls through the EzKey screens',
    (tester) async {
      // The emulator has no screen lock to confirm with; the Pixel pilot covers the real prompt.
      ProviderContainer container = ProviderContainer(
        overrides: [
          ezkeyApprovalConfirmationProvider.overrideWithValue(() async => true),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TranslationProvider(
            child: MaterialApp(
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocaleUtils.supportedLocales,
              theme: greenTheme.light.touch.toApproximateMaterialTheme(),
              builder: (context, child) => FTheme(
                data: greenTheme.light.touch,
                child: FToaster(child: child!),
              ),
              home: const EzkeyPage(),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _screen(tester, '1-empty');

      await tester.tap(find.byKey(const ValueKey('ezkey-add-paste')));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText), _enrollmentCode);
      await _settle(tester);
      await _screen(tester, '2-invitation');
      await tester.tap(find.text('OK'));
      await _settle(tester);

      // Clean-start invitations carry no Auth API address: the app asks for it.
      expect(find.text(translations.ezkey.server.title), findsOneWidget);
      await tester.enterText(find.byType(EditableText), _authApiBaseUrl);
      await _settle(tester);
      await _screen(tester, '3-server');
      await tester.tap(find.text('OK'));
      await _settle(tester, until: find.byKey(const ValueKey('ezkey-enrollment-code')));

      expect(find.text('Open Authenticator Lab'), findsOneWidget);
      await _screen(tester, '4-confirm');
      await tester.enterText(find.byKey(const ValueKey('ezkey-enrollment-code')), _enrollmentChallenge);
      await _settle(tester);
      await _screen(tester, '5-code');
      // The page is a lazy list: with the keyboard open, the button is not built until scrolled to.
      Finder submit = find.byKey(const ValueKey('ezkey-enroll-submit'));
      await tester.scrollUntilVisible(submit, 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(submit);
      await _settle(tester, until: find.text(translations.ezkey.page.enrollments));
      await _screen(tester, '6-enrolled');

      List<EzkeyEnrollment> enrollments = await container.read(ezkeyEnrollmentsProvider.future);
      EzkeyEnrollment enrollment = enrollments.single;
      // ignore: avoid_print
      print('EZKEY_LAB enrolled id=${enrollment.enrollmentId} integration=${enrollment.integrationName} tier=${enrollment.devicePrivateKeyStorageTier.name}');

      // The lab script creates the auth attempt once the enrollment is VERIFIED: check until it shows up.
      Finder approve = find.byKey(const ValueKey('ezkey-attempt-approve'));
      DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
      while (approve.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.tap(find.byKey(const ValueKey('ezkey-check-pending')));
        await _settle(tester, until: approve, timeout: const Duration(seconds: 5));
      }
      expect(approve, findsOneWidget, reason: 'no auth attempt arrived');
      expect(find.text('Sign in to Open Authenticator Lab'), findsOneWidget);
      await _screen(tester, '7-attempt');
      await tester.tap(approve);
      await _settle(tester, until: find.text(translations.ezkey.attempt.result.approved));
      expect(find.text(translations.ezkey.attempt.result.approved), findsOneWidget);
      await _screen(tester, '8-approved');

      // Removal lives on the enrollment's own page (#33).
      await tester.tap(find.text('Open Authenticator Lab'));
      await _settle(tester, until: find.byKey(const ValueKey('ezkey-enrollment-forget')));
      await tester.tap(find.byKey(const ValueKey('ezkey-enrollment-forget')));
      await _settle(tester);
      await _screen(tester, '9-forget');
      await tester.tap(find.text('OK'));
      await _settle(tester, until: find.text(translations.ezkey.page.empty));
      await _screen(tester, '10-forgotten');
      expect(await container.read(ezkeyEnrollmentsProvider.future), isEmpty);
    },
    // With semantics on, the framework asserts in the forui tile group / dialog tree
    // ('node.isMergedIntoParent'), then taps hit stale tappables. Accessibility follow-up noted in #20.
    semanticsEnabled: false,
    skip: _enrollmentCode.isEmpty,
  );
}

/// Pumps frames for real time (network calls run on the real clock), until [until] shows up when given.
Future<void> _settle(WidgetTester tester, {Finder? until, Duration timeout = const Duration(seconds: 30)}) async {
  DateTime deadline = DateTime.now().add(timeout);
  do {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 100));
  } while (until != null && until.evaluate().isEmpty && DateTime.now().isBefore(deadline));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Asks the lab script for a screenshot, and holds the screen while it is taken.
Future<void> _screen(WidgetTester tester, String name) async {
  // ignore: avoid_print
  print('EZKEY_LAB_SCREEN $name');
  await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
  await tester.pump();
}
