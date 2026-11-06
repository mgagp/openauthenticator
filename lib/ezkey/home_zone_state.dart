import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/model/settings/entry.dart';

/// Which home zones are expanded (#36, #44). One state for both zones, so they are never both
/// collapsed: collapsing one expands the other.
enum EzkeyHomeZoneState {
  /// The user has not chosen yet: the TOTP zone is expanded, and the EzKey zone is collapsed until there is
  /// something to show (an enrollment, or one to re-enroll after a restore), then expanded.
  auto,

  /// The user expanded both zones.
  expanded,

  /// The user collapsed the EzKey zone: the TOTP zone takes the full height.
  collapsed,

  /// The user collapsed the TOTP zone: the EzKey zone takes the full height.
  totpCollapsed;

  /// Whether the EzKey zone shows expanded, knowing whether it has something to show ([hasEnrollments]).
  bool isExpanded({required bool hasEnrollments}) => switch (this) {
    .auto => hasEnrollments,
    .expanded || .totpCollapsed => true,
    .collapsed => false,
  };

  /// Whether the TOTP zone shows expanded.
  bool get isTotpExpanded => this != .totpCollapsed;
}

/// The EzKey home zone state provider, remembered across launches.
final ezkeyHomeZoneStateProvider = AsyncNotifierProvider.autoDispose<EzkeyHomeZoneStateEntry, EzkeyHomeZoneState>(EzkeyHomeZoneStateEntry.new);

/// Remembers the user's last choice for the home zones.
class EzkeyHomeZoneStateEntry extends EnumSettingsEntry<EzkeyHomeZoneState> {
  /// Creates a new EzKey home zone state entry instance.
  EzkeyHomeZoneStateEntry()
    : super(
        key: 'ezkeyHomeZoneState',
        defaultValue: EzkeyHomeZoneState.auto,
      );

  @override
  @protected
  List<EzkeyHomeZoneState> get values => EzkeyHomeZoneState.values;
}

/// The EzKey zone's share of the home height while both zones are expanded (#32), remembered across
/// launches. `0` (the default) lets the EzKey zone take the height it needs, up to a cap.
final ezkeyHomeZoneSplitProvider = AsyncNotifierProvider.autoDispose<EzkeyHomeZoneSplitEntry, double>(EzkeyHomeZoneSplitEntry.new);

/// Remembers where the user dragged the divider between the home zones.
class EzkeyHomeZoneSplitEntry extends SettingsEntry<double> {
  /// The smallest share the EzKey zone can be given.
  static const double minShare = 0.25;

  /// The largest share the EzKey zone can be given.
  static const double maxShare = 0.75;

  /// Creates a new EzKey home zone split entry instance.
  EzkeyHomeZoneSplitEntry()
    : super(
        key: 'ezkeyHomeZoneSplit',
        defaultValue: 0,
      );
}
