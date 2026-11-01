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
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/model/totp/decrypted.dart';
import 'package:open_authenticator/model/totp/repository.dart';
import 'package:open_authenticator/model/totp/totp.dart';
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

/// A TOTP repository that holds a fixed list, without the database.
class _FixedTotps extends TotpRepository {
  /// The TOTPs.
  final List<Totp> totps;

  /// Creates a new fixed TOTP repository instance.
  _FixedTotps(this.totps);

  @override
  FutureOr<List<Totp>> build() => totps;
}

/// Stands for the upstream content: a counter that tells whether its state survived.
class _CounterZone extends StatefulWidget {
  /// Creates a new counter zone instance.
  const _CounterZone();

  @override
  State<_CounterZone> createState() => _CounterZoneState();
}

/// The counter zone state.
class _CounterZoneState extends State<_CounterZone> {
  /// The number of taps.
  int count = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('totp $count'),
  );
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

  group('EzkeyHomeZoneState', () {
    test('never collapses both zones', () {
      for (EzkeyHomeZoneState state in EzkeyHomeZoneState.values) {
        for (bool hasEnrollments in [false, true]) {
          expect(state.isTotpExpanded || state.isExpanded(hasEnrollments: hasEnrollments), isTrue, reason: '$state, hasEnrollments: $hasEnrollments');
        }
      }
    });

    test('collapsing the TOTP zone expands EzKey, even without enrollments', () {
      expect(EzkeyHomeZoneState.totpCollapsed.isTotpExpanded, isFalse);
      expect(EzkeyHomeZoneState.totpCollapsed.isExpanded(hasEnrollments: false), isTrue);
    });

    test('the TOTP zone is expanded by default', () {
      expect(EzkeyHomeZoneState.auto.isTotpExpanded, isTrue);
    });
  });

  group('EzkeyHomeZones', () {
    late CryptoStore cryptoStore;

    setUpAll(() => cryptoStore = CryptoStore.fromPassword('password', Salt.generate()));

    /// Shows both zones with [enrollments], [totpCount] TOTPs, the zone [state] and [totpZone].
    Future<void> pumpZones(
      WidgetTester tester,
      List<EzkeyEnrollment> enrollments, {
      EzkeyHomeZoneState state = .auto,
      int totpCount = 0,
      Widget totpZone = const Text('totp'),
    }) async {
      List<Totp> totps = [
        for (int i = 0; i < totpCount; i++) DecryptedTotp.create(cryptoStore: cryptoStore, uuid: 'uuid-$i', secret: 'JBSWY3DPEHPK3PXP', label: 'totp-$i')!,
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ezkeyEnrollmentsProvider.overrideWith(() => _FixedEnrollments(enrollments)),
            ezkeyHomeZoneStateProvider.overrideWith(() => _MemoryZoneState(state)),
            totpRepositoryProvider.overrideWith(() => _FixedTotps(totps)),
          ],
          child: TranslationProvider(
            child: MaterialApp(
              builder: (context, child) => FTheme(
                data: greenTheme.light.touch,
                child: child!,
              ),
              home: Scaffold(body: EzkeyHomeZones(totpZone: totpZone)),
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

    testWidgets('shows no TOTP header while EzKey is collapsed, so the app looks like the original', (tester) async {
      await pumpZones(tester, []);

      expect(find.byKey(const ValueKey('ezkey-home-totp-collapse')), findsNothing);
      expect(find.byKey(const ValueKey('ezkey-home-totp-expand')), findsNothing);
    });

    testWidgets('collapsing the TOTP zone hides the upstream content and gives EzKey the full height', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], totpCount: 2);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-totp-collapse')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ezkey-home-totp-expand')), findsOneWidget);
      expect(find.text(translations.ezkey.home.totpCount(n: 2)), findsOneWidget);
      expect(find.text('totp'), findsNothing);
      expect(find.text('totp', skipOffstage: false), findsOneWidget);
      expect(tester.widget<EzkeyHomeZone>(find.byType(EzkeyHomeZone)).fill, isTrue);
    });

    testWidgets('a full-height EzKey zone lets its list grow past the usual cap', (tester) async {
      await pumpZones(tester, [for (int i = 1; i <= 12; i++) testEnrollment(i)], state: .totpCollapsed);

      Finder list = find.descendant(of: find.byType(EzkeyHomeZone), matching: find.byType(SingleChildScrollView));

      expect(tester.getSize(list).height, greaterThan(200));
    });

    testWidgets('expanding the TOTP zone brings the upstream content back with its state', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], totpZone: const _CounterZone());
      await tester.tap(find.text('totp 0'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ezkey-home-totp-collapse')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ezkey-home-totp-expand')));
      await tester.pumpAndSettle();

      expect(find.text('totp 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-totp-expand')), findsNothing);
      expect(tester.widget<EzkeyHomeZone>(find.byType(EzkeyHomeZone)).fill, isFalse);
    });

    testWidgets('collapsing EzKey while the TOTP zone is collapsed expands the TOTP zone', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], state: .totpCollapsed);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-collapse')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ezkey-home-expand')), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-totp-expand')), findsNothing);
      expect(find.text('totp'), findsOneWidget);
    });

    testWidgets('a remembered collapsed TOTP zone stays collapsed, even without enrollments', (tester) async {
      await pumpZones(tester, [], state: .totpCollapsed, totpCount: 1);

      expect(find.byKey(const ValueKey('ezkey-home-totp-expand')), findsOneWidget);
      expect(find.text(translations.ezkey.home.totpCount(n: 1)), findsOneWidget);
      expect(find.text(translations.ezkey.home.empty), findsOneWidget);
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
