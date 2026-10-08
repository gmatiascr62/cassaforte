import 'package:flutter/material.dart';

import '../security/biometric_unlock.dart';
import '../session/vault_session.dart';
import 'app_scope.dart';
import 'widgets/common.dart';

/// Acciones compartidas entre pantallas: huella.

/// Activa la huella con la sesión abierta. Devuelve `true` si se activó.
Future<bool> enableBiometric(BuildContext context) async {
  final scope = AppScope.read(context);
  try {
    final availability = await scope.biometric.availability();
    if (availability != BiometricAvailability.available) {
      if (context.mounted) {
        showMessage(context, biometricUnavailableText(availability));
      }
      return false;
    }
    await scope.runExternal(() => scope.biometric.enable(scope.session));
    if (context.mounted) {
      showMessage(context, 'Desbloqueo con huella o patrón activado.');
    }
    return true;
  } on BiometricCanceledException {
    return false;
  } on VaultLockedException {
    return false;
  } catch (e) {
    if (context.mounted) {
      showMessage(
        context,
        e is BiometricFailedException
            ? 'No se pudo activar: ${e.message}'
            : 'No se pudo activar el desbloqueo con huella.',
      );
    }
    return false;
  }
}

String biometricUnavailableText(BiometricAvailability availability) =>
    switch (availability) {
      BiometricAvailability.available => '',
      BiometricAvailability.notEnrolled =>
        'Configurá una huella o un bloqueo de pantalla (patrón o PIN) en '
            'los ajustes del teléfono.',
      BiometricAvailability.unsupported =>
        'Este teléfono no es compatible (hace falta Android 11 o superior).',
      BiometricAvailability.error =>
        'No se pudo comprobar la huella en este teléfono.',
    };

/// Tras crear o restaurar la bóveda, ofrece activar la huella.
Future<void> offerBiometric(BuildContext context) async {
  final scope = AppScope.read(context);
  if (await scope.biometric.availability() != BiometricAvailability.available ||
      !context.mounted) {
    return;
  }
  final accept = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.fingerprint),
      title: const Text('¿Desbloquear con huella?'),
      content: const Text(
        'Podés abrir Cassaforte con tu huella o con el patrón del teléfono. '
        'La contraseña maestra se seguirá pidiendo para las copias de '
        'seguridad y si cambian las huellas del teléfono.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Activar'),
        ),
      ],
    ),
  );
  if (accept == true && context.mounted) await enableBiometric(context);
}
