import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// One piece of enrollment information: the value as the title, its label (and details) below.
///
/// The value is never cut: the end of a server address is what tells whose it is, and the user decides
/// on it whom to trust.
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
    title: Text(
      value == null || value!.isEmpty ? '—' : value!,
      // forui's tile keeps its title on one line, and a null here would inherit that: no real value reaches this.
      maxLines: 100,
      softWrap: true,
    ),
    subtitle: Text(details == null || details!.isEmpty ? label : '$label · $details'),
  );
}
