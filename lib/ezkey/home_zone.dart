import 'dart:math' as math;

import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/about.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/ezkey/home_zone_state.dart';
import 'package:open_authenticator/ezkey/identity.dart';
import 'package:open_authenticator/ezkey/installations.dart';
import 'package:open_authenticator/ezkey/pages/enrollment_page.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/ezkey/to_reenroll.dart';
import 'package:open_authenticator/ezkey/widgets/enrollment_tile.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/model/totp/repository.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/button_text.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/app_dialog.dart';
import 'package:open_authenticator/widgets/sized_scalable_image.dart';

/// The EzKey brand blue (EzKey `ezkey_mobile` theme `primary`, also in its logo).
const Color kEzkeyBlue = Color(0xFF3076DF);

/// Puts the upstream home content and the EzKey zone side by side (ADR-0003).
///
/// This is the only home-screen hook: the home page passes the list its builder returns through
/// this function. Where EzKey is not available ([ezkeyAvailable]), [totpChildren] comes back unchanged.
List<Widget> ezkeyHomeZones(List<Widget> totpChildren) => ezkeyAvailable && totpChildren.length == 1 ? [EzkeyHomeZones(totpZone: totpChildren.single)] : totpChildren;

/// The home zones: TOTP (upstream content, unchanged) above, EzKey below.
///
/// Expanded, both zones are framed. With EzKey collapsed (#36), the upstream content takes the full
/// height without a frame, so the app looks like the original, and EzKey is a thin bar at the bottom.
/// With the TOTP zone collapsed (#44), it is a thin bar at the top and EzKey takes the full height; the
/// upstream content stays in the tree, hidden, so it keeps its state.
///
/// While both zones are expanded, a divider between them sets how the height is shared (#32): drag it,
/// or use the screen reader's adjust actions; a double tap restores the automatic height.
class EzkeyHomeZones extends ConsumerStatefulWidget {
  /// The upstream home content (TOTP list or empty state, and its add button).
  final Widget totpZone;

  /// Creates a new EzKey home zones instance.
  const EzkeyHomeZones({
    super.key,
    required this.totpZone,
  });

  @override
  ConsumerState<EzkeyHomeZones> createState() => _EzkeyHomeZonesState();
}

/// The EzKey home zones state.
class _EzkeyHomeZonesState extends ConsumerState<EzkeyHomeZones> {
  /// How much a screen reader's adjust action changes the EzKey zone's share.
  static const double _shareStep = 0.1;

  /// The smallest EzKey zone height the divider allows: its header, a row and the add button stay usable.
  static const double _minEzkeyHeight = 240;

  /// The smallest TOTP zone height the divider allows.
  static const double _minTotpHeight = 160;

  /// Finds the EzKey zone, to measure the automatic height a drag starts from.
  final GlobalKey _ezkeyZoneKey = GlobalKey();

  /// The height the two zones share, from the last layout.
  double _sharedHeight = 0;

  /// The EzKey zone's share while the divider is being dragged, saved when the drag ends.
  double? _dragShare;

  @override
  Widget build(BuildContext context) {
    _ZonesState zones = _watchZones();
    // The same widget types in every state, so the upstream content keeps its state.
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _sharedHeight = constraints.maxHeight - _SplitHandle.height;
          _ZonesLayout layout = _layout(zones);
          return Column(
            crossAxisAlignment: .stretch,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: .topCenter,
                child: layout.totpExpanded ? const SizedBox(width: double.infinity) : const _TotpCollapsedBar(),
              ),
              Expanded(
                flex: layout.totpFlex,
                child: _TotpZone(
                  layout: layout,
                  child: widget.totpZone,
                ),
              ),
              _splitHandle(layout),
              Expanded(
                key: _ezkeyZoneKey,
                flex: layout.ezkeyFlex,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: .bottomCenter,
                  child: layout.expanded
                      ? _ZoneFrame(
                          margin: layout.ezkeyMargin,
                          child: EzkeyHomeZone(fill: layout.ezkeyFills),
                        )
                      : const _CollapsedBar(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Reads the state of both zones and the remembered share, and rebuilds when they change.
  _ZonesState _watchZones() {
    bool hasEnrollments = ref.watch(ezkeyInstallationsProvider).value?.isNotEmpty ?? false;
    // After a restore on a new device, the list to re-enroll is all the zone has to show, and it must be seen.
    bool hasToReenroll = ref.watch(ezkeyToReenrollProvider).value?.isNotEmpty ?? false;
    EzkeyHomeZoneState state = ref.watch(ezkeyHomeZoneStateProvider).value ?? .auto;
    return (
      expanded: state.isExpanded(hasEnrollments: hasEnrollments || hasToReenroll),
      totpExpanded: state.isTotpExpanded,
      savedShare: ref.watch(ezkeyHomeZoneSplitProvider).value ?? 0,
    );
  }

  /// Decides the layout of this screen for [zones].
  _ZonesLayout _layout(_ZonesState zones) {
    // Too little height for both minimums (small window, landscape): no divider.
    bool split = zones.expanded && zones.totpExpanded && _minShare <= _maxShare;
    // A share of 0 means automatic: the EzKey zone takes the height it needs. A remembered share is
    // kept within this screen's limits.
    double share = split ? (_dragShare ?? (zones.savedShare > 0 ? _clampShare(zones.savedShare) : 0)) : 0;
    return _ZonesLayout(
      expanded: zones.expanded,
      totpExpanded: zones.totpExpanded,
      split: split,
      share: share,
    );
  }

  /// The divider between the zones while [_ZonesLayout.split], else nothing.
  Widget _splitHandle(_ZonesLayout layout) => layout.split
      ? _SplitHandle(
          share: _currentShare(layout),
          step: _shareStep,
          onDragStart: _startDrag,
          onDrag: _drag,
          onDragEnd: _endDrag,
          onAdjust: (step) => _saveShare(_clampShare(_currentShare(layout) + step * _shareStep)),
          onReset: () => _saveShare(0),
        )
      : const SizedBox.shrink();

  /// The EzKey zone's share in [layout], measured while automatic.
  double _currentShare(_ZonesLayout layout) => layout.share > 0 ? layout.share : _measuredShare();

  /// The EzKey zone's share of the height in the last layout (automatic height included).
  double _measuredShare() {
    RenderBox? box = _ezkeyZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _sharedHeight <= 0) {
      return _clampShare(0);
    }
    return _clampShare(box.size.height / _sharedHeight);
  }

  /// The smallest share the EzKey zone can have on this screen.
  double get _minShare => _sharedHeight <= 0 ? 1 : math.max(EzkeyHomeZoneSplitEntry.minShare, _minEzkeyHeight / _sharedHeight);

  /// The largest share the EzKey zone can have on this screen.
  double get _maxShare => _sharedHeight <= 0 ? 0 : math.min(EzkeyHomeZoneSplitEntry.maxShare, 1 - _minTotpHeight / _sharedHeight);

  /// Keeps [share] between the limits, so neither zone gets too small to use.
  double _clampShare(double share) => share.clamp(_minShare, _maxShare);

  /// Starts a drag from the current share.
  void _startDrag() {
    double saved = ref.read(ezkeyHomeZoneSplitProvider).value ?? 0;
    setState(() => _dragShare = saved > 0 ? saved : _measuredShare());
  }

  /// Moves the divider by [delta] (downwards is positive) during a drag.
  void _drag(double delta) => setState(() => _dragShare = _clampShare(_dragShare! - delta / _sharedHeight));

  /// Ends a drag, and remembers where it ended.
  void _endDrag() {
    double? share = _dragShare;
    if (share != null) {
      _saveShare(share);
    }
  }

  /// Remembers [share] (`0` for automatic), and drops the drag value.
  void _saveShare(double share) {
    ref.read(ezkeyHomeZoneSplitProvider.notifier).changeValue(share);
    setState(() => _dragShare = null);
  }
}

/// What the home zones layout depends on: whether each zone is expanded, and the remembered share of the
/// EzKey zone (`0` for automatic).
typedef _ZonesState = ({bool expanded, bool totpExpanded, double savedShare});

/// How the home zones share the screen in one layout.
class _ZonesLayout {
  /// Whether the EzKey zone is expanded.
  final bool expanded;

  /// Whether the TOTP zone is expanded.
  final bool totpExpanded;

  /// Whether the divider is shown: both zones expanded, and enough height for both minimums.
  final bool split;

  /// The EzKey zone's share of the height, kept within this screen's limits; `0` while automatic.
  final double share;

  /// Creates a new zones layout instance.
  const _ZonesLayout({
    required this.expanded,
    required this.totpExpanded,
    required this.split,
    required this.share,
  });

  /// The EzKey zone's flex.
  int get ezkeyFlex => totpExpanded ? (share * 1000).round() : 1;

  /// The TOTP zone's flex: `0` while collapsed, an even share with automatic height, the rest otherwise.
  int get totpFlex {
    if (!totpExpanded) {
      return 0;
    }
    return share > 0 ? 1000 - ezkeyFlex : 1;
  }

  /// Whether the EzKey zone takes all the height it is given, instead of the height it needs.
  bool get ezkeyFills => !totpExpanded || share > 0;

  /// The space around the TOTP zone frame. The divider holds the space between the zones.
  EdgeInsets get totpMargin => EdgeInsets.fromLTRB(kSpace, 0, kSpace, split ? 0 : kSpace);

  /// The space around the EzKey zone frame.
  EdgeInsets get ezkeyMargin => EdgeInsets.fromLTRB(kSpace, totpExpanded ? 0 : kSpace, kSpace, kSpace);
}

/// The TOTP zone: the upstream content, framed with its header while EzKey is expanded. Collapsed, it
/// stays in the tree, hidden, so it keeps its state.
class _TotpZone extends StatelessWidget {
  /// The layout of the zones.
  final _ZonesLayout layout;

  /// The upstream home content.
  final Widget child;

  /// Creates a new TOTP zone instance.
  const _TotpZone({
    required this.layout,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: layout.totpExpanded ? null : 0,
    child: Visibility(
      visible: layout.totpExpanded,
      maintainState: true,
      child: _ZoneFrame(
        framed: layout.expanded,
        margin: layout.totpMargin,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            layout.expanded ? const _TotpHeader() : const SizedBox.shrink(),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// The divider between the expanded zones: a grip to drag, a slider for screen readers.
class _SplitHandle extends StatelessWidget {
  /// The divider height, which is also the space between the zones.
  static const double height = 24;

  /// The EzKey zone's share, measured while automatic.
  final double share;

  /// How much one adjust action changes [share].
  final double step;

  /// Called when a drag starts.
  final VoidCallback onDragStart;

  /// Called with the vertical distance of each drag move (downwards is positive).
  final ValueChanged<double> onDrag;

  /// Called when a drag ends.
  final VoidCallback onDragEnd;

  /// Called with `1` to make the EzKey zone bigger, `-1` to make it smaller.
  final ValueChanged<int> onAdjust;

  /// Called to restore the automatic height.
  final VoidCallback onReset;

  /// Creates a new split handle instance.
  const _SplitHandle({
    required this.share,
    required this.step,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onAdjust,
    required this.onReset,
  });

  /// Describes [share] for screen readers.
  static String _describe(double share) => translations.ezkey.home.splitValue(percent: (share * 100).round());

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('ezkey-home-split'),
    slider: true,
    label: translations.ezkey.home.split,
    value: _describe(share),
    increasedValue: _describe(share + step),
    decreasedValue: _describe(share - step),
    hint: translations.ezkey.home.splitReset,
    onIncrease: () => onAdjust(1),
    onDecrease: () => onAdjust(-1),
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: .opaque,
        onVerticalDragStart: (details) => onDragStart(),
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        onVerticalDragEnd: (details) => onDragEnd(),
        onDoubleTap: onReset,
        child: SizedBox(
          height: height,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.theme.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Expands or collapses the EzKey home zone, and remembers the choice. Collapsing it expands the TOTP zone.
void _setExpanded(WidgetRef ref, bool expanded) => ref.read(ezkeyHomeZoneStateProvider.notifier).changeValue(expanded ? .expanded : .collapsed);

/// Expands or collapses the TOTP home zone, and remembers the choice. Collapsing it expands the EzKey zone.
void _setTotpExpanded(WidgetRef ref, bool expanded) => ref.read(ezkeyHomeZoneStateProvider.notifier).changeValue(expanded ? .expanded : .totpCollapsed);

/// The header of the TOTP zone while both zones are expanded: the app logo, the name, and a chevron to
/// collapse it.
class _TotpHeader extends ConsumerWidget {
  /// Creates a new TOTP header instance.
  const _TotpHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(kSpace, kSpace / 2, kSpace, 0),
    child: Row(
      children: [
        const SizedScalableImage(
          asset: 'assets/images/logo.si',
          width: 24,
          height: 24,
        ),
        const SizedBox(width: kSpace),
        Expanded(
          child: Text(
            translations.ezkey.home.totpTitle,
            style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        // Icon only: a tooltip on long press, which also labels it for screen readers.
        Tooltip(
          message: translations.ezkey.home.totpCollapse,
          child: ClickableButton.icon(
            key: const ValueKey('ezkey-home-totp-collapse'),
            variant: .ghost,
            onPress: () => _setTotpExpanded(ref, false),
            child: const Icon(FLucideIcons.chevronUp),
          ),
        ),
      ],
    ),
  );
}

/// The collapsed TOTP zone: a thin bar at the top with the app logo, the name, the number of codes,
/// and a chevron. Adding a TOTP needs the zone expanded, where upstream's add button is.
class _TotpCollapsedBar extends ConsumerWidget {
  /// Creates a new TOTP collapsed bar instance.
  const _TotpCollapsedBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int? count = ref.watch(totpRepositoryProvider).value?.length;
    return _ZoneBar(
      tapKey: const ValueKey('ezkey-home-totp-expand'),
      label: translations.ezkey.home.totpExpand,
      onTap: () => _setTotpExpanded(ref, true),
      atTop: true,
      verticalPadding: kSpace,
      logo: 'assets/images/logo.si',
      title: translations.ezkey.home.totpTitle,
      trailing: [
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(right: kSpace),
            child: Text(
              translations.ezkey.home.totpCount(n: count),
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
            ),
          ),
        const Icon(FLucideIcons.chevronDown),
      ],
    );
  }
}

/// The collapsed EzKey zone: a thin bar with the logo, the name, "about", and a chevron.
class _CollapsedBar extends ConsumerWidget {
  /// Creates a new collapsed bar instance.
  const _CollapsedBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int toReenroll = ref.watch(ezkeyToReenrollProvider).value?.length ?? 0;
    return _ZoneBar(
      tapKey: const ValueKey('ezkey-home-expand'),
      label: translations.ezkey.home.expand,
      onTap: () => _setExpanded(ref, true),
      atTop: false,
      verticalPadding: kSpace / 2,
      logo: 'assets/images/ezkey_logo.si',
      title: translations.ezkey.home.title,
      trailing: [
        if (toReenroll > 0)
          Text(
            translations.ezkey.home.toReenroll(n: toReenroll),
            style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
          ),
        const _AboutButton(),
        const Icon(FLucideIcons.chevronUp),
      ],
    );
  }
}

/// A collapsed zone: a thin bar with the zone's logo and name, which expands the zone on tap.
class _ZoneBar extends StatelessWidget {
  /// The key of the tap target.
  final Key tapKey;

  /// What a screen reader says the bar does.
  final String label;

  /// Expands the zone.
  final VoidCallback onTap;

  /// Whether the bar is at the top of the screen: its border is then below it, else above it.
  final bool atTop;

  /// The space above and below the bar's content.
  final double verticalPadding;

  /// The zone's logo asset.
  final String logo;

  /// The zone's name.
  final String title;

  /// What follows the name: a count, buttons, the chevron.
  final List<Widget> trailing;

  /// Creates a new zone bar instance.
  const _ZoneBar({
    required this.tapKey,
    required this.label,
    required this.onTap,
    required this.atTop,
    required this.verticalPadding,
    required this.logo,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    BorderSide border = BorderSide(color: context.theme.colors.border, width: 2);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: tapKey,
        behavior: .opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: atTop ? Border(bottom: border) : Border(top: border),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: kBigSpace, vertical: verticalPadding),
            child: Row(
              children: [
                SizedScalableImage(
                  asset: logo,
                  width: 24,
                  height: 24,
                ),
                const SizedBox(width: kSpace),
                Expanded(
                  child: Text(
                    title,
                    style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                ...trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The ⓘ button that opens "About EzKey".
class _AboutButton extends StatelessWidget {
  /// Creates a new about button instance.
  const _AboutButton();

  // Icon only: a tooltip on long press, which also labels it for screen readers.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: translations.ezkey.about.open,
    child: ClickableButton.icon(
      key: const ValueKey('ezkey-home-about'),
      variant: .ghost,
      onPress: () => EzkeyAboutDialog.show(context),
      child: const Icon(FLucideIcons.info),
    ),
  );
}

/// Checks for requests on one enrollment (ADR-0006), the everyday action of the zone.
class _CheckButton extends ConsumerWidget {
  /// The enrollment to check.
  final EzkeyEnrollment enrollment;

  /// Creates a new check button instance.
  const _CheckButton({
    required this.enrollment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onPress() => EzkeyActions.checkPending(context, ref, enrollment);
    String name = EzkeyIdentity.of(enrollment).spokenName;
    if (ref.watch(ezkeySeveralInstallationsProvider)) {
      name = '$name, ${enrollment.authApiBaseUri.authority}';
    }
    // Inside a tile that merges its texts: without its own node, a screen reader would read the button with
    // the tile, and every row would offer the same "check".
    return Semantics(
      container: true,
      button: true,
      label: translations.ezkey.home.checkAction(integration: name),
      onTap: onPress,
      excludeSemantics: true,
      child: FButton(
        key: ValueKey('ezkey-home-check-${enrollment.localId}'),
        size: .sm,
        mainAxisSize: .min,
        // The whole zone uses the EzKey blue.
        style: .delta(
          decoration: .delta(
            [
              .base(const .boxDelta(color: kEzkeyBlue)),
            ],
          ),
          contentStyle: .delta(
            textStyle: .delta(
              [
                .all(const .delta(color: Colors.white)),
              ],
            ),
          ),
        ),
        onPress: onPress,
        child: ButtonText(translations.ezkey.home.check),
      ).clickable(),
    );
  }
}

/// The EzKey home zone: the enrollments, each with its own check for requests, and the add button.
class EzkeyHomeZone extends ConsumerWidget {
  /// The tallest the enrollment list gets before it scrolls, unless the zone [fill]s the screen: three rows and
  /// part of a fourth, which tells there is more.
  static const double _maxListHeight = 260;

  /// Whether the zone takes the full height (TOTP zone collapsed, #44): the list then scrolls in all the
  /// space there is.
  final bool fill;

  /// Creates a new EzKey home zone instance.
  const EzkeyHomeZone({
    super.key,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(kSpace),
    child: Column(
      mainAxisSize: fill ? .max : .min,
      crossAxisAlignment: .stretch,
      children: [
        const _EzkeyHeader(),
        const SizedBox(height: kSpace),
        ..._content(context, ref),
        const SizedBox(height: kSpace),
        // Alone in its corner, at the same distance from the frame as the upstream add button in
        // the TOTP zone (page padding), so both line up.
        Align(
          alignment: .centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: kBigSpace - kSpace, bottom: kBigSpace - kSpace),
            child: _AddButton(
              onPress: () => _addEnrollment(context, ref),
            ),
          ),
        ),
      ],
    ),
  );

  /// The zone's content under the header: an error, a progress indicator, or the enrollments.
  List<Widget> _content(BuildContext context, WidgetRef ref) {
    AsyncValue<List<EzkeyInstallation>> installations = ref.watch(ezkeyInstallationsProvider);
    ClickableTile? toReenrollTile = _toReenrollTile(context, ref);
    if (installations.hasError) {
      return [
        Text(
          translations.ezkey.home.loadError,
          style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.destructive),
        ),
        if (fill) const Spacer(),
      ];
    }
    if (installations.isLoading && !installations.hasValue) {
      return [
        const Center(child: FCircularProgress()),
        if (fill) const Spacer(),
      ];
    }
    List<EzkeyEnrollment> enrollments = [
      for (EzkeyInstallation installation in installations.value ?? []) ...installation.enrollments,
    ];
    return [
      enrollments.isEmpty
          ? _EmptyList(
              fill: fill,
              toReenrollTile: toReenrollTile,
            )
          : _EnrollmentList(
              fill: fill,
              enrollments: enrollments,
              toReenrollTile: toReenrollTile,
            ),
    ];
  }

  /// The row that says how many enrollments to re-enroll and leads to the EzKey page, or `null` when there is none.
  ClickableTile? _toReenrollTile(BuildContext context, WidgetRef ref) {
    int toReenroll = ref.watch(ezkeyToReenrollProvider).value?.length ?? 0;
    if (toReenroll == 0) {
      return null;
    }
    // In the scrolling part, so it never overflows at the smallest zone height.
    return ClickableTile(
      key: const ValueKey('ezkey-home-to-reenroll'),
      prefix: const Icon(FLucideIcons.rotateCcw),
      title: Text(translations.ezkey.home.toReenroll(n: toReenroll)),
      suffix: const Icon(FLucideIcons.chevronRight),
      onPress: () => EzkeyPage.open(context),
    );
  }

  /// Scans an invitation, or first asks how to add it when manual entry is allowed.
  Future<void> _addEnrollment(BuildContext context, WidgetRef ref) async {
    if (!ezkeyManualInvitationEntry) {
      await EzkeyActions.addFromScan(context, ref);
      return;
    }
    _AddChoice? choice = await showFDialog<_AddChoice>(
      context: context,
      builder: (context, style, animation) => AppDialog(
        title: Text(translations.ezkey.page.add),
        actions: [
          ClickableButton(
            variant: .secondary,
            onPress: () => Navigator.pop(context),
            child: ButtonText(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
        children: [
          ClickableTile(
            key: const ValueKey('ezkey-home-add-scan'),
            prefix: const Icon(FLucideIcons.qrCode),
            onPress: () => Navigator.pop(context, _AddChoice.scan),
            title: Text(translations.ezkey.page.scan.title),
            subtitle: Text(translations.ezkey.page.scan.subtitle),
          ),
          ClickableTile(
            key: const ValueKey('ezkey-home-add-paste'),
            prefix: const Icon(FLucideIcons.keyboard),
            onPress: () => Navigator.pop(context, _AddChoice.text),
            title: Text(translations.ezkey.page.paste.title),
            subtitle: Text(translations.ezkey.page.paste.subtitle),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) {
      return;
    }
    await switch (choice) {
      .scan => EzkeyActions.addFromScan(context, ref),
      .text => EzkeyActions.addFromText(context, ref),
    };
  }
}

/// The header of the EzKey zone: the logo and the name, which open "about", then the about, manage and
/// collapse buttons.
class _EzkeyHeader extends ConsumerWidget {
  /// Creates a new EzKey header instance.
  const _EzkeyHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      // The logo and the name also open "about": EzKey is little known.
      Expanded(
        child: GestureDetector(
          behavior: .opaque,
          onTap: () => EzkeyAboutDialog.show(context),
          child: Row(
            children: [
              const SizedScalableImage(
                asset: 'assets/images/ezkey_logo.si',
                width: 32,
                height: 32,
              ),
              const SizedBox(width: kSpace),
              Text(
                translations.ezkey.home.title,
                style: context.theme.typography.body.lg.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      const _AboutButton(),
      // Icon only: a tooltip on long press, which also labels it for screen readers.
      Tooltip(
        message: translations.ezkey.home.manage,
        child: ClickableButton.icon(
          key: const ValueKey('ezkey-home-manage'),
          variant: .ghost,
          onPress: () => EzkeyPage.open(context),
          child: const Icon(FLucideIcons.settings2),
        ),
      ),
      // Icon only: a tooltip on long press, which also labels it for screen readers.
      Tooltip(
        message: translations.ezkey.home.collapse,
        child: ClickableButton.icon(
          key: const ValueKey('ezkey-home-collapse'),
          variant: .ghost,
          onPress: () => _setExpanded(ref, false),
          child: const Icon(FLucideIcons.chevronDown),
        ),
      ),
    ],
  );
}

/// The EzKey zone without enrollment: an invitation to add one, under the row to re-enroll if any.
class _EmptyList extends StatelessWidget {
  /// Whether the zone takes the full height.
  final bool fill;

  /// The row that leads to the enrollments to re-enroll, if any.
  final ClickableTile? toReenrollTile;

  /// Creates a new empty list instance.
  const _EmptyList({
    required this.fill,
    this.toReenrollTile,
  });

  @override
  Widget build(BuildContext context) {
    ClickableTile? toReenrollTile = this.toReenrollTile;
    return Flexible(
      fit: fill ? .tight : .loose,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (toReenrollTile != null) ...[
              FTileGroup(children: [toReenrollTile]),
              const SizedBox(height: kSpace),
            ],
            Text(
              translations.ezkey.home.empty,
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

/// The enrollments of the EzKey zone, each with its own check, under the row to re-enroll if any.
class _EnrollmentList extends ConsumerWidget {
  /// Whether the zone takes the full height: the list then scrolls in all the space there is.
  final bool fill;

  /// The enrollments, of every installation.
  final List<EzkeyEnrollment> enrollments;

  /// The row that leads to the enrollments to re-enroll, if any.
  final ClickableTile? toReenrollTile;

  /// Creates a new enrollment list instance.
  const _EnrollmentList({
    required this.fill,
    required this.enrollments,
    this.toReenrollTile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => Flexible(
    fit: fill ? .tight : .loose,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: fill ? double.infinity : EzkeyHomeZone._maxListHeight),
      child: SingleChildScrollView(
        child: FTileGroup(
          children: [
            ?toReenrollTile,
            // Flat, with the server when there are several installations (ADR-0007).
            for (EzkeyEnrollment enrollment in enrollments)
              EzkeyEnrollmentTile(
                enrollment: enrollment,
                showServer: ref.watch(ezkeySeveralInstallationsProvider),
                onPress: () => EzkeyEnrollmentPage.open(context, enrollment),
                suffix: _CheckButton(enrollment: enrollment),
              ),
          ],
        ),
      ),
    ),
  );
}

/// How the user adds an enrollment.
enum _AddChoice {
  /// Scan the invitation QR code.
  scan,

  /// Type or paste the invitation content.
  text,
}

/// The blue round add button of the EzKey zone, built like the upstream floating add button
/// (`lib/pages/home/scroll/fab.dart`) so both have the same size.
class _AddButton extends StatelessWidget {
  /// Triggered when the button is pressed.
  final VoidCallback onPress;

  /// Creates a new add button instance.
  const _AddButton({
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: translations.ezkey.page.add,
    child: ClickableButton(
      key: const ValueKey('ezkey-home-add'),
      style: .delta(
        decoration: .delta([
          .base(
            .value(
              BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: context.theme.style.shadow,
                color: kEzkeyBlue,
              ),
            ),
          ),
        ]),
      ),
      mainAxisSize: .min,
      onPress: onPress,
      child: const Icon(
        FLucideIcons.plus,
        size: 40,
        color: Colors.white,
      ),
    ),
  );
}

/// A home zone frame: a rounded border, the same for both zones, thick enough to notice. Unframed,
/// it keeps the same widget tree with no margin and no border.
class _ZoneFrame extends StatelessWidget {
  /// Whether to show the frame.
  final bool framed;

  /// The space around the frame.
  final EdgeInsets margin;

  /// The zone content.
  final Widget child;

  /// Creates a new zone frame instance.
  const _ZoneFrame({
    this.framed = true,
    required this.margin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: framed ? margin : EdgeInsets.zero,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: framed ? Border.all(color: context.theme.colors.border, width: 2) : null,
        borderRadius: framed ? context.theme.style.borderRadius.md : null,
      ),
      child: ClipRRect(
        borderRadius: framed ? context.theme.style.borderRadius.md : BorderRadius.zero,
        child: child,
      ),
    ),
  );
}
