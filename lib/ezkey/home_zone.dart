import 'package:ezkey_dart/ezkey_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/about.dart';
import 'package:open_authenticator/ezkey/actions.dart';
import 'package:open_authenticator/ezkey/home_zone_state.dart';
import 'package:open_authenticator/ezkey/installations.dart';
import 'package:open_authenticator/ezkey/pages/ezkey_page.dart';
import 'package:open_authenticator/ezkey/widgets/enrollment_tile.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/utils/platform.dart';
import 'package:open_authenticator/widgets/button_text.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/app_dialog.dart';
import 'package:open_authenticator/widgets/sized_scalable_image.dart';

/// The EzKey brand blue (EzKey `ezkey_mobile` theme `primary`, also in its logo).
const Color kEzkeyBlue = Color(0xFF3076DF);

/// Puts the upstream home content and the EzKey zone side by side (ADR-0003).
///
/// This is the only home-screen hook: the home page passes the list its builder returns through
/// this function. Off Android, EzKey is not available and [totpChildren] comes back unchanged.
List<Widget> ezkeyHomeZones(List<Widget> totpChildren) => currentPlatform == .android && totpChildren.length == 1 ? [EzkeyHomeZones(totpZone: totpChildren.single)] : totpChildren;

/// The home zones: TOTP (upstream content, unchanged) above, EzKey below.
///
/// Expanded, both zones are framed. Collapsed (#36), the upstream content takes the full height
/// without a frame, so the app looks like the original, and EzKey is a thin bar at the bottom.
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
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            // Same widget tree framed or not, so the upstream content keeps its state.
            child: _ZoneFrame(
              framed: expanded,
              margin: const EdgeInsets.fromLTRB(kSpace, 0, kSpace, kSpace),
              child: totpZone,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: .bottomCenter,
            child: expanded
                ? const _ZoneFrame(
                    margin: EdgeInsets.fromLTRB(kSpace, 0, kSpace, kSpace),
                    child: EzkeyHomeZone(),
                  )
                : const _CollapsedBar(),
          ),
        ],
      ),
    );
  }
}

/// Expands or collapses the EzKey home zone, and remembers the choice.
void _setExpanded(WidgetRef ref, bool expanded) => ref.read(ezkeyHomeZoneStateProvider.notifier).changeValue(expanded ? .expanded : .collapsed);

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

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: translations.ezkey.about.open,
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
  /// The most enrollment rows shown before the list scrolls.
  static const double _maxListHeight = 200;

  /// Creates a new EzKey home zone instance.
  const EzkeyHomeZone({
    super.key,
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
        mainAxisSize: .min,
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
              Semantics(
                button: true,
                label: translations.ezkey.home.collapse,
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
          if (installations.hasError)
            Text(
              translations.ezkey.home.loadError,
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.destructive),
            )
          else if (installations.isLoading && !installations.hasValue)
            const Center(child: FCircularProgress())
          else if (enrollments.isEmpty)
            Text(
              translations.ezkey.home.empty,
              style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground),
            )
          else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              child: SingleChildScrollView(
                child: FTileGroup(
                  children: [
                    // Phase 1 shows the installations flat (ADR-0003); #26 frames each one.
                    for (EzkeyEnrollment enrollment in enrollments)
                      EzkeyEnrollmentTile(
                        enrollment: enrollment,
                        onPress: () => EzkeyPage.open(context),
                      ),
                  ],
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
