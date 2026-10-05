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
