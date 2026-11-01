import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/about.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/availability.dart';
import 'package:open_authenticator/ezkey/home_zone_state.dart';
import 'package:open_authenticator/ezkey/installations.dart';
import 'package:open_authenticator/ezkey/pages/enrollment_page.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
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
class EzkeyHomeZones extends ConsumerWidget {
  /// The upstream home content (TOTP list or empty state, and its add button).
  final Widget totpZone;

  /// Creates a new EzKey home zones instance.
  const EzkeyHomeZones({
    super.key,
    required this.totpZone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool hasEnrollments = ref.watch(ezkeyInstallationsProvider).value?.isNotEmpty ?? false;
    EzkeyHomeZoneState state = ref.watch(ezkeyHomeZoneStateProvider).value ?? .auto;
    bool expanded = state.isExpanded(hasEnrollments: hasEnrollments);
    bool totpExpanded = state.isTotpExpanded;
    // The same widget types in every state, so the upstream content keeps its state.
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: .topCenter,
            child: totpExpanded ? const SizedBox(width: double.infinity) : const _TotpCollapsedBar(),
          ),
          Expanded(
            flex: totpExpanded ? 1 : 0,
            child: SizedBox(
              height: totpExpanded ? null : 0,
              child: Visibility(
                visible: totpExpanded,
                maintainState: true,
                child: _ZoneFrame(
                  framed: expanded,
                  margin: const EdgeInsets.fromLTRB(kSpace, 0, kSpace, kSpace),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      expanded ? const _TotpHeader() : const SizedBox.shrink(),
                      Expanded(child: totpZone),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: totpExpanded ? 0 : 1,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: .bottomCenter,
              child: expanded
                  ? _ZoneFrame(
                      margin: EdgeInsets.fromLTRB(kSpace, totpExpanded ? 0 : kSpace, kSpace, kSpace),
                      child: EzkeyHomeZone(fill: !totpExpanded),
                    )
                  : const _CollapsedBar(),
            ),
          ),
        ],
      ),
    );
  }
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
    return Semantics(
      button: true,
      label: translations.ezkey.home.totpExpand,
      child: GestureDetector(
        key: const ValueKey('ezkey-home-totp-expand'),
        behavior: .opaque,
        onTap: () => _setTotpExpanded(ref, true),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.theme.colors.border, width: 2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kBigSpace, vertical: kSpace),
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
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsed EzKey zone: a thin bar with the logo, the name, "about", and a chevron.
class _CollapsedBar extends ConsumerWidget {
  /// Creates a new collapsed bar instance.
  const _CollapsedBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    button: true,
    label: translations.ezkey.home.expand,
    child: GestureDetector(
      key: const ValueKey('ezkey-home-expand'),
      behavior: .opaque,
      onTap: () => _setExpanded(ref, true),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.theme.colors.border, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kBigSpace, vertical: kSpace / 2),
          child: Row(
            children: [
              const SizedScalableImage(
                asset: 'assets/images/ezkey_logo.si',
                width: 24,
                height: 24,
              ),
              const SizedBox(width: kSpace),
              Expanded(
                child: Text(
                  translations.ezkey.home.title,
                  style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const _AboutButton(),
              const Icon(FLucideIcons.chevronUp),
            ],
          ),
        ),
      ),
    ),
  );
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

/// The EzKey home zone: the enrollments, "check for requests" and the add button.
class EzkeyHomeZone extends ConsumerWidget {
  /// The most enrollment rows shown before the list scrolls, unless the zone [fill]s the screen.
  static const double _maxListHeight = 200;

  /// Whether the zone takes the full height (TOTP zone collapsed, #44): the list then scrolls in all the
  /// space there is.
  final bool fill;

  /// Creates a new EzKey home zone instance.
  const EzkeyHomeZone({
    super.key,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AsyncValue<List<EzkeyInstallation>> installations = ref.watch(ezkeyInstallationsProvider);
    List<EzkeyEnrollment> enrollments = [
      for (EzkeyInstallation installation in installations.value ?? []) ...installation.enrollments,
    ];
    return Padding(
      padding: const EdgeInsets.all(kSpace),
      child: Column(
        mainAxisSize: fill ? .max : .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
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
          ),
          const SizedBox(height: kSpace),
          if (installations.hasError) ...[
            Text(
              translations.ezkey.home.loadError,
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.destructive),
            ),
            if (fill) const Spacer(),
          ] else if (installations.isLoading && !installations.hasValue) ...[
            const Center(child: FCircularProgress()),
            if (fill) const Spacer(),
          ] else if (enrollments.isEmpty) ...[
            Text(
              translations.ezkey.home.empty,
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
            ),
            if (fill) const Spacer(),
          ] else ...[
            Flexible(
              fit: fill ? .tight : .loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: fill ? double.infinity : _maxListHeight),
                child: SingleChildScrollView(
                  child: FTileGroup(
                    children: [
                      // Phase 1 shows the installations flat (ADR-0003); #26 frames each one.
                      for (EzkeyEnrollment enrollment in enrollments)
                        EzkeyEnrollmentTile(
                          enrollment: enrollment,
                          onPress: () => EzkeyEnrollmentPage.open(context, enrollment),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: kSpace),
            ClickableButton(
              key: const ValueKey('ezkey-home-check'),
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
                  iconStyle: .delta(
                    [
                      .all(const .delta(color: Colors.white)),
                    ],
                  ),
                ),
              ),
              prefix: const Icon(FLucideIcons.bellRing),
              onPress: () => EzkeyActions.checkPending(context, ref, enrollments),
              child: ButtonText(translations.ezkey.home.check),
            ),
          ],
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
