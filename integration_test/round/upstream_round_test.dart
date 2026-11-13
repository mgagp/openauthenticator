import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:integration_test/integration_test.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/main.dart' as app;
import 'package:open_authenticator/widgets/expandable_tile.dart';

/// The master password the round sets during the intro.
const String _masterPassword = 'RoundTest2026xyz';

/// The password of the backup the round makes.
const String _backupPassword = 'BackupPw2026';

/// The RFC 6238 SHA-1 test secret, `12345678901234567890`, in base32.
const String _sha1Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

/// Runs the upstream part of the full round (`docs/test-plan.md` § 6) in the real app process, on a fresh
/// install: U1, U3, U5, U7, U13, U15. Written for desktop, where the app cannot be driven from outside
/// (#132); it needs no camera, network or account.
///
/// It writes to the app's real storage for this build type. Start it only on a clean install: it
/// expects the intro, and it ends by clearing the data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Semantics off: forui 0.25 text fields break the semantics merge invariant of Flutter 3.47 (#30).
  testWidgets('upstream round on a fresh install', semanticsEnabled: false, (tester) async {
    await app.main();
    await _waitFor(tester, find.text(translations.intro.button.next));

    // U1: intro, master password, empty home.
    await _tap(tester, find.text(translations.intro.button.next));
    await _waitFor(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText).at(0), _masterPassword);
    await tester.enterText(find.byType(EditableText).at(1), _masterPassword);
    await _settle(tester);
    while (find.text(translations.intro.button.finish).evaluate().isEmpty) {
      await _tap(tester, find.text(translations.intro.button.next));
    }
    await _tap(tester, find.text(translations.intro.button.finish));
    await _waitFor(tester, find.textContaining(translations.home.empty.split('\n').first));
    _report('U1', 'intro done, home empty');

    // U3: add a TOTP by hand, with the default parameters (SHA-1, 6 digits, 30 s). The advanced options
    // (algorithm select) could not be driven from this test; Android covers them.
    await _tap(tester, find.byIcon(FLucideIcons.plus));
    await _tap(tester, find.text(translations.home.addDialog.manually.title));
    await _waitFor(tester, find.text(translations.totp.page.title.add));
    await tester.enterText(find.byType(EditableText).at(0), 'carol@example.com');
    await tester.enterText(find.byType(EditableText).at(1), _sha1Secret);
    await tester.enterText(find.byType(EditableText).at(2), 'ManualCo');
    await _settle(tester, seconds: 2);
    await _tap(tester, find.text(translations.totp.page.save));
    await _waitGone(tester, find.text(translations.totp.page.title.add));
    await _waitFor(tester, find.text('ManualCo'));
    _report('U3', 'manual TOTP saved');

    // U5: the code shown is the RFC 6238 SHA-1 code of the current period (read again once if a
    // period boundary fell between the two reads).
    hashlib.TOTP reference = hashlib.TOTP(utf8.encode('12345678901234567890'));
    String shown = _shownCode(tester, 6);
    String expected = _pad(reference.value(), 6);
    if (shown != expected) {
      await _settle(tester, seconds: 2);
      shown = _shownCode(tester, 6);
      expected = _pad(reference.value(), 6);
    }
    expect(shown, expected);
    _report('U5', 'shown $shown, expected $expected');

    // U7: edit through the desktop menu, then delete.
    await _tap(tester, find.byIcon(FLucideIcons.ellipsis).first);
    await _tap(tester, find.text(translations.totp.actions.desktopButtons.edit));
    await _waitFor(tester, find.text(translations.totp.page.title.edit));
    await tester.enterText(find.byType(EditableText).at(2), 'ManualCoEdited');
    await _settle(tester, seconds: 2);
    await _tap(tester, find.text(translations.totp.page.save));
    await _waitGone(tester, find.text(translations.totp.page.title.edit));
    await _waitFor(tester, find.text('ManualCoEdited'));
    _report('U7', 'edited');

    // U13: backup, delete the TOTP, wrong backup password refused, restore with the right one.
    await _openSettings(tester);
    await _tapScrolled(tester, find.text(translations.settings.backups.backupNow.title));
    await _waitFor(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText).last, _backupPassword);
    await _tap(tester, find.text(_ok(tester)));
    await _settle(tester, seconds: 3);
    await _back(tester);

    await _tap(tester, find.byIcon(FLucideIcons.ellipsis).first);
    await _tap(tester, find.text(translations.totp.actions.desktopButtons.delete));
    await _tap(tester, find.text(_ok(tester)));
    await _waitFor(tester, find.textContaining(translations.home.empty.split('\n').first));
    _report('U7', 'deleted');

    await _openSettings(tester);
    await _tapScrolled(tester, find.text(translations.settings.backups.manageBackups.title));
    await _tap(tester, find.descendant(of: find.byType(ExpandableTile).first, matching: find.byIcon(FLucideIcons.chevronRight)));
    await _tap(tester, find.text(translations.settings.backups.manageBackups.button.restore));
    await _waitFor(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText).last, 'WrongPassword');
    await _tap(tester, find.text(_ok(tester)));
    await _settle(tester, seconds: 2);
    expect(find.text('ManualCoEdited'), findsNothing);
    await _tap(tester, find.text(translations.settings.backups.manageBackups.button.restore));
    await _waitFor(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText).last, _backupPassword);
    await _tap(tester, find.text(_ok(tester)));
    await _settle(tester, seconds: 3);
    await _closeDialogIfAny(tester);
    await _back(tester);
    await _waitFor(tester, find.text('ManualCoEdited'));
    _report('U13', 'restored after delete; wrong password did not restore');

    // U15: clear data. Keeps the backups: deleting them hits #141.
    await _openSettings(tester);
    await _tapScrolled(tester, find.text(translations.settings.dangerZone.clearData.title));
    await _tap(tester, find.text(_ok(tester)));
    await _waitFor(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText).last, _masterPassword);
    await _tap(tester, find.text(_ok(tester)));
    await _waitFor(tester, find.text(translations.settings.dangerZone.clearData.backupDeleteConfirmationDialog.title));
    await _tap(tester, find.text(MaterialLocalizations.of(tester.element(find.byType(Navigator).first)).cancelButtonLabel));
    await _settle(tester, seconds: 3);
    _report('U15', 'data cleared, backups kept');
  });
}

/// Pumps frames for [seconds] of real time. The home screen never settles: each TOTP has a countdown.
Future<void> _settle(WidgetTester tester, {int seconds = 1}) async {
  for (int i = 0; i < seconds * 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Pumps until [finder] finds something, or fails after [seconds].
Future<void> _waitFor(WidgetTester tester, Finder finder, {int seconds = 20}) async {
  for (int i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  fail('Not found after ${seconds}s: $finder');
}

/// Pumps until [finder] finds nothing, or fails after [seconds].
Future<void> _waitGone(WidgetTester tester, Finder finder, {int seconds = 30}) async {
  for (int i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  fail('Still there after ${seconds}s: $finder');
}

/// Waits for [finder], taps its last match, and lets the next screen draw.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder.last);
  await tester.pump();
  await tester.tap(finder.last);
  await _settle(tester);
}

/// Scrolls the current page until [finder] is visible, then taps it.
Future<void> _tapScrolled(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await _tap(tester, finder);
}

/// Opens the settings page from the home screen header.
Future<void> _openSettings(WidgetTester tester) async {
  await _tap(tester, find.byIcon(FLucideIcons.settings));
  await _waitFor(tester, find.text(translations.settings.title));
}

/// Goes back to the previous page with the header's back button.
Future<void> _back(WidgetTester tester) async {
  await _tap(tester, find.byIcon(FLucideIcons.arrowLeft));
}

/// Closes the "Manage backups" dialog if it is still open.
Future<void> _closeDialogIfAny(WidgetTester tester) async {
  String close = MaterialLocalizations.of(tester.element(find.byType(Navigator).first)).closeButtonLabel;
  if (find.text(close).evaluate().isNotEmpty) {
    await _tap(tester, find.text(close));
  }
}

/// The OK label the app's dialogs use, in the app's locale.
String _ok(WidgetTester tester) => MaterialLocalizations.of(tester.element(find.byType(Navigator).first)).okButtonLabel;

/// The only TOTP code with [digits] digits on screen, spaces removed.
String _shownCode(WidgetTester tester, int digits) {
  // The code is grouped with a (possibly non-breaking) space: keep the texts made of digits and spaces only.
  RegExp grouped = RegExp(r'^[0-9\s]+$');
  List<String> codes = [
    for (Text text in tester.widgetList<Text>(find.byType(Text)))
      if (grouped.hasMatch(text.data ?? '') && (text.data ?? '').replaceAll(RegExp(r'\s'), '').length == digits) (text.data ?? '').replaceAll(RegExp(r'\s'), ''),
  ];
  expect(codes, hasLength(1), reason: 'TOTP codes on screen: $codes');
  return codes.single;
}

/// Pads [value] with leading zeros to [digits] digits.
String _pad(int value, int digits) => value.toString().padLeft(digits, '0');

/// Prints one result line for the run log.
void _report(String item, String detail) => debugPrint('ROUND $item: $detail');
