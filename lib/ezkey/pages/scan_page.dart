import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/scan.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/model/app_links/otpauth_totp.dart';
import 'package:open_authenticator/pages/totp.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/error_dialog.dart';
import 'package:open_authenticator/widgets/scan/scanner.dart';
import 'package:open_authenticator/ezkey/toast.dart';
import 'package:open_authenticator/widgets/waiting_overlay.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Scans an EzKey invitation QR code and pops with its raw content.
///
/// A TOTP QR code goes to upstream's TOTP add page instead, as upstream's scanner would send it
/// (harmonization H6); [scan] then returns `null`.
class EzkeyScanPage extends ConsumerStatefulWidget {
  /// Creates a new EzKey scan page instance.
  const EzkeyScanPage({
    super.key,
  });

  /// Opens the scanner and returns the scanned invitation, or `null` if the user went back.
  static Future<String?> scan(BuildContext context) => Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (context) => const EzkeyScanPage()),
  );

  @override
  ConsumerState<EzkeyScanPage> createState() => _EzkeyScanPageState();
}

/// The EzKey scan page state.
class _EzkeyScanPageState extends ConsumerState<EzkeyScanPage> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    header: FHeader.nested(
      prefixes: [
        ClickableHeaderAction.back(
          onPress: () => Navigator.pop(context),
        ),
      ],
      title: Text(translations.ezkey.scan.title),
    ),
    children: [
      QrCodeScanner(
        onScan: (barcode) async {
          if (isEzkeyInvitation(barcode)) {
            Navigator.pop(context, barcode);
            return false;
          }
          Uri? uri = Uri.tryParse(barcode);
          if (uri != null && (uri as OtpAuthTotpLink).isValid) {
            // Same as upstream's scanner (lib/pages/scan.dart): the TOTP page replaces the routes above home.
            await showWaitingOverlay(
              context,
              future: TotpPage.openFromUri(context, ref, uri),
            );
            return false;
          }
          showEzkeyErrorToast(context, text: translations.ezkey.scan.notAnInvitation);
          return true;
        },
        onError: (error, listener) => ErrorDialog.openDialog(
          context,
          error: error,
        ),
      ),
    ],
  );

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    WakelockPlus.disable();
    super.dispose();
  }
}
