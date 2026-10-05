import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Parámetros de Argon2id guardados (sin cifrar) en la cabecera de la bóveda.
///
/// Los valores por defecto siguen la segunda configuración recomendada por
/// RFC 9106 (sección 4): 64 MiB de memoria, 3 pasadas y 4 carriles.
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
  });

  /// Memoria en KiB (64 MiB por defecto).
  static const int defaultMemoryKiB = 64 * 1024;

  /// Número de pasadas.
  static const int defaultIterations = 3;

  /// Número de carriles.
  static const int defaultParallelism = 4;

  /// Longitud de la sal aleatoria en bytes.
  static const int saltLength = 16;

  /// Longitud de la clave derivada en bytes (AES-256).
  static const int keyLength = 32;

  // Límites para rechazar cabeceras manipuladas que intenten agotar memoria o
  // tiempo antes incluso de comprobar la autenticación.
  static const int minMemoryKiB = 8;
  static const int maxMemoryKiB = 1024 * 1024;
  static const int maxIterations = 64;
  static const int maxParallelism = 16;

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;

  /// Crea parámetros con los valores por defecto y una sal nueva.
  factory KdfParams.generate({
    int memoryKiB = defaultMemoryKiB,
    int iterations = defaultIterations,
    int parallelism = defaultParallelism,
  }) {
    return KdfParams(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: randomBytes(saltLength),
    );
  }

  /// Comprueba que los parámetros estén dentro de límites razonables.
  bool get isValid =>
      salt.length == saltLength &&
      parallelism >= 1 &&
      parallelism <= maxParallelism &&
      iterations >= 1 &&
      iterations <= maxIterations &&
      memoryKiB >= 8 * parallelism &&
      memoryKiB >= minMemoryKiB &&
      memoryKiB <= maxMemoryKiB;
}

/// Bytes aleatorios de un generador criptográficamente seguro.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}

/// Deriva una clave a partir de la contraseña maestra.
abstract interface class KeyDerivation {
  Future<Uint8List> deriveKey(String password, KdfParams params);
}

/// Argon2id del paquete `cryptography`, ejecutado fuera del hilo de la
/// interfaz para no congelarla.
class Argon2idKeyDerivation implements KeyDerivation {
  const Argon2idKeyDerivation();

  @override
  Future<Uint8List> deriveKey(String password, KdfParams params) {
    final memory = params.memoryKiB;
    final iterations = params.iterations;
    final parallelism = params.parallelism;
    final salt = Uint8List.fromList(params.salt);
    return Isolate.run(() async {
      final algorithm = Argon2id(
        memory: memory,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: KdfParams.keyLength,
      );
      final passwordBytes = SecretKeyData(utf8.encode(password));
      try {
        final key = await algorithm.deriveKey(
          secretKey: passwordBytes,
          nonce: salt,
        );
        final bytes = await key.extractBytes();
        return Uint8List.fromList(bytes);
      } finally {
        passwordBytes.destroy();
      }
    });
  }
}
