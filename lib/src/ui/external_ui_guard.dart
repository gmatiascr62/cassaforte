import 'dart:async';

import 'package:flutter/widgets.dart';

/// El diálogo de huella, el patrón del teléfono y el selector de archivos
/// son pantallas del sistema que ponen Cassaforte en segundo plano. Mientras
/// duran, no se bloquea por pasar a segundo plano (si no, sería imposible
/// usarlos). Al terminar, si la aplicación no ha vuelto a primer plano en
/// [returnTimeout], se bloquea. El bloqueo por inactividad sigue activo.
class ExternalUiGuard {
  ExternalUiGuard({this.returnTimeout = const Duration(seconds: 2)});

  final Duration returnTimeout;
  int _depth = 0;

  bool get active => _depth > 0;

  Future<T> run<T>(
    Future<T> Function() action, {
    required VoidCallback lock,
  }) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
      if (_depth == 0) await _lockUnlessForeground(lock);
    }
  }

  Future<void> _lockUnlessForeground(VoidCallback lock) async {
    if (_isResumed) return;
    final resumed = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!resumed.isCompleted) resumed.complete();
      },
    );
    try {
      await resumed.future.timeout(returnTimeout);
    } on TimeoutException {
      if (!_isResumed && !active) lock();
    } finally {
      listener.dispose();
    }
  }

  static bool get _isResumed =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
}
