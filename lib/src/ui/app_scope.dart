import 'package:flutter/material.dart';

import '../legal/terms.dart';
import '../security/biometric_unlock.dart';
import '../security/clipboard_guard.dart';
import '../security/password_generator.dart';
import '../session/vault_session.dart';
import '../storage/backup_files.dart';
import 'external_ui_guard.dart';

/// Da acceso a la sesión y a los servicios desde cualquier pantalla.
/// Reconstruye los widgets dependientes cuando cambia la sesión.
class AppScope extends InheritedNotifier<VaultSession> {
  const AppScope({
    super.key,
    required VaultSession session,
    required this.clipboard,
    required this.generator,
    required this.biometric,
    required this.backupFiles,
    required this.externalUi,
    required this.pending,
    required this.terms,
    required super.child,
  }) : super(notifier: session);

  final ClipboardGuard clipboard;
  final PasswordGenerator generator;
  final BiometricUnlock biometric;
  final BackupFiles backupFiles;
  final ExternalUiGuard externalUi;
  final PendingPrompts pending;
  final TermsAcceptance terms;

  /// Ejecuta una pantalla del sistema (huella, selector de archivos) sin
  /// que el paso a segundo plano bloquee la bóveda.
  Future<T> runExternal<T>(Future<T> Function() action) =>
      externalUi.run(action, lock: session.lock);

  VaultSession get session => notifier!;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado');
    return scope!;
  }

  /// Acceso sin suscribirse a los cambios.
  static AppScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado');
    return scope!;
  }
}

/// Avisos que se muestran al abrir la bóveda.
class PendingPrompts {
  /// Ofrecer activar la huella (tras crear o restaurar la bóveda).
  bool offerBiometric = false;

  /// Volver a activar la huella (Android invalidó la llave anterior).
  bool reenableBiometric = false;
}
