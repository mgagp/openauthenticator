import 'dart:async';

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/pages/enroll_page.dart';
import 'package:open_authenticator/ezkey/pages/scan_page.dart';
import 'package:open_authenticator/ezkey/providers.dart';
import 'package:open_authenticator/ezkey/scan.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/model/crypto/salt.dart';
import 'package:open_authenticator/model/crypto/store.dart';
import 'package:open_authenticator/pages/scan.dart';
import 'package:open_authenticator/pages/totp.dart';
import 'package:open_authenticator/themes.dart';
import 'package:open_authenticator/utils/platform.dart';
import 'package:open_authenticator/widgets/scan/scanner.dart';

import 'support.dart';

/// A crypto store notifier that holds a fixed store, without the secure storage.
class _FixedCryptoStore extends CryptoStoreNotifier {
  /// The store.
  final CryptoStore store;

  /// Creates a new fixed crypto store notifier instance.
  _FixedCryptoStore(this.store);

  @override
  Future<CryptoStore?> build() async => store;
}

/// An invitation for enrollment 12 that carries its Auth API address.
const String _invitation = '{"enrollmentId":12,"enrollmentProofToken":"proof-token-12","authUrl":"https://auth.example.com"}';

/// An invitation for enrollment 13 to the local stack, as the emulator reaches it over plain HTTP.
const String _localInvitation = '{"enrollmentId":13,"enrollmentProofToken":"proof-token-13","authUrl":"http://10.0.2.2:8080"}';

/// A TOTP QR code.
const String _totpUri = 'otpauth://totp/Orbit:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Orbit';

void main() {
  late Platform platform;
  late Ed25519TestKeyPair integrationKey;
  late CryptoStore cryptoStore;
  late InMemoryEnrollmentStore enrollmentStore;
  late EzkeyAuthenticator authenticator;
  late List<String> pushedRouteNames;
  late Future<String?> scanned;

  setUpAll(() async {
    integrationKey = await generateEd25519TestKeyPair();
    cryptoStore = CryptoStore.fromPassword('password', Salt.generate());
  });

  setUp(() {
    platform = currentPlatform;
    currentPlatform = .android;
    enrollmentStore = InMemoryEnrollmentStore();
    authenticator = EzkeyAuthenticator(keyStore: SoftwareDeviceKeyStore(), enrollmentStore: enrollmentStore, apiFactory: (uri) => BindingAuthApi(integrationKey));
    pushedRouteNames = [];
  });

  tearDown(() => currentPlatform = platform);

  /// Shows a home page that opens [scanner] with its "Open" button, and opens it.
  Future<void> pumpScanner(WidgetTester tester, {required bool ezkey}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ezkeyAuthenticatorProvider.overrideWith((ref) async => authenticator),
          cryptoStoreProvider.overrideWith(() => _FixedCryptoStore(cryptoStore)),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            builder: (context, child) => FTheme(
              data: greenTheme.light.touch,
              child: FToaster(child: child!),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    if (ezkey) {
                      scanned = EzkeyScanPage.scan(context);
                    } else {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ScanPage()));
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
            onGenerateRoute: (settings) {
              pushedRouteNames.add(settings.name!);
              return MaterialPageRoute(builder: (context) => const SizedBox.shrink(), settings: settings);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settle(tester);
  }

  /// Hands [content] to the open scanner as if the camera had read it, and returns whether it resumes.
  Future<bool> scan(WidgetTester tester, String content) async {
    QrCodeScanner scanner = tester.widget<QrCodeScanner>(find.byType(QrCodeScanner));
    bool? resume;
    unawaited(scanner.onScan!(content).then((value) => resume = value));
    await settle(tester);
    return resume ?? false;
  }

  group('isEzkeyInvitation', () {
    test('recognizes both invitation formats', () {
      expect(isEzkeyInvitation(_invitation), isTrue);
      expect(isEzkeyInvitation('12|proof-token-12'), isTrue);
    });

    test('rejects TOTP URIs and other content', () {
      expect(isEzkeyInvitation(_totpUri), isFalse);
      expect(isEzkeyInvitation('https://example.com'), isFalse);
      expect(isEzkeyInvitation(''), isFalse);
    });
  });

  group('isEzkeyScan', () {
    test('takes invitations where EzKey is available only', () {
      expect(isEzkeyScan(_invitation), isTrue);

      currentPlatform = .windows;

      expect(isEzkeyScan(_invitation), isFalse);
    });
  });

  group('Upstream scanner', () {
    testWidgets('an EzKey invitation opens the enrollment page in place of the scanner', (tester) async {
      await pumpScanner(tester, ezkey: false);

      await scan(tester, _invitation);

      expect(find.byType(EzkeyEnrollPage), findsOneWidget);
      expect(find.byType(ScanPage, skipOffstage: false), findsNothing);
      expect(find.text('Orbit Console'), findsWidgets);
    });

    testWidgets('an invitation for an administrator reads Administration with the role, and no organization', (tester) async {
      authenticator = EzkeyAuthenticator(
        keyStore: SoftwareDeviceKeyStore(),
        enrollmentStore: enrollmentStore,
        apiFactory: (uri) => BindingAuthApi(integrationKey, adminType: 'GLOBAL_ADMIN'),
      );
      await pumpScanner(tester, ezkey: false);

      await scan(tester, _invitation);

      expect(find.text(translations.ezkey.identity.administration), findsOneWidget);
      expect(find.text(translations.ezkey.identity.globalAdmin), findsOneWidget);
      expect(find.text('Alice Chen'), findsOneWidget);
      expect(find.text('Ezkey System'), findsNothing);
      expect(find.text('Orbit Console'), findsNothing);
    });

    testWidgets('leaving the enrollment page goes back home, not to the scanner', (tester) async {
      await pumpScanner(tester, ezkey: false);
      await scan(tester, _invitation);

      Navigator.pop(tester.element(find.byType(EzkeyEnrollPage)));
      await settle(tester);

      expect(find.text('Open'), findsOneWidget);
      expect(find.byType(ScanPage, skipOffstage: false), findsNothing);
    });

    testWidgets('an invitation already enrolled here shows why and resumes scanning', (tester) async {
      await enrollmentStore.save(testEnrollment(12, authApiBaseUrl: 'https://auth.example.com'));
      await pumpScanner(tester, ezkey: false);

      bool resume = await scan(tester, _invitation);

      expect(resume, isTrue);
      expect(find.text(translations.ezkey.error.alreadyEnrolled), findsOneWidget);
      expect(find.byType(ScanPage), findsOneWidget);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
    });

    testWidgets('an invitation to a plain HTTP server is refused for that reason in a release build', (tester) async {
      authenticator = EzkeyAuthenticator(
        keyStore: SoftwareDeviceKeyStore(),
        enrollmentStore: enrollmentStore,
        apiFactory: (uri) => BindingAuthApi(integrationKey),
        urlPolicy: ezkeyUrlPolicyFor(debug: false),
      );
      await pumpScanner(tester, ezkey: false);

      bool resume = await scan(tester, _localInvitation);

      expect(resume, isTrue);
      expect(find.text(translations.ezkey.error.insecureServer), findsOneWidget);
      expect(find.text(translations.ezkey.error.alreadyEnrolled), findsNothing);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
    });

    testWidgets('an invitation to the local stack over plain HTTP is accepted in a debug build', (tester) async {
      authenticator = EzkeyAuthenticator(
        keyStore: SoftwareDeviceKeyStore(),
        enrollmentStore: enrollmentStore,
        apiFactory: (uri) => BindingAuthApi(integrationKey),
        urlPolicy: ezkeyUrlPolicyFor(debug: true),
      );
      await pumpScanner(tester, ezkey: false);

      await scan(tester, _localInvitation);

      expect(find.byType(EzkeyEnrollPage), findsOneWidget);
    });

    testWidgets('a TOTP code still goes through upstream\'s flow', (tester) async {
      await pumpScanner(tester, ezkey: false);

      bool resume = await scan(tester, _totpUri);

      expect(resume, isFalse);
      expect(pushedRouteNames, [TotpPage.name]);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
    });

    testWidgets('an invitation shows upstream\'s error where EzKey is not available', (tester) async {
      currentPlatform = .windows;
      await pumpScanner(tester, ezkey: false);

      bool resume = await scan(tester, _invitation);

      expect(resume, isTrue);
      expect(find.text(translations.error.scan.noUri), findsOneWidget);
      expect(find.byType(EzkeyEnrollPage), findsNothing);
    });
  });

  group('EzkeyScanPage', () {
    testWidgets('returns a scanned invitation', (tester) async {
      await pumpScanner(tester, ezkey: true);

      bool resume = await scan(tester, _invitation);

      expect(resume, isFalse);
      expect(await scanned, _invitation);
    });

    testWidgets('sends a TOTP code to upstream\'s TOTP page and returns nothing', (tester) async {
      await pumpScanner(tester, ezkey: true);

      bool resume = await scan(tester, _totpUri);

      expect(resume, isFalse);
      expect(pushedRouteNames, [TotpPage.name]);
      expect(await scanned, isNull);
    });

    testWidgets('shows an error and resumes scanning on other content', (tester) async {
      await pumpScanner(tester, ezkey: true);

      bool resume = await scan(tester, 'https://example.com');

      expect(resume, isTrue);
      expect(find.text(translations.ezkey.scan.notAnInvitation), findsOneWidget);
      expect(pushedRouteNames, isEmpty);
    });
  });
}

/// Lets routes and the waiting overlay finish. No pumpAndSettle: without a camera, the scanner
/// placeholder spins forever.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
