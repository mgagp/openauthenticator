import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/main.dart' as app;
import 'package:open_authenticator/widgets/dialog/text_input_dialog.dart';
import 'package:open_authenticator/widgets/expandable_tile.dart';

import 'round_helpers.dart';

/// Which half of the round this run is: `setup` (fresh install, ends with the app's data in place) or
/// `restart` (the next launch of the same build, ends by clearing the data).
const String _phase = String.fromEnvironment('ROUND_PHASE');

/// Runs the items of the full round (`docs/test-plan.md` § 6) that need more than one launch of the app,
/// in two runs of the real app process (#132):
///
/// - `--dart-define=ROUND_PHASE=setup`, on a fresh install: U6 copy, U8 search, U10 change the master
///   password, U9 change settings, U11 turn on the master password at start, U14 manage backups.
/// - `--dart-define=ROUND_PHASE=restart`, right after: U11 unlock at start (wrong, then right password),
///   U19 and U9 everything still there, U10 the TOTP still decrypts; then it clears the data.
/// - `--dart-define=ROUND_PHASE=links`, on a fresh install: only the intro, leaving an unlocked app for the
///   links opened from outside through the MSIX package (U4, U17); clear the data afterwards.
///
/// Like `upstream_round_test.dart`, it writes to the app's real storage for this build type, and it uses
/// the system clipboard (U6).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Semantics off: forui 0.25 text fields break the semantics merge invariant of Flutter 3.47 (#30).
  testWidgets('upstream round across a restart ($_phase)', semanticsEnabled: false, (tester) async {
    switch (_phase) {
      case 'setup':
        await _setup(tester);
      case 'restart':
        await _afterRestart(tester);
      case 'links':
        await app.main();
        await completeIntro(tester);
        report('links', 'intro done, home empty; the app is ready for links opened from outside (MSIX)');
      default:
        fail('Pass --dart-define=ROUND_PHASE=setup, then ROUND_PHASE=restart (or ROUND_PHASE=links).');
    }
  });
}

/// First launch: sets everything the second launch checks.
Future<void> _setup(WidgetTester tester) async {
  await app.main();
  await completeIntro(tester);
  await addManualTotp(tester, label: 'carol@example.com', issuer: 'ManualCo');

  // U6: on desktop, a tap on the tile copies the code (there is no copy button). Windows refuses the
  // clipboard to every process while the session is locked, and the app does not catch that error:
  // probe the clipboard first, and record U6 as blocked rather than fail the round.
  // The code shown before the tap was checked against the reference; a period may roll over in between.
  final String before = await expectReferenceCode(tester);
  if (await _clipboardAvailable()) {
    await tapLast(tester, find.text('ManualCo'));
    final String? copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    final hashlib.TOTP reference = hashlib.TOTP(utf8.encode(roundSha1SecretRaw));
    expect([before, pad(reference.value(), 6)], contains(copied));
    report('U6', 'tap copied $copied');
  } else {
    report('U6', 'blocked: the clipboard is unavailable (session locked?)');
  }

  // U8: search from the header finds the TOTP by part of its issuer, finds nothing for another text, and
  // choosing the result goes back to the home screen. Upstream lowercases the query but not the issuer
  // or label, so a query with the issuer's capital letters finds nothing (#145): recorded, not failed.
  await tapLast(tester, find.byIcon(FLucideIcons.search));
  await waitFor(tester, find.byType(EditableText));
  await tester.enterText(find.byType(EditableText).last, 'zzz');
  await settle(tester);
  expect(find.text('ManualCo'), findsNothing);
  await tester.enterText(find.byType(EditableText).last, 'Manual');
  await settle(tester);
  final bool foundAsWritten = find.text('ManualCo').evaluate().isNotEmpty;
  await tester.enterText(find.byType(EditableText).last, 'anual');
  await settle(tester);
  await tapLast(tester, find.text('ManualCo'));
  await waitGone(tester, find.byType(EditableText));
  await waitFor(tester, find.text('ManualCo'));
  report('U8', 'found by "anual", nothing for "zzz", back home; "Manual" ${foundAsWritten ? 'found it' : 'found nothing (#145)'}');

  // U10: change the master password (asks the current one first), then the code still matches.
  await openSettings(tester);
  await tapScrolled(tester, find.text(translations.settings.security.changeMasterPassword.title));
  await answerPasswordDialog(tester, roundMasterPassword);
  await waitFor(tester, find.text(translations.masterPassword.changeDialog.title));
  final Finder dialogFields = find.descendant(of: find.byType(Form), matching: find.byType(EditableText));
  await tester.enterText(dialogFields.at(0), roundNewMasterPassword);
  await tester.enterText(dialogFields.at(1), roundNewMasterPassword);
  await settle(tester);
  await tapLast(tester, find.text(materialLabels(tester).continueButtonLabel));
  await waitGone(tester, find.text(translations.masterPassword.changeDialog.title));
  await settle(tester, seconds: 3);
  await goBack(tester);
  await expectReferenceCode(tester);
  report('U10', 'master password changed, code still matches');

  // U9: dark theme, and the search button hidden (a display option).
  await openSettings(tester);
  await tapScrolled(tester, find.text(translations.settings.application.theme.title));
  await tapLast(tester, find.text(translations.settings.application.theme.themePickerDialog.theme.name['dark']!));
  await settle(tester);
  expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
  await tapScrolled(tester, find.text(translations.settings.application.displaySearchIconButton.title));
  await settle(tester);
  report('U9', 'theme set to dark, search button turned off');

  // U11: ask for the master password at start (turn off "save derived key"; it asks the password).
  await tapScrolled(tester, find.text(translations.settings.security.saveDerivedKey.title));
  await answerPasswordDialog(tester, roundNewMasterPassword);
  await settle(tester, seconds: 2);
  report('U11', 'master password at start turned on');

  // U14: make a backup, see it listed, delete it. The list should show none afterwards; #141 keeps it
  // listed until the dialog is reopened, so both are recorded.
  await backupNow(tester);
  await tapScrolled(tester, find.text(translations.settings.backups.manageBackups.title));
  await waitFor(tester, find.byType(ExpandableTile));
  final int listed = find.byType(ExpandableTile).evaluate().length;
  await tapLast(tester, find.descendant(of: find.byType(ExpandableTile).first, matching: find.byIcon(FLucideIcons.chevronRight)));
  await tapLast(tester, find.text(translations.settings.backups.manageBackups.button.delete));
  await waitFor(tester, find.text(translations.settings.backups.manageBackups.deleteBackupConfirmationDialog.title));
  await tapLast(tester, find.text(okLabel(tester)));
  await settle(tester, seconds: 2);
  final int afterDelete = find.byType(ExpandableTile).evaluate().length;
  await closeDialogIfAny(tester);
  await tapScrolled(tester, find.text(translations.settings.backups.manageBackups.title));
  await settle(tester, seconds: 2);
  final int afterReopen = find.byType(ExpandableTile).evaluate().length;
  await closeDialogIfAny(tester);
  expect(listed, 1);
  expect(afterReopen, 0);
  report('U14', 'listed $listed, after delete $afterDelete (stale if 1, #141), after reopening $afterReopen');

  await goBack(tester);
  await waitFor(tester, find.text('ManualCo'));
  report('setup', 'done; run again with ROUND_PHASE=restart');
}

/// Second launch: checks what the first one left, then clears the data.
Future<void> _afterRestart(WidgetTester tester) async {
  await app.main();

  // U11: the app asks for the master password at start; a wrong one does not unlock.
  await _unlockAtStart(tester, 'WrongPassword');
  await settle(tester, seconds: 2);
  expect(find.text('ManualCo'), findsNothing);
  await _closeErrorIfAny(tester);
  await _unlockAtStart(tester, roundNewMasterPassword);
  await waitFor(tester, find.text('ManualCo'));
  report('U11', 'wrong password refused, new password unlocked');

  // U19, U10: the TOTP is still there, and decrypts with the changed master password.
  final String shown = await expectReferenceCode(tester);
  report('U19', 'TOTP kept across the restart, code $shown matches');

  // U9: the settings are still there.
  expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
  expect(find.byIcon(FLucideIcons.search), findsNothing);
  report('U9', 'dark theme and hidden search button kept');

  await openSettings(tester);
  await clearDataKeepingBackups(tester, roundNewMasterPassword);
  report('restart', 'data cleared');
}

/// Answers the master password prompt shown at start, opening it with the Unlock button if needed.
Future<void> _unlockAtStart(WidgetTester tester, String password) async {
  final Finder unlock = find.text(translations.appUnlock.button.unlock);
  final Finder field = find.descendant(of: find.byType(MasterPasswordInputDialog), matching: find.byType(EditableText));
  for (int i = 0; i < 200 && field.evaluate().isEmpty; i++) {
    if (unlock.evaluate().isNotEmpty && i % 20 == 19) {
      await tester.tap(unlock.last);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  // After a refused password, enterText no longer replaces the field's text in this dialog (seen on
  // Windows): set it through the field's controller, which the dialog listens to.
  tester.widget<EditableText>(field.last).controller.text = password;
  await settle(tester);
  expect(tester.widget<EditableText>(field.last).controller.text, password);
  await tapLast(tester, find.descendant(of: find.byType(MasterPasswordInputDialog), matching: find.text(okLabel(tester))));
}

/// Whether the system clipboard accepts a write now.
Future<bool> _clipboardAvailable() async {
  try {
    await Clipboard.setData(const ClipboardData(text: 'round-clipboard-probe'));
    return true;
  } on PlatformException {
    return false;
  }
}

/// Closes an error dialog left by a failed unlock, if any.
Future<void> _closeErrorIfAny(WidgetTester tester) async {
  for (final String label in [okLabel(tester), materialLabels(tester).closeButtonLabel]) {
    if (find.text(label).evaluate().isNotEmpty && find.byType(EditableText).evaluate().isEmpty) {
      await tapLast(tester, find.text(label));
    }
  }
}
