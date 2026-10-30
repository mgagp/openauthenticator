import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/button_text.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/app_dialog.dart';
import 'package:open_authenticator/widgets/sized_scalable_image.dart';
import 'package:url_launcher/url_launcher.dart';

/// EzKey's website (EzKey `README.md`).
final Uri kEzkeyWebsite = Uri.parse('https://ezkey.org/');

/// EzKey's source code (EzKey `README.md`).
final Uri kEzkeySourceCode = Uri.parse('https://github.com/mgagp/ezkey');

/// Tells what EzKey is and where to learn more: EzKey is little known, so the home zone links to it.
class EzkeyAboutDialog extends StatelessWidget {
  /// Creates a new EzKey about dialog instance.
  const EzkeyAboutDialog({
    super.key,
  });

  /// Shows the dialog.
  static Future<void> show(BuildContext context) => showFDialog<void>(
    context: context,
    builder: (context, style, animation) => const EzkeyAboutDialog(),
  );

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(translations.ezkey.about.title),
    actions: [
      ClickableButton(
        variant: .secondary,
        onPress: () => Navigator.pop(context),
        child: ButtonText(MaterialLocalizations.of(context).closeButtonLabel),
      ),
    ],
    children: [
      const SizedScalableImage(
        asset: 'assets/images/ezkey_logo.si',
        width: 64,
        height: 64,
      ),
      const SizedBox(height: kSpace),
      Text(translations.ezkey.about.description),
      const SizedBox(height: kSpace),
      ClickableTile(
        key: const ValueKey('ezkey-about-website'),
        prefix: const Icon(FLucideIcons.globe),
        suffix: const Icon(FLucideIcons.externalLink),
        title: Text(translations.ezkey.about.website),
        subtitle: Text(kEzkeyWebsite.host),
        onPress: () => launchUrl(kEzkeyWebsite, mode: .externalApplication),
      ),
      ClickableTile(
        key: const ValueKey('ezkey-about-source'),
        prefix: const Icon(FLucideIcons.codeXml),
        suffix: const Icon(FLucideIcons.externalLink),
        title: Text(translations.ezkey.about.sourceCode),
        subtitle: Text('${kEzkeySourceCode.host}${kEzkeySourceCode.path}'),
        onPress: () => launchUrl(kEzkeySourceCode, mode: .externalApplication),
      ),
    ],
  );
}
