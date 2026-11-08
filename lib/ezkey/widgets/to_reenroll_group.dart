import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:open_authenticator/ezkey/backup_inventory.dart';
import 'package:open_authenticator/ezkey/to_reenroll.dart';
import 'package:open_authenticator/ezkey/toast.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/spacing.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/confirmation_dialog.dart';

/// Lists the enrollments to re-enroll after a backup restore. Takes no space when there is none, or when the
/// list cannot be loaded: it is a reminder, and must not get in the way of the EzKey page.
class EzkeyToReenrollGroup extends ConsumerWidget {
  /// Creates a new EzKey to re-enroll group instance.
  const EzkeyToReenrollGroup({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<EzkeyInventoryEntry> entries = ref.watch(ezkeyToReenrollProvider).value ?? const [];
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: kBigSpace),
      child: FTileGroup(
        label: Text(translations.ezkey.toReenroll.title),
        description: Text(translations.ezkey.toReenroll.help),
        children: [
          for (EzkeyInventoryEntry entry in entries)
            _EzkeyToReenrollTile(
              entry: entry,
              onRemove: () => _remove(context, ref, entry),
            ),
        ],
      ),
    );
  }

  /// Removes [entry] from the list after confirmation.
  Future<void> _remove(BuildContext context, WidgetRef ref, EzkeyInventoryEntry entry) async {
    bool confirmed = await ConfirmationDialog.ask(
      context,
      title: translations.ezkey.toReenroll.remove.confirmTitle,
      message: translations.ezkey.toReenroll.remove.confirmMessage(integration: _name(entry)),
      okButtonVariant: .destructive,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(ezkeyToReenrollProvider.notifier).remove(entry);
    } on Object catch (ex) {
      debugPrint('EzKey list to re-enroll not updated: $ex');
      if (context.mounted) {
        showEzkeyErrorToast(context, text: translations.ezkey.toReenroll.remove.error);
      }
    }
  }
}

/// Returns the name that designates [entry], the server when it has no integration name.
String _name(EzkeyInventoryEntry entry) {
  String? integration = entry.integrationName;
  return integration == null || integration.isEmpty ? entry.authApiHost : integration;
}

/// Shows one enrollment to re-enroll, with what an administrator needs to find it.
class _EzkeyToReenrollTile extends StatelessWidget with FTileMixin {
  /// The entry.
  final EzkeyInventoryEntry entry;

  /// Triggered when the user asks to remove the entry.
  final VoidCallback onRemove;

  /// Creates a new EzKey to re-enroll tile instance.
  const _EzkeyToReenrollTile({
    required this.entry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // The account first: one line can be cut, and it matters more than the organization.
    String account = [entry.enrollmentName, entry.tenantName].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    String date = MaterialLocalizations.of(context).formatShortDate(entry.enrolledAt.toLocal());
    String action = translations.ezkey.toReenroll.remove.action(integration: _name(entry));
    return FTile(
      prefix: const Icon(FLucideIcons.rotateCcw),
      title: Text(entry.integrationName ?? '—'),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: [
          if (account.isNotEmpty) Text(account, maxLines: 1, overflow: .ellipsis),
          Text(entry.authApiHost, maxLines: 1, overflow: .ellipsis),
          Text(
            translations.ezkey.toReenroll.details(date: date, id: entry.enrollmentId),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ],
      ),
      // Icon only, inside a tile that merges its texts: without its own node, a screen reader would read the
      // tooltip with the tile and find a button with no name.
      suffix: Semantics(
        container: true,
        button: true,
        label: action,
        onTap: onRemove,
        excludeSemantics: true,
        child: Tooltip(
          message: action,
          child: ClickableButton.icon(
            key: ValueKey('ezkey-to-reenroll-remove-${entry.enrollmentId}'),
            variant: .ghost,
            onPress: onRemove,
            child: const Icon(FLucideIcons.x),
          ),
        ),
      ),
    );
  }
}
