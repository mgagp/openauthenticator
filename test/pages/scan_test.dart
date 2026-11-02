import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/main.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/model/totp/decrypted.dart';
import 'package:open_authenticator/pages/scan.dart';
import 'package:open_authenticator/pages/totp.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/utils/platform.dart';
import 'package:open_authenticator/widgets/scan/scanner.dart';

// Characterization tests (#64): they pin upstream's QR scanner as it is today, before the EzKey work
// lets it recognize EzKey invitations (harmonization H6). The camera is not needed: the tests call the
// scanner's `onScan` callback with the scanned content. They run where EzKey is not available (Windows),
// so they see upstream's behavior only; test/ezkey/scan_test.dart covers the EzKey hook.

/// A crypto store notifier that holds a fixed store, without the secure storage.
class _FixedCryptoStore extends CryptoStoreNotifier {
  /// The store, or `null` for none.
  final CryptoStore? store;

  /// Creates a new fixed crypto store notifier instance.
  _FixedCryptoStore(this.store);

  @override
  FutureOr<CryptoStore?> build() => store;
}

void main() {
  late CryptoStore cryptoStore;
  late List<RouteSettings> pushedRoutes;
  late Platform platform;

  setUpAll(() => cryptoStore = CryptoStore.fromPassword('password', Salt.generate()));

  setUp(() {
    pushedRoutes = [];
    platform = currentPlatform;
    currentPlatform = .windows;
  });

  tearDown(() => currentPlatform = platform);

  /// Shows the scan page, with a crypto store unless [withCryptoStore] is `false`.
  Future<void> pumpScan(WidgetTester tester, {bool withCryptoStore = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(withCryptoStore ? cryptoStore : null)),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
            ),
            home: const ScanPage(),
            onGenerateRoute: (settings) {
              pushedRoutes.add(settings);
              return MaterialPageRoute(builder: (context) => const SizedBox.shrink(), settings: settings);
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Hands [content] to the scanner as if the camera had read it, and returns whether it resumes.
  Future<bool> scan(WidgetTester tester, String content) async {
    QrCodeScanner scanner = tester.widget<QrCodeScanner>(find.byType(QrCodeScanner));
    Future<bool> resume = scanner.onScan!(content);
    // No pumpAndSettle: without a camera, the scanner placeholder spins forever.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return resume;
  }

  group('ScanPage', () {
    testWidgets('opens the TOTP page with the scanned TOTP to add', (tester) async {
      await pumpScan(tester);

      bool resume = await scan(tester, 'otpauth://totp/Orbit:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Orbit');

      expect(resume, isFalse);
      expect(pushedRoutes.map((route) => route.name), [TotpPage.name]);
      Map arguments = pushedRoutes.single.arguments as Map;
      expect(arguments[OpenAuthenticatorApp.kRouteParameterAddTotp], isTrue);
      DecryptedTotp totp = arguments[OpenAuthenticatorApp.kRouteParameterTotp];
      // Upstream keeps the "Issuer:" prefix of the URI path in the label.
      expect(totp.label, 'Orbit:alice@example.com');
      expect(totp.issuer, 'Orbit');
    });

    testWidgets('shows an error and resumes scanning on content that is not a URI', (tester) async {
      await pumpScan(tester);

      bool resume = await scan(tester, 'not a URI at all: %%');

      expect(resume, isTrue);
      expect(find.text(translations.error.scan.noUri), findsOneWidget);
      expect(pushedRoutes, isEmpty);
    });

    testWidgets('shows an error and resumes scanning on an otpauth URI without a secret', (tester) async {
      await pumpScan(tester);

      bool resume = await scan(tester, 'otpauth://totp/alice@example.com?issuer=Orbit');

      expect(resume, isTrue);
      expect(find.text(translations.error.scan.noUri), findsOneWidget);
      expect(pushedRoutes, isEmpty);
    });

    testWidgets('shows an error and resumes scanning on an EzKey invitation', (tester) async {
      await pumpScan(tester);

      bool resume = await scan(tester, '{"enrollmentId":12,"enrollmentProofToken":"proof-token-12","authUrl":"https://auth.example.com"}');

      expect(resume, isTrue);
      expect(find.text(translations.error.scan.noUri), findsOneWidget);
      expect(pushedRoutes, isEmpty);
    });

    testWidgets('shows an error without a crypto store, and stays on the scanner', (tester) async {
      await pumpScan(tester, withCryptoStore: false);

      bool resume = await scan(tester, 'otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP');

      expect(resume, isFalse);
      expect(find.text(translations.error.generic.noException), findsOneWidget);
      expect(pushedRoutes, isEmpty);
    });
  });
}
