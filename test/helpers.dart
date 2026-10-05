import 'dart:async';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/kdf.dart';
import 'package:cassaforte/src/security/biometric_unlock.dart';
import 'package:cassaforte/src/security/clipboard_guard.dart';
import 'package:cassaforte/src/storage/backup_files.dart';
import 'package:cassaforte/src/storage/vault_store.dart';

/// Parámetros de Argon2id mínimos para que las pruebas sean rápidas.
/// La aplicación usa [KdfParams.generate] con los valores por defecto.
KdfParams fastKdfParams() =>
    KdfParams.generate(memoryKiB: 64, iterations: 1, parallelism: 1);

/// Almacén en memoria que cuenta escrituras.
class MemoryVaultStore implements VaultStore {
  Uint8List? bytes;
  int writes = 0;
  bool failWrites = false;

  /// Si no es nulo, las escrituras esperan a que se complete.
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  @override
  Future<bool> exists() async => bytes != null;

  @override
  Future<Uint8List> read() async {
    final b = bytes;
    if (b == null) throw StateError('No existe');
    return Uint8List.fromList(b);
  }

  @override
  Future<void> delete() async => bytes = null;

  @override
  Future<void> writeAtomic(Uint8List data) async {
    if (failWrites) throw StateError('Fallo de escritura simulado');
    writeStarted?.complete();
    final gate = writeGate;
    if (gate != null) await gate.future;
    writes++;
    bytes = Uint8List.fromList(data);
  }
}

/// Derivación que se detiene hasta que la prueba la libera, para poder
/// bloquear la sesión mientras está en curso.
class ControlledKdf implements KeyDerivation {
  ControlledKdf([this.inner = const Argon2idKeyDerivation()]);

  final KeyDerivation inner;
  Completer<void>? gate;
  int calls = 0;

  void hold() => gate = Completer<void>();
  void release() => gate?.complete();

  @override
  Future<Uint8List> deriveKey(String password, KdfParams params) async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    return inner.deriveKey(password, params);
  }
}

/// Portapapeles simulado con identificador por copia, como el nativo.
class FakeClipboard implements SecureClipboard {
  String? content;
  int _counter = 0;
  int? _currentToken;
  bool accessible = true;
  int clears = 0;

  @override
  Future<Object?> copy(String text) async {
    content = text;
    _currentToken = ++_counter;
    return _currentToken;
  }

  /// Copia hecha por otra aplicación o por el usuario.
  void userCopies(String text) {
    content = text;
    _currentToken = ++_counter;
  }

  @override
  Future<ClearResult> clearIfUnchanged(Object? token, String text) async {
    if (!accessible) return ClearResult.unavailable;
    if (token != _currentToken) return ClearResult.changed;
    content = null;
    clears++;
    return ClearResult.cleared;
  }
}

/// Keystore simulado: "cifra" con XOR y una llave aleatoria; puede simular
/// cancelación o invalidación.
class FakeBiometricPlatform implements BiometricPlatform {
  BiometricAvailability status = BiometricAvailability.available;
  Uint8List? _hwKey;
  bool cancelNext = false;
  int prompts = 0;

  /// Simula que el usuario añadió una huella (Android destruye la llave).
  void invalidate() => _hwKey = null;

  bool get hasKey => _hwKey != null;

  bool failStatus = false;

  @override
  Future<BiometricAvailability> availability() async {
    if (failStatus) throw StateError('Fallo del sistema simulado');
    return status;
  }

  @override
  Future<WrappedKey> wrap(Uint8List key) async {
    prompts++;
    if (cancelNext) {
      cancelNext = false;
      throw const BiometricCanceledException();
    }
    _hwKey = randomBytes(key.length);
    return WrappedKey(iv: randomBytes(12), data: _xor(key, _hwKey!));
  }

  @override
  Future<Uint8List> unwrap(WrappedKey wrapped) async {
    final hw = _hwKey;
    if (hw == null) throw const BiometricInvalidatedException();
    prompts++;
    if (cancelNext) {
      cancelNext = false;
      throw const BiometricCanceledException();
    }
    return _xor(wrapped.data, hw);
  }

  @override
  Future<void> deleteKey() async => _hwKey = null;

  static Uint8List _xor(Uint8List a, Uint8List b) =>
      Uint8List.fromList([for (var i = 0; i < a.length; i++) a[i] ^ b[i]]);
}

/// Selector de archivos simulado.
class FakeBackupFiles implements BackupFiles {
  Uint8List? saved;
  Uint8List? toOpen;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    saved = Uint8List.fromList(bytes);
    return true;
  }

  @override
  Future<Uint8List?> open() async => toOpen;
}
