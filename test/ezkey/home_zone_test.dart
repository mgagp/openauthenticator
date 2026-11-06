import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/ezkey/enrollment_store.dart';
import 'package:open_authenticator/ezkey/home_zone.dart';
import 'package:open_authenticator/ezkey/home_zone_state.dart';
import 'package:open_authenticator/ezkey/local_confirmation.dart';
import 'package:open_authenticator/ezkey/pages/enrollment_page.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/to_reenroll.dart';
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

/// Keeps the zone split in memory instead of the shared preferences.
class _MemorySplit extends EzkeyHomeZoneSplitEntry {
  /// The initial share.
  final double initial;

  /// Creates a new memory split instance.
  _MemorySplit(this.initial);

  @override
  FutureOr<double> build() => initial;

  @override
  Future<void> changeValue(double value) async => state = AsyncData(value);
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

/// Records the pending checks and answers that nothing is waiting, or with [error].
class _RecordingAuthApi implements EzkeyAuthApi {
  /// The enrollment ids checked, in order.
  final List<int> checked = [];

  /// What to fail with, if anything.
  EzkeyException? error;

  @override
  Future<PendingAuthResponse?> pending(PendingAuthRequest request) async {
    checked.add(request.enrollmentId);
    if (error != null) {
      throw error!;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Keeps the approval protection in memory instead of the shared preferences.
class _StandardSecurity extends EzkeyApprovalSecurityEntry {
  @override
  FutureOr<EzkeyApprovalSecurity> build() => EzkeyApprovalSecurity.standard;
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
  /// Returns a secure storage holding [count] enrollments to re-enroll.
  Future<InMemorySecureValues> valuesToReenroll(int count) async {
    InMemorySecureValues values = InMemorySecureValues();
    await EzkeyToReenrollStore(values).write([
      for (int i = 0; i < count; i++) EzkeyInventoryEntry(enrollmentId: i, authApiHost: 'auth.orbit.example', enrolledAt: DateTime.utc(2026, 10, 27), integrationName: 'Service $i'),
    ]);
    return values;
  }

  /// Shows the EzKey zone with [enrollments] and [toReenroll] enrollments to re-enroll, checking through
  /// [authenticator] when given.
  Future<void> pumpZone(WidgetTester tester, List<EzkeyEnrollment> enrollments, {int toReenroll = 0, EzkeyAuthenticator? authenticator}) async {
    InMemorySecureValues values = await valuesToReenroll(toReenroll);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyEnrollmentsProvider.overrideWith(() => _FixedEnrollments(enrollments)),
          ezkeyEnrollmentStoreProvider.overrideWith((ref) async => SecureEzkeyEnrollmentStore(values)),
          ezkeyApprovalSecurityProvider.overrideWith(_StandardSecurity.new),
          if (authenticator != null) ezkeyAuthenticatorProvider.overrideWith((ref) async => authenticator),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
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
      expect(find.text(translations.ezkey.home.check), findsNothing);
    });

    testWidgets('mentions nothing to re-enroll while the list is empty', (tester) async {
      await pumpZone(tester, []);

      expect(find.byKey(const ValueKey('ezkey-home-to-reenroll')), findsNothing);
    });

    testWidgets('after a restore, says how many to re-enroll and leads to the EzKey page', (tester) async {
      await pumpZone(tester, [], toReenroll: 2);

      expect(find.text(translations.ezkey.home.toReenroll(n: 2)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ezkey-home-to-reenroll')));
      await tester.pumpAndSettle();

      expect(find.byType(EzkeyPage), findsOneWidget);
      expect(find.text('Service 1'), findsOneWidget);
    });

    testWidgets('lists the enrollments, each with its own check', (tester) async {
      await pumpZone(tester, [
        testEnrollment(1, integrationName: 'Internal Tools'),
        testEnrollment(2, integrationName: 'Administration', authApiBaseUrl: 'https://other.example'),
      ]);

      expect(find.text('Internal Tools'), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);
      expect(find.text(translations.ezkey.home.check), findsNWidgets(2));
      expect(find.text(translations.ezkey.home.empty), findsNothing);
    });

    group('checking for requests', () {
      late _RecordingAuthApi api;
      late List<EzkeyEnrollment> enrollments;
      late EzkeyAuthenticator authenticator;

      setUp(() async {
        api = _RecordingAuthApi();
        SoftwareDeviceKeyStore keyStore = SoftwareDeviceKeyStore();
        await keyStore.generateKeyPair('key-1');
        await keyStore.generateKeyPair('key-2');
        enrollments = [
          testEnrollment(1, deviceKeyAlias: 'key-1', integrationName: 'Internal Tools'),
          testEnrollment(2, deviceKeyAlias: 'key-2', integrationName: 'Payroll'),
        ];
        InMemoryEnrollmentStore store = InMemoryEnrollmentStore();
        for (EzkeyEnrollment enrollment in enrollments) {
          await store.save(enrollment);
        }
        authenticator = EzkeyAuthenticator(keyStore: keyStore, enrollmentStore: store, apiFactory: (uri) => api);
      });

      /// Finds the check button of [enrollment].
      Finder check(EzkeyEnrollment enrollment) => find.byKey(ValueKey('ezkey-home-check-${enrollment.localId}'));

      testWidgets('a row\'s button checks that enrollment only', (tester) async {
        await pumpZone(tester, enrollments, authenticator: authenticator);

        await tester.tap(check(enrollments[1]));
        await tester.pumpAndSettle();

        expect(api.checked, [2]);
        expect(find.text(translations.ezkey.attempt.check.none), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
      });

      testWidgets('a failing server reports an error and leaves the other enrollments alone', (tester) async {
        api.error = const EzkeyNetworkException('unreachable');
        await pumpZone(tester, enrollments, authenticator: authenticator);

        await tester.tap(check(enrollments[0]));
        await tester.pumpAndSettle();

        expect(api.checked, [1]);
        expect(find.text(translations.ezkey.error.network), findsOneWidget);
        expect(find.text(translations.ezkey.attempt.check.none), findsNothing);
        await tester.pump(const Duration(seconds: 10));
      });

      testWidgets('the rest of the row opens the enrollment page and checks nothing', (tester) async {
        await pumpZone(tester, enrollments, authenticator: authenticator);

        await tester.tap(find.text('Internal Tools'));
        await tester.pumpAndSettle();

        expect(find.byType(EzkeyEnrollmentPage), findsOneWidget);
        expect(api.checked, isEmpty);
      });

      testWidgets('a screen reader tells the buttons apart and can press them', (tester) async {
        await pumpZone(tester, enrollments, authenticator: authenticator);

        tester.semantics.tap(find.semantics.byLabel(translations.ezkey.home.checkAction(integration: 'Payroll')));
        await tester.pumpAndSettle();

        expect(api.checked, [2]);
        await tester.pump(const Duration(seconds: 10));
      });
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
    late _MemorySplit split;

    setUpAll(() => cryptoStore = CryptoStore.fromPassword('password', Salt.generate()));

    /// Shows both zones with [enrollments], [toReenroll] enrollments to re-enroll, [totpCount] TOTPs, the
    /// zone [state] and [totpZone].
    Future<void> pumpZones(
      WidgetTester tester,
      List<EzkeyEnrollment> enrollments, {
      EzkeyHomeZoneState state = .auto,
      int totpCount = 0,
      Widget totpZone = const Text('totp'),
      double share = 0,
      int toReenroll = 0,
    }) async {
      InMemorySecureValues values = await valuesToReenroll(toReenroll);
      List<Totp> totps = [
        for (int i = 0; i < totpCount; i++) DecryptedTotp.create(cryptoStore: cryptoStore, uuid: 'uuid-$i', secret: 'JBSWY3DPEHPK3PXP', label: 'totp-$i')!,
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ezkeyEnrollmentsProvider.overrideWith(() => _FixedEnrollments(enrollments)),
            ezkeyEnrollmentStoreProvider.overrideWith((ref) async => SecureEzkeyEnrollmentStore(values)),
            ezkeyHomeZoneStateProvider.overrideWith(() => _MemoryZoneState(state)),
            totpRepositoryProvider.overrideWith(() => _FixedTotps(totps)),
            ezkeyHomeZoneSplitProvider.overrideWith(() => split = _MemorySplit(share)),
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

    testWidgets('is expanded while there is something to re-enroll, even without enrollment', (tester) async {
      await pumpZones(tester, [], toReenroll: 1);

      expect(find.byType(EzkeyHomeZone), findsOneWidget);
      expect(find.byKey(const ValueKey('ezkey-home-to-reenroll')), findsOneWidget);
    });

    testWidgets('stays collapsed if the user chose so, and the bar still says how many to re-enroll', (tester) async {
      await pumpZones(tester, [], state: .collapsed, toReenroll: 2);

      expect(find.byType(EzkeyHomeZone), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('ezkey-home-expand')), matching: find.text(translations.ezkey.home.toReenroll(n: 2))), findsOneWidget);
    });

    testWidgets('the collapsed bar mentions nothing while the list is empty', (tester) async {
      await pumpZones(tester, []);

      expect(find.textContaining(translations.ezkey.home.toReenroll(n: 0)), findsNothing);
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

    /// The divider between the zones.
    Finder divider() => find.byKey(const ValueKey('ezkey-home-split'));

    /// The height of the EzKey zone.
    double ezkeyHeight(WidgetTester tester) => tester.getSize(find.byType(EzkeyHomeZone)).height;

    testWidgets('shows the divider only while both zones are expanded', (tester) async {
      await pumpZones(tester, [testEnrollment(1)]);

      expect(divider(), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-collapse')));
      await tester.pumpAndSettle();

      expect(divider(), findsNothing);

      await tester.tap(find.byKey(const ValueKey('ezkey-home-expand')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ezkey-home-totp-collapse')));
      await tester.pumpAndSettle();

      expect(divider(), findsNothing);
    });

    testWidgets('lets the EzKey zone take the height it needs until the divider is moved', (tester) async {
      await pumpZones(tester, [testEnrollment(1)]);

      expect(tester.widget<EzkeyHomeZone>(find.byType(EzkeyHomeZone)).fill, isFalse);
    });

    testWidgets('dragging the divider up gives EzKey more height, and remembers it', (tester) async {
      await pumpZones(tester, [testEnrollment(1)]);
      double before = ezkeyHeight(tester);

      await tester.drag(divider(), const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(ezkeyHeight(tester), greaterThan(before + 100));
      expect(split.state.value, greaterThan(0));
      expect(tester.widget<EzkeyHomeZone>(find.byType(EzkeyHomeZone)).fill, isTrue);
    });

    testWidgets('the divider stops at the limits, so neither zone gets too small', (tester) async {
      await pumpZones(tester, [testEnrollment(1)]);

      await tester.drag(divider(), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(split.state.value, lessThanOrEqualTo(EzkeyHomeZoneSplitEntry.maxShare));
      expect(tester.getSize(find.text('totp')).height, greaterThan(0));
      expect(tester.getTopLeft(divider()).dy, greaterThanOrEqualTo(160));

      await tester.drag(divider(), const Offset(0, 2000));
      await tester.pumpAndSettle();

      expect(split.state.value, greaterThanOrEqualTo(EzkeyHomeZoneSplitEntry.minShare));
      expect(ezkeyHeight(tester), greaterThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a remembered share sizes the zones', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], share: 0.45);
      double small = ezkeyHeight(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpZones(tester, [testEnrollment(1)], share: 0.7);

      expect(ezkeyHeight(tester), closeTo(small + 0.25 * (600 - 24), 1));
    });

    testWidgets('the smallest share still fits the mention with a long enrollment list', (tester) async {
      await pumpZones(tester, [for (int i = 1; i <= 12; i++) testEnrollment(i)], share: EzkeyHomeZoneSplitEntry.minShare, toReenroll: 3);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ezkey-home-to-reenroll')), findsOneWidget);
    });

    testWidgets('the smallest share still fits the mention without enrollment', (tester) async {
      await pumpZones(tester, [], state: .expanded, share: EzkeyHomeZoneSplitEntry.minShare, toReenroll: 3);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ezkey-home-to-reenroll')), findsOneWidget);
    });

    testWidgets('the smallest share still fits a long enrollment list', (tester) async {
      await pumpZones(tester, [for (int i = 1; i <= 12; i++) testEnrollment(i)], share: EzkeyHomeZoneSplitEntry.minShare);

      expect(tester.takeException(), isNull);
      expect(find.text(translations.ezkey.home.check), findsWidgets);
    });

    testWidgets('a double tap on the divider restores the automatic height', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], share: 0.6);

      await tester.tap(divider());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(divider());
      await tester.pumpAndSettle();

      expect(split.state.value, 0);
      expect(tester.widget<EzkeyHomeZone>(find.byType(EzkeyHomeZone)).fill, isFalse);
    });

    testWidgets('screen readers can adjust the divider', (tester) async {
      await pumpZones(tester, [testEnrollment(1)], share: 0.55);

      tester.semantics.increase(find.semantics.byLabel(translations.ezkey.home.split));
      await tester.pumpAndSettle();

      expect(split.state.value, closeTo(0.65, 0.001));

      tester.semantics.decrease(find.semantics.byLabel(translations.ezkey.home.split));
      await tester.pump();
      tester.semantics.decrease(find.semantics.byLabel(translations.ezkey.home.split));
      await tester.pumpAndSettle();

      expect(split.state.value, closeTo(0.45, 0.001));
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
