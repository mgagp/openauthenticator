import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/home_zone.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/widgets/clickable.dart';

/// How long an EzKey toast stays. Upstream toasts stay 1 second, short to read a sign-in outcome;
/// Material guidance is 4 to 10 seconds. forui keeps every toast until closed when Android reports
/// accessible navigation.
const Duration _kEzkeyToastDuration = Duration(seconds: 4);

/// Shows an EzKey success toast, in the EzKey blue so the service is recognizable.
FToasterEntry showEzkeySuccessToast(BuildContext context, {required String text}) => _showEzkeyToast(
  context,
  background: kEzkeyBlue,
  foreground: Colors.white,
  title: translations.miscellaneous.toast.success,
  text: text,
  icon: FLucideIcons.check,
);

/// Shows an EzKey error toast. Errors keep upstream's destructive color, whatever the service.
FToasterEntry showEzkeyErrorToast(BuildContext context, {required String text}) => _showEzkeyToast(
  context,
  background: context.theme.colors.destructive,
  foreground: context.theme.colors.destructiveForeground,
  title: translations.miscellaneous.toast.error,
  text: text,
  icon: FLucideIcons.circleAlert,
);

/// Shows a toast built like upstream's (`lib/widgets/toast.dart`), with the EzKey duration.
FToasterEntry _showEzkeyToast(
  BuildContext context, {
  required String title,
  required String text,
  required Color background,
  required Color foreground,
  required IconData icon,
}) => showFToast(
  context: context,
  style: .delta(
    decoration: .boxDelta(
      color: background,
    ),
    titleTextStyle: .delta(
      color: foreground,
    ),
    descriptionTextStyle: .delta(
      color: foreground,
    ),
    iconStyle: .delta(
      color: foreground,
    ),
  ),
  title: Text(title),
  description: Text(text),
  icon: Icon(icon),
  suffixBuilder: (context, entry) => ClickableButton.icon(
    variant: .ghost,
    style: .delta(
      decoration: .delta(
        [
          .all(
            .boxDelta(color: background),
          ),
        ],
      ),
    ),
    onPress: entry.dismiss,
    child: Icon(FLucideIcons.x, color: foreground),
  ),
  duration: _kEzkeyToastDuration,
);
