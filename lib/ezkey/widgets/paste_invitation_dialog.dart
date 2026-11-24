import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_authenticator/i18n/translations.g.dart';
import 'package:open_authenticator/widgets/button_text.dart';
import 'package:open_authenticator/widgets/clickable.dart';
import 'package:open_authenticator/widgets/dialog/app_dialog.dart';

/// Asks the user to paste an EzKey invitation: the content of its QR code (ADR-0004 D5).
///
/// The text holds the invitation's bearer proof token, so nothing may keep it: no correction, no
/// suggestion, no keyboard learning, no autofill, and the field is emptied once read. Smart quotes are
/// off because the text is JSON. The app never reads the clipboard itself: the user pastes.
class EzkeyPasteInvitationDialog extends StatefulWidget {
  /// Creates a new paste invitation dialog instance.
  const EzkeyPasteInvitationDialog({
    super.key,
  });

  /// Shows the dialog and returns the pasted text, or `null` if the user cancelled.
  static Future<String?> prompt(BuildContext context) => showFDialog<String>(
    context: context,
    builder: (context, style, animation) => const EzkeyPasteInvitationDialog(),
  );

  @override
  State<EzkeyPasteInvitationDialog> createState() => _EzkeyPasteInvitationDialogState();
}

/// The paste invitation dialog state.
class _EzkeyPasteInvitationDialogState extends State<EzkeyPasteInvitationDialog> {
  /// The pasted text.
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(translations.ezkey.page.paste.dialogTitle),
    actions: [
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, child) => ClickableButton(
          onPress: value.text.trim().isEmpty ? null : _submit,
          child: ButtonText(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ),
      ClickableButton(
        variant: .secondary,
        onPress: () => Navigator.pop(context),
        child: ButtonText(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
    ],
    children: [
      Text(
        translations.ezkey.page.paste.dialogMessage,
        textAlign: TextAlign.left,
      ),
      FTextField.multiline(
        key: const ValueKey('ezkey-paste-field'),
        control: .managed(controller: _controller),
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
      ),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Empties the field, then closes the dialog with what it held.
  void _submit() {
    final String text = _controller.text.trim();
    _controller.clear();
    Navigator.pop(context, text);
  }
}
