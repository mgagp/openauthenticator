import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// One piece of enrollment information: the value as the title, its label (and details) below.
class EzkeyInformationTile extends StatelessWidget with FTileMixin {
  /// The icon.
  final IconData icon;

  /// The label.
  final String label;

  /// The value (may be missing on the server side).
  final String? value;

  /// Optional details under the value.
  final String? details;

  /// Creates a new EzKey information tile instance.
  const EzkeyInformationTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.details,
  });

  @override
  Widget build(BuildContext context) => FTile(
    prefix: Icon(icon),
    title: Text(value == null || value!.isEmpty ? '—' : value!),
    subtitle: Text(details == null || details!.isEmpty ? label : '$label · $details'),
  );
}
