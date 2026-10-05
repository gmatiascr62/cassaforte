import 'package:flutter/material.dart';

import '../security/clipboard_guard.dart';
import '../security/password_generator.dart';
import '../session/vault_session.dart';

/// Da acceso a la sesión y a los servicios desde cualquier pantalla.
/// Reconstruye los widgets dependientes cuando cambia la sesión.
class AppScope extends InheritedNotifier<VaultSession> {
  const AppScope({
    super.key,
    required VaultSession session,
    required this.clipboard,
    required this.generator,
    required super.child,
  }) : super(notifier: session);

  final ClipboardGuard clipboard;
  final PasswordGenerator generator;

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
