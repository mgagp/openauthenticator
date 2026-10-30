import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/home_zone.dart';
import 'package:open_authenticator/ezkey/home_zone_state.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/utils/platform.dart';

import 'support.dart';

/// Serves a fixed enrollment list instead of the device stores.
class _FixedEnrollments extends EzkeyEnrollmentsNotifier {
  /// The enrollments to serve.
  final List<EzkeyEnrollment> enrollments;

  /// Creates a new fixed enrollments notifier instance.
  _FixedEnrollments(this.enrollments);

  @override
  FutureOr<List<EzkeyEnrollment>> build() => enrollments;
}

/// Keeps the zone state in memory instead of the shared preferences.
class _MemoryZoneState extends EzkeyHomeZoneStateEntry {
  /// The initial state.
  final EzkeyHomeZoneState initial;

  /// Creates a new memory zone state instance.
  _MemoryZoneState(this.initial);

  @override
  FutureOr<EzkeyHomeZoneState> build() => initial;

  @override
  Future<void> changeValue(EzkeyHomeZoneState value) async => state = AsyncData(value);
}

void main() {
  /// Shows the EzKey zone with [enrollments].
  Future<void> pumpZone(WidgetTester tester, List<EzkeyEnrollment> enrollments) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyEnrollmentsProvider.overrideWith(() => _FixedEnrollments(enrollments)),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: child!,
            ),
            home: const Scaffold(body: EzkeyHomeZone()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EzkeyHomeZone', () {
    testWidgets('without enrollment, invites to add one and offers no check', (tester) async {
      await pumpZone(tester, []);

      expect(find.text(translations.ezkey.home.empty), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-check')), findsNothing);
    });

    testWidgets('lists the enrollments and offers to check for requests', (tester) async {
      await pumpZone(tester, [
        testEnrollment(1, integrationName: 'Internal Tools'),
        testEnrollment(2, integrationName: 'Administration', authApiBaseUrl: 'https://other.example'),
      ]);

      expect(find.text('Internal Tools'), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-check')), findsOneWidget);
      expect(find.text(translations.ezkey.home.empty), findsNothing);
    });

    testWidgets('the add button offers to scan or type an invitation', (tester) async {
      await pumpZone(tester, []);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ezkey-home-add-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-add-paste')), findsOneWidget);
    });

    testWidgets('the info button tells what EzKey is and links to its website and source code', (tester) async {
      await pumpZone(tester, []);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-about')));
      await tester.pumpAndSettle();

      expect(find.text(translations.ezkey.about.description), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-about-website')), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-about-source')), findsOneWidget);
    });
  });

  group('EzkeyHomeZones', () {
    /// Shows both zones with [enrollments] and the zone [state].
    Future<void> pumpZones(WidgetTester tester, List<EzkeyEnrollment> enrollments, {EzkeyHomeZoneState state = .auto}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ezkeyEnrollmentsProvider.overrideWith(() => _FixedEnrollments(enrollments)),
            ezkeyHomeZoneStateProvider.overrideWith(() => _MemoryZoneState(state)),
          ],
          child: TranslationProvider(
            child: MaterialApp(
              builder: (context, child) => FTheme(
                data: greenTheme.light.touch,
                child: child!,
              ),
              home: const Scaffold(body: EzkeyHomeZones(totpZone: Text('totp'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is collapsed to a bar while there is no enrollment', (tester) async {
      await pumpZones(tester, []);

      expect(find.byKey(const ValueKey('ezkey-home-expand')), findsOneWidget);
      expect(find.byType(EzkeyHomeZone), findsNothing);
      expect(find.text('totp'), findsOneWidget);
    });

    testWidgets('is expanded once there is an enrollment', (tester) async {
      await pumpZones(tester, [testEnrollment(1)]);

      expect(find.byType(EzkeyHomeZone), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-expand')), findsNothing);
    });

    testWidgets('a remembered choice wins over the default', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], state: .collapsed);

      expect(find.byType(EzkeyHomeZone), findsNothing);
    });

    testWidgets('collapses and expands on tap', (tester) async {
      await pumpZones(tester, [testEnrollment(1)]);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-collapse')));
      await tester.pumpAndSettle();

      expect(find.byType(EzkeyHomeZone), findsNothing);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-expand')));
      await tester.pumpAndSettle();

      expect(find.byType(EzkeyHomeZone), findsOneWidget);
    });
  });

  group('ezkeyHomeZones', () {
    late Platform platform;

    setUp(() => platform = currentPlatform);

    tearDown(() => currentPlatform = platform);

    test('adds the EzKey zone on Android', () {
      currentPlatform = .android;
      const Widget totpZone = SizedBox();

      List<Widget> children = ezkeyHomeZones([totpZone]);

      expect(children.single, isA<EzkeyHomeZones>());
      expect((children.single as EzkeyHomeZones).totpZone, same(totpZone));
    });

    test('keeps the upstream content unchanged off Android', () {
      currentPlatform = .windows;
      List<Widget> totpChildren = [const SizedBox()];

      expect(ezkeyHomeZones(totpChildren), same(totpChildren));
    });
  });
}
