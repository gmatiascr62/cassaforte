import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kdf.dart';

/// El archivo no tiene el formato esperado (dañado o manipulado).
class VaultFormatException implements Exception {
  const VaultFormatException(this.message);
  final String message;
  @override
  String toString() => 'VaultFormatException: $message';
}

/// La autenticación del contenido cifrado falló: contraseña incorrecta o
/// archivo alterado. AES-GCM no permite distinguir entre ambos casos.
class VaultAuthenticationException implements Exception {
  const VaultAuthenticationException();
  @override
  String toString() => 'VaultAuthenticationException';
}

/// Cabecera pública de un archivo de bóveda.
class VaultHeader {
  const VaultHeader({required this.kdf, required this.nonce});

  final KdfParams kdf;
  final Uint8List nonce;
}

/// Formato del archivo de bóveda (JSON, versión 1):
///
/// ```json
/// {
///   "format": "cassaforte-vault",
///   "version": 1,
///   "kdf": {"algorithm": "argon2id", "version": 19, "memoryKiB": 65536,
///           "iterations": 3, "parallelism": 4, "salt": "<base64>"},
///   "cipher": {"algorithm": "aes-256-gcm", "nonce": "<base64, 12 bytes>"},
///   "ciphertext": "<base64: texto cifrado || etiqueta de 16 bytes>"
/// }
/// ```
///
/// Todo el contenido de la bóveda (nombres, direcciones, usuarios,
/// contraseñas y notas) va dentro de `ciphertext`. Los parámetros de la
/// cabecera se autentican como datos asociados (AAD) de AES-GCM, de modo que
/// cualquier cambio en ellos hace fallar el descifrado.
class VaultCipher {
  VaultCipher({KeyDerivation? keyDerivation})
    : keyDerivation = keyDerivation ?? const Argon2idKeyDerivation();

  static const String formatName = 'cassaforte-vault';
  static const int formatVersion = 1;
  static const String kdfName = 'argon2id';
  static const int argon2Version = 0x13;
  static const String cipherName = 'aes-256-gcm';
  static const int nonceLength = 12;
  static const int tagLength = 16;

  /// Tamaño máximo aceptado para un archivo de bóveda (protección básica).
  static const int maxFileBytes = 32 * 1024 * 1024;

  final KeyDerivation keyDerivation;
  final AesGcm _aes = AesGcm.with256bits(nonceLength: nonceLength);

  Future<Uint8List> deriveKey(String password, KdfParams params) =>
      keyDerivation.deriveKey(password, params);

  /// Cifra [plaintext] con [key] y un nonce aleatorio nuevo.
  Future<Uint8List> seal({
    required Uint8List plaintext,
    required Uint8List key,
    required KdfParams kdf,
  }) async {
    if (key.length != KdfParams.keyLength) {
      throw ArgumentError('Longitud de clave incorrecta');
    }
    // Nonce único para cada operación de cifrado (96 bits aleatorios).
    final nonce = randomBytes(nonceLength);
    final secretKey = SecretKeyData(Uint8List.fromList(key));
    try {
      final box = await _aes.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
        aad: _associatedData(kdf),
      );
      final document = <String, Object?>{
        'format': formatName,
        'version': formatVersion,
        'kdf': {
          'algorithm': kdfName,
          'version': argon2Version,
          'memoryKiB': kdf.memoryKiB,
          'iterations': kdf.iterations,
          'parallelism': kdf.parallelism,
          'salt': base64.encode(kdf.salt),
        },
        'cipher': {'algorithm': cipherName, 'nonce': base64.encode(nonce)},
        'ciphertext': base64.encode([...box.cipherText, ...box.mac.bytes]),
      };
      return Uint8List.fromList(utf8.encode(jsonEncode(document)));
    } finally {
      secretKey.destroy();
    }
  }

  /// Lee y valida la cabecera pública. Lanza [VaultFormatException].
  VaultHeader readHeader(Uint8List fileBytes) => _parse(fileBytes).header;

  /// Descifra el archivo con [key]. Lanza [VaultFormatException] o
  /// [VaultAuthenticationException].
  Future<Uint8List> open({
    required Uint8List fileBytes,
    required Uint8List key,
  }) async {
    final parsed = _parse(fileBytes);
    final secretKey = SecretKeyData(Uint8List.fromList(key));
    try {
      final data = parsed.ciphertext;
      final box = SecretBox(
        data.sublist(0, data.length - tagLength),
        nonce: parsed.header.nonce,
        mac: Mac(data.sublist(data.length - tagLength)),
      );
      final clear = await _aes.decrypt(
        box,
        secretKey: secretKey,
        aad: _associatedData(parsed.header.kdf),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const VaultAuthenticationException();
    } finally {
      secretKey.destroy();
    }
  }

  List<int> _associatedData(KdfParams kdf) => utf8.encode(
    [
      formatName,
      formatVersion,
      kdfName,
      argon2Version,
      kdf.memoryKiB,
      kdf.iterations,
      kdf.parallelism,
      base64.encode(kdf.salt),
      cipherName,
    ].join('|'),
  );

  _ParsedVault _parse(Uint8List fileBytes) {
    if (fileBytes.isEmpty || fileBytes.length > maxFileBytes) {
      throw const VaultFormatException('Tamaño de archivo no válido');
    }
    try {
      final doc = jsonDecode(utf8.decode(fileBytes));
      if (doc is! Map<String, Object?>) {
        throw const VaultFormatException('Estructura no válida');
      }
      if (doc['format'] != formatName) {
        throw const VaultFormatException('No es una bóveda de Cassaforte');
      }
      if (doc['version'] != formatVersion) {
        throw const VaultFormatException('Versión de formato no compatible');
      }
      final kdf = doc['kdf'];
      final cipher = doc['cipher'];
      if (kdf is! Map<String, Object?> || cipher is! Map<String, Object?>) {
        throw const VaultFormatException('Cabecera incompleta');
      }
      if (kdf['algorithm'] != kdfName || kdf['version'] != argon2Version) {
        throw const VaultFormatException('Derivación de clave no compatible');
      }
      if (cipher['algorithm'] != cipherName) {
        throw const VaultFormatException('Cifrado no compatible');
      }
      final params = KdfParams(
        memoryKiB: _int(kdf['memoryKiB']),
        iterations: _int(kdf['iterations']),
        parallelism: _int(kdf['parallelism']),
        salt: base64.decode(_string(kdf['salt'])),
      );
      if (!params.isValid) {
        throw const VaultFormatException('Parámetros de derivación no válidos');
      }
      final nonce = base64.decode(_string(cipher['nonce']));
      if (nonce.length != nonceLength) {
        throw const VaultFormatException('Nonce no válido');
      }
      final ciphertext = base64.decode(_string(doc['ciphertext']));
      if (ciphertext.length < tagLength) {
        throw const VaultFormatException('Contenido cifrado truncado');
      }
      return _ParsedVault(VaultHeader(kdf: params, nonce: nonce), ciphertext);
    } on VaultFormatException {
      rethrow;
    } on FormatException {
      throw const VaultFormatException('Archivo dañado');
    }
  }

  static int _int(Object? value) {
    if (value is int) return value;
    throw const VaultFormatException('Valor numérico no válido');
  }

  static String _string(Object? value) {
    if (value is String) return value;
    throw const VaultFormatException('Valor de texto no válido');
  }
}

class _ParsedVault {
  const _ParsedVault(this.header, this.ciphertext);
  final VaultHeader header;
  final Uint8List ciphertext;
}
