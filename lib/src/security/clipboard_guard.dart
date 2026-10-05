import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resultado de intentar limpiar el portapapeles.
enum ClearResult {
  /// Se borró lo que había copiado la aplicación.
  cleared,

  /// El contenido cambió (el usuario copió otra cosa): no se toca.
  changed,

  /// El sistema no deja consultar el portapapeles ahora (p. ej., la
  /// aplicación está en segundo plano). Se reintentará más tarde.
  unavailable,
}

/// Acceso al portapapeles del sistema.
abstract interface class SecureClipboard {
  /// Copia [text] y devuelve un identificador de esa copia.
  Future<Object?> copy(String text);

  /// Borra el portapapeles solo si sigue conteniendo la copia [token].
  Future<ClearResult> clearIfUnchanged(Object? token, String text);
}

/// Implementación para Android mediante un canal nativo (ver
/// `MainActivity.kt`): marca el contenido como sensible (Android 13+) y
/// compara la marca de tiempo de la copia sin leer el texto. Si el canal no
/// existe, usa el portapapeles genérico de Flutter.
class PlatformSecureClipboard implements SecureClipboard {
  const PlatformSecureClipboard();

  static const MethodChannel _channel = MethodChannel('cassaforte/clipboard');

  @override
  Future<Object?> copy(String text) async {
    try {
      return await _channel.invokeMethod<Object?>('copySensitive', {
        'text': text,
      });
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      return null;
    }
  }

  @override
  Future<ClearResult> clearIfUnchanged(Object? token, String text) async {
    try {
      final result = await _channel.invokeMethod<String>('clearIfUnchanged', {
        'token': token,
        'text': text,
      });
      return switch (result) {
        'cleared' => ClearResult.cleared,
        'changed' => ClearResult.changed,
        _ => ClearResult.unavailable,
      };
    } on MissingPluginException {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null) return ClearResult.unavailable;
      if (data!.text != text) return ClearResult.changed;
      await Clipboard.setData(const ClipboardData(text: ''));
      return ClearResult.cleared;
    }
  }
}

/// Copia secretos al portapapeles y los borra pasado [clearAfter], sin
/// borrar lo que el usuario haya copiado después.
class ClipboardGuard {
  ClipboardGuard({
    SecureClipboard clipboard = const PlatformSecureClipboard(),
    this.clearAfter = const Duration(seconds: 20),
  }) : _clipboard = clipboard;

  final SecureClipboard _clipboard;
  final Duration clearAfter;

  Timer? _timer;
  _Pending? _pending;
  bool _due = false;

  @visibleForTesting
  bool get hasPending => _pending != null;

  /// Copia [text]. Sustituye a cualquier copia anterior pendiente.
  Future<void> copySecret(String text) async {
    _timer?.cancel();
    _pending = null;
    _due = false;
    final token = await _clipboard.copy(text);
    final pending = _Pending(token, text);
    _pending = pending;
    _timer = Timer(clearAfter, () {
      _due = true;
      unawaited(_tryClear(pending));
    });
  }

  /// Llamar al volver a primer plano: si el borrado quedó pendiente porque
  /// el sistema no permitía acceder al portapapeles, se reintenta.
  Future<void> onAppResumed() async {
    final pending = _pending;
    if (pending != null && _due) await _tryClear(pending);
  }

  Future<void> _tryClear(_Pending pending) async {
    if (!identical(pending, _pending)) return;
    ClearResult result;
    try {
      result = await _clipboard.clearIfUnchanged(pending.token, pending.text);
    } catch (_) {
      result = ClearResult.unavailable;
    }
    if (!identical(pending, _pending)) return;
    if (result != ClearResult.unavailable) {
      _pending = null;
      _due = false;
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}

class _Pending {
  _Pending(this.token, this.text);
  final Object? token;
  final String text;
}
