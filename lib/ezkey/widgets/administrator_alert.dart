import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/spacing.dart';

/// Warns, under the tiles of an enrollment, that it belongs to an EzKey administrator.
class EzkeyAdministratorAlert extends StatelessWidget {
  /// What the warning says.
  final String text;

  /// Creates a new EzKey administrator alert instance.
  const EzkeyAdministratorAlert({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: kSpace),
    child: FAlert(
      icon: const Icon(FLucideIcons.shieldAlert),
      title: Text(text),
    ),
  );
}
