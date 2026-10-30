import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/widgets/app_scaffold.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/error_dialog.dart';
import 'package:open_authenticator/widgets/scan/scanner.dart';
import 'package:open_authenticator/ezkey/toast.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Scans an EzKey invitation QR code and pops with its raw content.
class EzkeyScanPage extends StatefulWidget {
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
  State<StatefulWidget> createState() => _EzkeyScanPageState();
}

/// The EzKey scan page state.
class _EzkeyScanPageState extends State<EzkeyScanPage> {
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
          try {
            EnrollmentCode.parse(barcode);
          } on EzkeyValidationException {
            showEzkeyErrorToast(context, text: translations.ezkey.scan.notAnInvitation);
            return true;
          }
          Navigator.pop(context, barcode);
          return false;
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
