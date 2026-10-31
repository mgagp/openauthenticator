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
import 'package:open_authenticator/model/app_unlock/methods/method.dart';
import 'package:open_authenticator/model/app_unlock/state.dart';
import 'package:open_authenticator/model/backend/synchronization/queue.dart';
import 'package:open_authenticator/model/backend/synchronization/status.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/model/settings/display_copy_button.dart';
import 'package:open_authenticator/model/settings/display_search_button.dart';
import 'package:open_authenticator/model/settings/storage_type.dart';
import 'package:open_authenticator/model/totp/decrypted.dart';
import 'package:open_authenticator/model/totp/image_cache.dart';
import 'package:open_authenticator/model/totp/repository.dart';
import 'package:open_authenticator/model/totp/totp.dart';
import 'package:open_authenticator/pages/home/page.dart';
import 'package:open_authenticator/pages/scan.dart';
import 'package:open_authenticator/pages/totp.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/utils/platform.dart';

// Characterization tests (#55): they pin upstream's home page as it is today, before the EzKey work
// changes its structure (#44, #32). A red test after an upstream sync or an EzKey change means the
// behaviour moved: check whether that was intended.

/// A TOTP repository that holds a fixed list, without the database.
class _FixedTotps extends TotpRepository {
  /// The TOTPs.
  final List<Totp> totps;

  /// Creates a new fixed TOTP repository instance.
  _FixedTotps(this.totps);

  @override
  FutureOr<List<Totp>> build() => totps;
}

/// A crypto store notifier that holds a fixed store, without the secure storage.
class _FixedCryptoStore extends CryptoStoreNotifier {
  /// The store, or `null` for none.
  final CryptoStore? store;

  /// Creates a new fixed crypto store notifier instance.
  _FixedCryptoStore(this.store);

  @override
  FutureOr<CryptoStore?> build() => store;
}

/// An app lock state that is always unlocked.
class _Unlocked extends AppLockStateNotifier {
  @override
  FutureOr<AppLockState> build() => AppLockState.unlocked;
}

/// The search button setting, fixed to shown.
class _SearchButtonShown extends DisplaySearchButtonSettingsEntry {
  @override
  FutureOr<bool> build() => true;
}

/// The copy button setting, fixed to shown.
class _CopyButtonShown extends DisplayCopyButtonSettingsEntry {
  @override
  FutureOr<bool> build() => true;
}

/// The storage type, fixed to local only.
class _LocalOnly extends StorageTypeSettingsEntry {
  @override
  FutureOr<StorageType> build() => StorageType.localOnly;
}

/// A synchronization controller that stays idle.
class _IdleSync extends SynchronizationController {
  @override
  SynchronizationStatus build() => SynchronizationStatus();
}

/// No EzKey enrollment.
class _NoEnrollments extends EzkeyEnrollmentsNotifier {
  @override
  FutureOr<List<EzkeyEnrollment>> build() => const [];
}

/// The EzKey zone state, kept in memory.
class _ZoneState extends EzkeyHomeZoneStateEntry {
  @override
  FutureOr<EzkeyHomeZoneState> build() => EzkeyHomeZoneState.auto;
}

void main() {
  late Platform platform;
  late CryptoStore cryptoStore;
  late List<String> pushedRoutes;

  setUpAll(() => cryptoStore = CryptoStore.fromPassword('password', Salt.generate()));

  setUp(() {
    platform = currentPlatform;
    currentPlatform = .android;
    pushedRoutes = [];
  });

  tearDown(() => currentPlatform = platform);

  /// Returns a decrypted TOTP with [label] and [issuer].
  Totp totp(String label, {String? issuer}) => DecryptedTotp.create(
    cryptoStore: cryptoStore,
    uuid: 'uuid-$label',
    secret: 'JBSWY3DPEHPK3PXP',
    label: label,
    issuer: issuer,
  )!;

  /// Shows the home page over [totps], with [store] as the crypto store.
  Future<void> pumpHome(WidgetTester tester, List<Totp> totps, {bool withCryptoStore = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          totpRepositoryProvider.overrideWith(() => _FixedTotps(totps)),
          cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(withCryptoStore ? cryptoStore : null)),
          appLockStateProvider.overrideWith(_Unlocked.new),
          displaySearchButtonSettingsEntryProvider.overrideWith(_SearchButtonShown.new),
          displayCopyButtonSettingsEntryProvider.overrideWith(_CopyButtonShown.new),
          storageTypeSettingsEntryProvider.overrideWith(_LocalOnly.new),
          synchronizationControllerProvider.overrideWith(_IdleSync.new),
          pushOperationsErrorsProvider.overrideWith((ref) => Stream.value(const [])),
          totpResolvedImageProvider.overrideWith((ref, args) async => null),
          ezkeyEnrollmentsProvider.overrideWith(_NoEnrollments.new),
          ezkeyHomeZoneStateProvider.overrideWith(_ZoneState.new),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
            ),
            home: const HomePage(),
            onGenerateRoute: (settings) {
              pushedRoutes.add(settings.name!);
              return MaterialPageRoute(builder: (context) => const SizedBox.shrink(), settings: settings);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Removes the page, so that the TOTP countdown timers stop before the test ends.
  Future<void> unpump(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  group('HomePage', () {
    testWidgets('lists every TOTP by its issuer and label', (tester) async {
      await pumpHome(tester, [totp('alice@example.com', issuer: 'Orbit'), totp('bob')]);

      expect(find.text('Orbit'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);

      await unpump(tester);
    });

    testWidgets('puts the TOTP list in the EzKey zones on Android', (tester) async {
      await pumpHome(tester, [totp('alice@example.com')]);

      expect(find.byType(EzkeyHomeZones), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);

      await unpump(tester);
    });

    testWidgets('shows the TOTP list without EzKey zones where EzKey is not available', (tester) async {
      currentPlatform = .windows;
      await pumpHome(tester, [totp('alice@example.com')]);

      expect(find.byType(EzkeyHomeZones), findsNothing);
      expect(find.text('alice@example.com'), findsOneWidget);

      await unpump(tester);
    });

    testWidgets('the add button offers a QR code or a manual entry, and opens the matching page', (tester) async {
      await pumpHome(tester, [totp('alice@example.com')]);

      await tester.tap(find.byIcon(FLucideIcons.plus).first);
      await tester.pumpAndSettle();

      expect(find.text(translations.home.addDialog.qrCode.title), findsOneWidget);
      expect(find.text(translations.home.addDialog.manually.title), findsOneWidget);

      await tester.tap(find.text(translations.home.addDialog.qrCode.title));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [ScanPage.name]);

      await unpump(tester);
    });

    testWidgets('the manual entry opens the TOTP page', (tester) async {
      await pumpHome(tester, [totp('alice@example.com')]);

      await tester.tap(find.byIcon(FLucideIcons.plus).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(translations.home.addDialog.manually.title));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [TotpPage.name]);

      await unpump(tester);
    });

    testWidgets('without a crypto store, offers to reset the master password instead of the list', (tester) async {
      await pumpHome(tester, [totp('alice@example.com')], withCryptoStore: false);

      expect(find.text(translations.home.noCryptoStore.message), findsOneWidget);
      expect(find.text(translations.home.noCryptoStore.resetButton), findsOneWidget);
      expect(find.text('alice@example.com'), findsNothing);

      await unpump(tester);
    });
  });

  // The search runs with semantics off: focusing any forui 0.25 text field trips a known semantics
  // assertion on Flutter 3.47 (#30, duobaseio/forui#1160, fixed in forui 0.26).
  group('HomePage search', () {
    /// Opens the search and types [query].
    Future<void> search(WidgetTester tester, String query) async {
      await tester.tap(find.byIcon(FLucideIcons.search).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), query);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('finds TOTPs whose label or issuer contains the query', semanticsEnabled: false, (tester) async {
      await pumpHome(tester, [totp('alice@example.com', issuer: 'orbit'), totp('bob', issuer: 'atlas')]);

      await search(tester, 'orb');

      expect(find.text('alice@example.com'), findsWidgets);
      expect(find.text('bob'), findsNothing);

      await unpump(tester);
    });

    testWidgets('lowercases the query but not the TOTP: upper-case letters in a label are never matched', semanticsEnabled: false, (tester) async {
      // Upstream behaviour as of 2026-10-31 (`_Search.search`), pinned on purpose. Noted for the
      // harmonization dossier (H9); not changed here (upstream alignment).
      await pumpHome(tester, [totp('alice@example.com', issuer: 'GitHub'), totp('bob', issuer: 'atlas')]);

      await search(tester, 'ALICE');

      expect(find.text('alice@example.com'), findsWidgets);

      await tester.enterText(find.byType(EditableText), 'GitHub');
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('alice@example.com'), findsNothing);

      // Control: the lower-case part of the same issuer is found.
      await tester.enterText(find.byType(EditableText), 'it');
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('alice@example.com'), findsWidgets);

      await unpump(tester);
    });
  });
}
