import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/main.dart' as app;
import 'package:open_authenticator/widgets/expandable_tile.dart';

import 'round_helpers.dart';

/// Runs the upstream part of the full round (`docs/test-plan.md` § 6) in the real app process, on a fresh
/// install: U1, U3, U5, U7, U13, U15. Written for desktop, where the app cannot be driven from outside
/// (#132); it needs no camera, network or account. The items that need a restart are in
/// `upstream_restart_test.dart`.
///
/// It writes to the app's real storage for this build type. Start it only on a clean install: it
/// expects the intro, and it ends by clearing the data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Semantics off: forui 0.25 text fields break the semantics merge invariant of Flutter 3.47 (#30).
  testWidgets('upstream round on a fresh install', semanticsEnabled: false, (tester) async {
    await app.main();

    // U1: intro, master password, empty home.
    await completeIntro(tester);
    report('U1', 'intro done, home empty');

    // U3: add a TOTP by hand, with the default parameters (SHA-1, 6 digits, 30 s). The advanced options
    // (algorithm select) could not be driven from this test; Android covers them.
    await addManualTotp(tester, label: 'carol@example.com', issuer: 'ManualCo');
    report('U3', 'manual TOTP saved');

    // U5: the code shown is the RFC 6238 SHA-1 code of the current period.
    String shown = await expectReferenceCode(tester);
    report('U5', 'shown $shown matches the reference');

    // U7: edit through the desktop menu, then delete.
    await tapLast(tester, find.byIcon(FLucideIcons.ellipsis).first);
    await tapLast(tester, find.text(translations.totp.actions.desktopButtons.edit));
    await waitFor(tester, find.text(translations.totp.page.title.edit));
    await tester.enterText(find.byType(EditableText).at(2), 'ManualCoEdited');
    await settle(tester, seconds: 2);
    await tapLast(tester, find.text(translations.totp.page.save));
    await waitGone(tester, find.text(translations.totp.page.title.edit));
    await waitFor(tester, find.text('ManualCoEdited'));
    report('U7', 'edited');

    // U13: backup, delete the TOTP, wrong backup password refused, restore with the right one.
    await openSettings(tester);
    await backupNow(tester);
    await goBack(tester);

    await tapLast(tester, find.byIcon(FLucideIcons.ellipsis).first);
    await tapLast(tester, find.text(translations.totp.actions.desktopButtons.delete));
    await tapLast(tester, find.text(okLabel(tester)));
    await waitFor(tester, find.textContaining(translations.home.empty.split('\n').first));
    report('U7', 'deleted');

    await openSettings(tester);
    await tapScrolled(tester, find.text(translations.settings.backups.manageBackups.title));
    await tapLast(tester, find.descendant(of: find.byType(ExpandableTile).first, matching: find.byIcon(FLucideIcons.chevronRight)));
    await tapLast(tester, find.text(translations.settings.backups.manageBackups.button.restore));
    await answerPasswordDialog(tester, 'WrongPassword');
    await settle(tester, seconds: 2);
    expect(find.text('ManualCoEdited'), findsNothing);
    await tapLast(tester, find.text(translations.settings.backups.manageBackups.button.restore));
    await answerPasswordDialog(tester, roundBackupPassword);
    await settle(tester, seconds: 3);
    await closeDialogIfAny(tester);
    await goBack(tester);
    await waitFor(tester, find.text('ManualCoEdited'));
    report('U13', 'restored after delete; wrong password did not restore');

    // U15: clear data, keeping the backups.
    await openSettings(tester);
    await clearDataKeepingBackups(tester, roundMasterPassword);
    report('U15', 'data cleared, backups kept');
  });
}
