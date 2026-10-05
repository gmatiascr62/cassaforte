import 'package:flutter/material.dart';

import '../app_scope.dart';

/// Limita el ancho del contenido en pantallas grandes o en horizontal.
class CenteredBody extends StatelessWidget {
  const CenteredBody({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Campo de texto que no envía sugerencias ni aprendizaje al teclado y
/// cuenta como actividad para el bloqueo por inactividad.
class SecureTextField extends StatelessWidget {
  const SecureTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
    this.maxLines = 1,
    this.autofocus = false,
    this.helperText,
    this.enabled = true,
    this.monospace = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final int maxLines;
  final bool autofocus;
  final String? helperText;
  final bool enabled;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: obscure
          ? TextInputType.visiblePassword
          : (maxLines > 1 ? TextInputType.multiline : keyboardType),
      textInputAction: textInputAction,
      maxLines: obscure ? 1 : maxLines,
      minLines: 1,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      onChanged: (_) => AppScope.read(context).session.registerActivity(),
      style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
    );
  }
}

/// Botón para mostrar u ocultar una contraseña.
class VisibilityToggle extends StatelessWidget {
  const VisibilityToggle({
    super.key,
    required this.visible,
    required this.onChanged,
  });

  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
      onPressed: () => onChanged(!visible),
    );
  }
}

/// Aviso destacado sobre la imposibilidad de recuperar la bóveda.
class RecoveryWarning extends StatelessWidget {
  const RecoveryWarning({super.key});

  static const String text =
      'Cassaforte no guarda tu contraseña maestra ni tiene copias en la nube. '
      'Si la olvidas, o si se pierden los datos del móvil (al desinstalar la '
      'aplicación, borrar sus datos, restablecer o perder el teléfono), '
      'no habrá forma de recuperar tus contraseñas.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Copia un dato sensible y avisa de que se borrará.
Future<void> copySecret(
  BuildContext context,
  String value, {
  String what = 'Contraseña copiada',
}) async {
  final scope = AppScope.read(context);
  scope.session.registerActivity();
  await scope.clipboard.copySecret(value);
  if (!context.mounted) return;
  final seconds = scope.clipboard.clearAfter.inSeconds;
  showMessage(
    context,
    '$what. Se borrará del portapapeles en $seconds s '
    'si no copias otra cosa.',
  );
}

/// Pide una contraseña en un diálogo. Devuelve `null` si se cancela.
Future<String?> showPasswordPrompt(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Aceptar',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PasswordPromptDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            SecureTextField(
              controller: _controller,
              label: 'Contraseña maestra',
              obscure: !_visible,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              suffix: VisibilityToggle(
                visible: _visible,
                onChanged: (v) => setState(() => _visible = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
