import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../security/biometric_unlock.dart';
import '../session/vault_session.dart';
import '../storage/backup_files.dart';
import 'app_scope.dart';
import 'widgets/common.dart';

/// Acciones compartidas entre pantallas: copias de seguridad y huella.

String _backupName() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'cassaforte-${now.year}-${two(now.month)}-${two(now.day)}.cassaforte';
}

String _errorText(Object error) => switch (error) {
  WrongPasswordException() =>
    'Contraseña incorrecta o archivo alterado. No se ha modificado nada.',
  VaultCorruptedException() =>
    'El archivo no es una copia de Cassaforte válida o está dañado.',
  BackupFileException() => 'No se pudo leer o escribir el archivo.',
  VaultAlreadyExistsException() => 'Ya existe una bóveda; no se sobrescribe.',
  _ => 'No se pudo completar la operación.',
};

/// Exporta la bóveda cifrada a un archivo que elige el usuario.
Future<void> exportBackup(BuildContext context) async {
  final scope = AppScope.read(context);
  final password = await showPasswordPrompt(
    context,
    title: 'Exportar copia',
    message:
        'La copia queda cifrada con tu contraseña maestra: la vas a '
        'necesitar para restaurarla. Escribila para confirmar.',
    confirmLabel: 'Continuar',
  );
  if (password == null || !context.mounted) return;
  try {
    final bytes = await scope.session.exportBackup(password);
    final saved = await scope.runExternal(
      () => scope.backupFiles.save(_backupName(), bytes),
    );
    if (saved && context.mounted) {
      showMessage(
        context,
        'Copia guardada. Guardala también fuera del teléfono '
        '(nube, otro dispositivo…).',
      );
    }
  } on VaultLockedException {
    // La pantalla se cierra al bloquearse.
  } catch (e) {
    if (context.mounted) showMessage(context, _errorText(e));
  }
}

/// Elige un archivo de copia y lo descifra con la contraseña que indique el
/// usuario. Devuelve `null` si se cancela o falla (mostrando el error).
Future<({Uint8List bytes, String password})?> _pickBackup(
  BuildContext context,
) async {
  final scope = AppScope.read(context);
  final bytes = await scope.runExternal(scope.backupFiles.open);
  if (bytes == null || !context.mounted) return null;
  final password = await showPasswordPrompt(
    context,
    title: 'Abrir copia',
    message: 'Escribí la contraseña maestra con la que se hizo la copia.',
    confirmLabel: 'Abrir',
  );
  if (password == null) return null;
  return (bytes: bytes, password: password);
}

/// Importa las cuentas de una copia en la bóveda abierta.
Future<void> importBackup(BuildContext context) async {
  final scope = AppScope.read(context);
  try {
    final picked = await _pickBackup(context);
    if (picked == null || !context.mounted) return;
    final entries = await scope.session.openBackup(
      picked.bytes,
      picked.password,
    );
    if (!context.mounted) return;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar copia'),
        content: Text(
          'La copia tiene ${entries.length} cuenta(s).\n\n'
          '• Fusionar: añade las que faltan y actualiza las que en la copia '
          'son más recientes.\n'
          '• Reemplazar: borra las cuentas actuales y deja solo las de la '
          'copia.\n\nTu contraseña maestra actual no cambia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reemplazar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Fusionar'),
          ),
        ],
      ),
    );
    if (replace == null || !context.mounted) return;
    final result = await scope.session.importEntries(entries, replace: replace);
    if (context.mounted) {
      showMessage(
        context,
        replace
            ? 'Bóveda reemplazada: ${result.added} cuenta(s).'
            : 'Importadas ${result.added} nueva(s) y '
                  '${result.updated} actualizada(s).',
      );
    }
  } on VaultLockedException {
    // La pantalla se cierra al bloquearse.
  } catch (e) {
    if (context.mounted) showMessage(context, _errorText(e));
  }
}

/// Primera ejecución: restaura una copia como bóveda nueva. Devuelve un
/// mensaje de error o `null`.
Future<String?> restoreBackup(BuildContext context) async {
  final scope = AppScope.read(context);
  try {
    final picked = await _pickBackup(context);
    if (picked == null) return null;
    await scope.biometric.disable();
    await scope.session.restoreBackup(picked.bytes, picked.password);
    return null;
  } on VaultLockedException {
    return null;
  } catch (e) {
    return _errorText(e);
  }
}

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
