import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_authenticator/model/settings/entry.dart';

/// Whether the EzKey home zone is expanded or collapsed (#36).
enum EzkeyHomeZoneState {
  /// The user has not chosen yet: collapsed until the first enrollment, then expanded.
  auto,

  /// The user expanded the zone.
  expanded,

  /// The user collapsed the zone.
  collapsed;

  /// Whether the zone shows expanded, knowing whether there is at least one enrollment.
  bool isExpanded({required bool hasEnrollments}) => switch (this) {
    .auto => hasEnrollments,
    .expanded => true,
    .collapsed => false,
  };
}

/// The EzKey home zone state provider, remembered across launches.
final ezkeyHomeZoneStateProvider = AsyncNotifierProvider.autoDispose<EzkeyHomeZoneStateEntry, EzkeyHomeZoneState>(EzkeyHomeZoneStateEntry.new);

/// Remembers the user's last choice for the EzKey home zone.
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
