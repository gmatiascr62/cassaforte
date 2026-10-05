import 'dart:convert';

import 'package:flutter/services.dart';

import '../session/vault_session.dart';
import '../storage/vault_store.dart';

enum BiometricAvailability {
  /// Hay huella o bloqueo de pantalla (patrón, PIN…) configurado.
  available,

  /// El teléfono no tiene huella ni bloqueo de pantalla configurados.
  notEnrolled,

  /// Android anterior a 11 o sin hardware compatible.
  unsupported,

  /// El sistema devolvió un error al comprobarlo.
  error,
}

/// El usuario canceló el diálogo de huella.
class BiometricCanceledException implements Exception {
  const BiometricCanceledException();
}

/// Android destruyó la llave del chip seguro (se cambiaron las huellas o se
/// quitó el bloqueo de pantalla). Hay que usar la contraseña maestra.
class BiometricInvalidatedException implements Exception {
  const BiometricInvalidatedException();
}

/// Cualquier otro fallo (demasiados intentos, error del sistema…).
class BiometricFailedException implements Exception {
  const BiometricFailedException(this.message);
  final String message;
  @override
  String toString() => 'BiometricFailedException: $message';
}

/// Clave de la bóveda cifrada por una llave del Android Keystore.
class WrappedKey {
  const WrappedKey({required this.iv, required this.data});
  final Uint8List iv;
  final Uint8List data;
}

/// Acceso al Android Keystore y al diálogo de huella del sistema.
abstract interface class BiometricPlatform {
  Future<BiometricAvailability> availability();

  /// Crea una llave nueva en el chip seguro (que exige huella o bloqueo de
  /// pantalla para cada uso) y cifra [key] con ella. Muestra el diálogo.
  Future<WrappedKey> wrap(Uint8List key);

  /// Muestra el diálogo y descifra la clave.
  Future<Uint8List> unwrap(WrappedKey wrapped);

  /// Borra la llave del chip seguro.
  Future<void> deleteKey();
}

class MethodChannelBiometricPlatform implements BiometricPlatform {
  const MethodChannelBiometricPlatform();

  static const MethodChannel _channel = MethodChannel('cassaforte/biometric');

  @override
  Future<BiometricAvailability> availability() async {
    try {
      final status = await _channel.invokeMethod<String>('status');
      return switch (status) {
        'available' => BiometricAvailability.available,
        'notEnrolled' => BiometricAvailability.notEnrolled,
        _ => BiometricAvailability.unsupported,
      };
    } on MissingPluginException {
      return BiometricAvailability.unsupported;
    } on PlatformException {
      return BiometricAvailability.error;
    }
  }

  @override
  Future<WrappedKey> wrap(Uint8List key) => _call(() async {
    final result = await _channel.invokeMapMethod<String, Object?>('wrap', {
      'key': key,
    });
    final iv = result?['iv'];
    final data = result?['data'];
    if (iv is! Uint8List || data is! Uint8List) {
      throw const BiometricFailedException('Respuesta no válida');
    }
    return WrappedKey(iv: iv, data: data);
  });

  @override
  Future<Uint8List> unwrap(WrappedKey wrapped) => _call(() async {
    final key = await _channel.invokeMethod<Uint8List>('unwrap', {
      'iv': wrapped.iv,
      'data': wrapped.data,
    });
    if (key == null) {
      throw const BiometricFailedException('Respuesta no válida');
    }
    return key;
  });

  @override
  Future<void> deleteKey() async {
    try {
      await _channel.invokeMethod<void>('deleteKey');
    } on MissingPluginException {
      // Sin canal nativo no hay llave que borrar.
    }
  }

  static Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'canceled':
          throw const BiometricCanceledException();
        case 'invalidated':
          throw const BiometricInvalidatedException();
        default:
          throw BiometricFailedException(e.message ?? e.code);
      }
    } on MissingPluginException {
      throw const BiometricFailedException('No disponible');
    }
  }
}

/// Desbloqueo con huella o con el bloqueo de pantalla del teléfono.
///
/// La clave de la bóveda se guarda cifrada con una llave AES-256-GCM del
/// Android Keystore que no se puede extraer del teléfono y que exige
/// autenticarse en cada uso. Android la destruye si se añaden huellas o se
/// quita el bloqueo de pantalla; entonces se pide la contraseña maestra.
class BiometricUnlock {
  BiometricUnlock({
    required VaultStore store,
    BiometricPlatform platform = const MethodChannelBiometricPlatform(),
  }) : _store = store,
       _platform = platform;

  final VaultStore _store;
  final BiometricPlatform _platform;

  Future<BiometricAvailability> availability() => _platform.availability();

  Future<bool> isEnabled() => _store.exists();

  /// Activa la huella con la clave de la sesión abierta.
  Future<void> enable(VaultSession session) async {
    final wrapped = await session.withKey(_platform.wrap);
    await _store.writeAtomic(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'iv': base64.encode(wrapped.iv),
            'data': base64.encode(wrapped.data),
          }),
        ),
      ),
    );
  }

  /// Borra la llave del chip seguro y la clave cifrada.
  Future<void> disable() async {
    await _store.delete();
    await _platform.deleteKey();
  }

  /// Muestra el diálogo y abre la sesión. Si la llave ya no sirve, desactiva
  /// la huella y lanza [BiometricInvalidatedException].
  Future<void> unlock(VaultSession session) async {
    final startedAt = session.lockGeneration;
    final wrapped = await _read();
    if (wrapped == null) {
      await disable();
      throw const BiometricInvalidatedException();
    }
    final Uint8List key;
    try {
      key = await _platform.unwrap(wrapped);
    } on BiometricInvalidatedException {
      await disable();
      rethrow;
    }
    try {
      await session.unlockWithKey(key, startedAt: startedAt);
    } on WrongPasswordException {
      // La clave guardada no corresponde a esta bóveda.
      await disable();
      throw const BiometricInvalidatedException();
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<WrappedKey?> _read() async {
    try {
      final doc = jsonDecode(utf8.decode(await _store.read()));
      if (doc is! Map<String, Object?> || doc['version'] != 1) return null;
      return WrappedKey(
        iv: base64.decode(doc['iv']! as String),
        data: base64.decode(doc['data']! as String),
      );
    } catch (_) {
      return null;
    }
  }
}
