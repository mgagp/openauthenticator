import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/pages/settings/entries/widgets.dart';
import 'package:open_authenticator/widgets/clickable.dart';

/// Opens the EzKey page from the settings (upstream hook, docs/ezkey/integration.md).
class EzkeySettingsEntryWidget extends StatelessWidget with FTileMixin {
  /// Creates a new EzKey settings entry widget instance.
  const EzkeySettingsEntryWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) => ClickableTile(
    key: const ValueKey('ezkey-settings-entry'),
    suffix: const RightChevronSuffix(),
    prefix: const Icon(FLucideIcons.shieldCheck),
    title: Text(translations.ezkey.settingsEntry.title),
    subtitle: Text(translations.ezkey.settingsEntry.subtitle),
    onPress: () => EzkeyPage.open(context),
  );
}
