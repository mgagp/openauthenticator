import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:material_ui/material_ui.dart';
import 'package:open_authenticator/i18n/translations.g.dart';

/// The master password the round sets during the intro.
const String roundMasterPassword = 'RoundTest2026xyz';

/// The master password the round changes to (U10).
const String roundNewMasterPassword = 'RoundTest2026abc';

/// The password of the backups the round makes.
const String roundBackupPassword = 'BackupPw2026';

/// The RFC 6238 SHA-1 test secret, `12345678901234567890`, in base32.
const String roundSha1Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

/// The RFC 6238 SHA-1 test secret as raw bytes, for the reference generator.
const String roundSha1SecretRaw = '12345678901234567890';

/// Pumps frames for [seconds] of real time. The home screen never settles: each TOTP has a countdown.
Future<void> settle(WidgetTester tester, {int seconds = 1}) async {
  for (int i = 0; i < seconds * 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Pumps until [finder] finds something, or fails after [seconds].
Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 20}) async {
  for (int i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  fail('Not found after ${seconds}s: $finder\nTexts on screen: ${visibleTexts(tester)}');
}

/// The texts on screen, to tell where the app is when a step fails.
List<String> visibleTexts(WidgetTester tester) => [
  for (final Text text in tester.widgetList<Text>(find.byType(Text)))
    if ((text.data ?? text.textSpan?.toPlainText() ?? '').trim().isNotEmpty) (text.data ?? text.textSpan!.toPlainText()).trim(),
];

/// Pumps until [finder] finds nothing, or fails after [seconds].
Future<void> waitGone(WidgetTester tester, Finder finder, {int seconds = 30}) async {
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
Future<void> tapLast(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.last);
  await tester.pump();
  await tester.tap(finder.last);
  await settle(tester);
}

/// Scrolls the current page until [finder] is visible, then taps it.
Future<void> tapScrolled(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tapLast(tester, finder);
}

/// Opens the settings page from the home screen header.
Future<void> openSettings(WidgetTester tester) async {
  await tapLast(tester, find.byIcon(FLucideIcons.settings));
  await waitFor(tester, find.text(translations.settings.title));
}

/// Goes back to the previous page with the header's back button.
Future<void> goBack(WidgetTester tester) async {
  await tapLast(tester, find.byIcon(FLucideIcons.arrowLeft));
}

/// Closes the open dialog if it has a Close button.
Future<void> closeDialogIfAny(WidgetTester tester) async {
  final String close = materialLabels(tester).closeButtonLabel;
  if (find.text(close).evaluate().isNotEmpty) {
    await tapLast(tester, find.text(close));
  }
}

/// The Material labels (OK, Cancel, Close...) in the app's locale.
MaterialLocalizations materialLabels(WidgetTester tester) => MaterialLocalizations.of(tester.element(find.byType(Navigator).first));

/// The OK label the app's dialogs use, in the app's locale.
String okLabel(WidgetTester tester) => materialLabels(tester).okButtonLabel;

/// Types [password] in the last text field of the open dialog and confirms with OK.
Future<void> answerPasswordDialog(WidgetTester tester, String password) async {
  await waitFor(tester, find.byType(EditableText));
  await tester.enterText(find.byType(EditableText).last, password);
  await tapLast(tester, find.text(okLabel(tester)));
}

/// Goes through the intro of a fresh install, sets [roundMasterPassword], and waits for the empty home (U1).
Future<void> completeIntro(WidgetTester tester) async {
  await waitFor(tester, find.text(translations.intro.button.next));
  await tapLast(tester, find.text(translations.intro.button.next));
  await waitFor(tester, find.byType(EditableText));
  await tester.enterText(find.byType(EditableText).at(0), roundMasterPassword);
  await tester.enterText(find.byType(EditableText).at(1), roundMasterPassword);
  await settle(tester);
  while (find.text(translations.intro.button.finish).evaluate().isEmpty) {
    await tapLast(tester, find.text(translations.intro.button.next));
  }
  await tapLast(tester, find.text(translations.intro.button.finish));
  await waitFor(tester, find.textContaining(translations.home.empty.split('\n').first));
}

/// Adds a TOTP by hand with the RFC 6238 SHA-1 secret and the default parameters (U3).
Future<void> addManualTotp(WidgetTester tester, {required String label, required String issuer}) async {
  await tapLast(tester, find.byIcon(FLucideIcons.plus));
  await tapLast(tester, find.text(translations.home.addDialog.manually.title));
  await waitFor(tester, find.text(translations.totp.page.title.add));
  await tester.enterText(find.byType(EditableText).at(0), label);
  await tester.enterText(find.byType(EditableText).at(1), roundSha1Secret);
  await tester.enterText(find.byType(EditableText).at(2), issuer);
  await settle(tester, seconds: 2);
  await tapLast(tester, find.text(translations.totp.page.save));
  await waitGone(tester, find.text(translations.totp.page.title.add));
  await waitFor(tester, find.text(issuer));
}

/// Makes a backup from the settings page with [roundBackupPassword], and comes back to the settings page.
Future<void> backupNow(WidgetTester tester) async {
  await tapScrolled(tester, find.text(translations.settings.backups.backupNow.title));
  await answerPasswordDialog(tester, roundBackupPassword);
  await settle(tester, seconds: 3);
}

/// Clears the data from the settings page, keeping the backups (deleting them hits #141).
Future<void> clearDataKeepingBackups(WidgetTester tester, String masterPassword) async {
  await tapScrolled(tester, find.text(translations.settings.dangerZone.clearData.title));
  await tapLast(tester, find.text(okLabel(tester)));
  await answerPasswordDialog(tester, masterPassword);
  await waitFor(tester, find.text(translations.settings.dangerZone.clearData.backupDeleteConfirmationDialog.title));
  await tapLast(tester, find.text(materialLabels(tester).cancelButtonLabel));
  await settle(tester, seconds: 3);
}

/// The only TOTP code with [digits] digits on screen, spaces removed.
String shownCode(WidgetTester tester, int digits) {
  // The code is grouped with a (possibly non-breaking) space: keep the texts made of digits and spaces only.
  final RegExp grouped = RegExp(r'^[0-9\s]+$');
  final List<String> codes = [
    for (final Text text in tester.widgetList<Text>(find.byType(Text)))
      if (grouped.hasMatch(text.data ?? '') && (text.data ?? '').replaceAll(RegExp(r'\s'), '').length == digits) (text.data ?? '').replaceAll(RegExp(r'\s'), ''),
  ];
  expect(codes, hasLength(1), reason: 'TOTP codes on screen: $codes');
  return codes.single;
}

/// Checks that the only 6-digit code on screen is the RFC 6238 SHA-1 code of the current period, reading
/// it again once if a period boundary fell between the two reads (U5). Returns the code.
Future<String> expectReferenceCode(WidgetTester tester) async {
  final hashlib.TOTP reference = hashlib.TOTP(utf8.encode(roundSha1SecretRaw));
  String shown = shownCode(tester, 6);
  String expected = pad(reference.value(), 6);
  if (shown != expected) {
    await settle(tester, seconds: 2);
    shown = shownCode(tester, 6);
    expected = pad(reference.value(), 6);
  }
  expect(shown, expected);
  return shown;
}

/// Pads [value] with leading zeros to [digits] digits.
String pad(int value, int digits) => value.toString().padLeft(digits, '0');

/// Prints one result line for the run log.
void report(String item, String detail) => debugPrint('ROUND $item: $detail');
