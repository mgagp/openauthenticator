import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/availability.dart';

// Hook for upstream's QR scanner (lib/pages/scan.dart). It only sees what upstream rejects as a TOTP URI,
// so TOTP codes go through upstream's flow unchanged; an EzKey invitation goes to the enrollment flow
// instead of an error (docs/ezkey/harmonization.md, H6). The EzKey scanner does the reverse for TOTP URIs
// (ezkey/pages/scan_page.dart).

/// Returns whether [content], scanned by upstream's scanner, is for EzKey: an EzKey invitation, where
/// EzKey is available. Synchronous, so upstream's code keeps using its context as before.
bool isEzkeyScan(String content) => ezkeyAvailable && isEzkeyInvitation(content);

/// Returns whether [content] is an EzKey invitation.
bool isEzkeyInvitation(String content) {
  try {
    EnrollmentCode.parse(content);
    return true;
  } on EzkeyValidationException {
    return false;
  }
}

/// Handles [content] scanned by upstream's scanner when [isEzkeyScan] says it is for EzKey.
///
/// Starts the enrollment flow over the scanner, and `EzkeyEnrollPage` takes the scanner's place, like
/// upstream's TOTP page does. Returns whether the scanner resumes: only when the flow stopped before that
/// page (cancelled, or binding failed and the user was told).
Future<bool> onEzkeyScan(BuildContext context, WidgetRef ref, String content) async {
  bool opened = await EzkeyActions.addEnrollment(context, ref, content, replaceRoute: true);
  return !opened;
}
