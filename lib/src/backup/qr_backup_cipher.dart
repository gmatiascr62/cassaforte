import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/kdf.dart';
import '../model/vault_entry.dart';

/// La copia no tiene un formato válido, está incompleta o supera los
/// límites permitidos.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// La autenticación AES-GCM falló: contraseña incorrecta o datos alterados.
class BackupWrongPasswordException implements Exception {
  const BackupWrongPasswordException();
  @override
  String toString() => 'BackupWrongPasswordException';
}

/// Contenedor cifrado de las copias de seguridad en códigos QR (versión 1).
///
/// Formato binario, compacto para que quepa en pocos QR:
///
/// ```text
///  0..3   "CSFB"                    identificador del formato
///  4      1                         versión
///  5..8   memoria Argon2id (KiB)    entero sin signo, big-endian
///  9      pasadas Argon2id
///  10     carriles Argon2id
///  11..26 sal (16 bytes aleatorios, nueva en cada copia)
///  27..38 nonce AES-GCM (12 bytes aleatorios)
///  39..   texto cifrado || etiqueta GCM (16 bytes)
/// ```
///
/// Los bytes 0..38 se autentican como datos asociados (AAD). El texto en
/// claro es `gzip(JSON)` con el mismo esquema versionado de la bóveda
/// ([VaultContents]): nombres, direcciones, usuarios, contraseñas, notas,
/// campos adicionales y fechas. Se comprime antes de cifrar.
///
/// La clave se deriva de la contraseña maestra con Argon2id y una sal
/// propia de la copia, así que la copia no depende del teléfono ni de la
/// bóveda: solo de la contraseña maestra que se usó al exportarla.
class QrBackupCipher {
  QrBackupCipher({
    KeyDerivation? keyDerivation,
    KdfParams Function()? newKdfParams,
  }) : _kdf = keyDerivation ?? const Argon2idKeyDerivation(),
       _newKdfParams = newKdfParams ?? KdfParams.generate;

  static const List<int> magic = [0x43, 0x53, 0x46, 0x42]; // "CSFB"
  static const int version = 1;
  static const int headerLength = 39;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  /// Tamaño máximo de una copia cifrada.
  static const int maxPayloadBytes = 1024 * 1024;

  /// Tamaño máximo de los datos una vez descomprimidos (evita «bombas» de
  /// compresión en archivos maliciosos).
  static const int maxDecompressedBytes = 16 * 1024 * 1024;

  final KeyDerivation _kdf;
  final KdfParams Function() _newKdfParams;
  final AesGcm _aes = AesGcm.with256bits(nonceLength: nonceLength);

  /// Cifra todas las cuentas con la contraseña maestra.
  Future<Uint8List> seal(
    List<VaultEntry> entries,
    String masterPassword,
  ) async {
    final kdf = _newKdfParams();
    final key = await _kdf.deriveKey(masterPassword, kdf);
    final plain = Uint8List.fromList(VaultContents.encode(entries));
    Uint8List? compressed;
    final secretKey = SecretKeyData(Uint8List.fromList(key));
    try {
      compressed = Uint8List.fromList(GZipCodec(level: 9).encode(plain));
      _wipe(plain);
      final nonce = randomBytes(nonceLength);
      final header = _header(kdf, nonce);
      final box = await _aes.encrypt(
        compressed,
        secretKey: secretKey,
        nonce: nonce,
        aad: header,
      );
      final out = BytesBuilder(copy: false)
        ..add(header)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
      final payload = out.takeBytes();
      if (payload.length > maxPayloadBytes) {
        throw const BackupFormatException('La copia es demasiado grande');
      }
      return payload;
    } finally {
      _wipe(plain);
      _wipe(compressed);
      _wipe(key);
      secretKey.destroy();
    }
  }

  /// Lee los parámetros públicos sin descifrar. Lanza
  /// [BackupFormatException].
  KdfParams readKdfParams(Uint8List payload) => _parse(payload).kdf;

  /// Descifra y valida la copia. Lanza [BackupFormatException] o
  /// [BackupWrongPasswordException]. No modifica nada.
  Future<List<VaultEntry>> open(
    Uint8List payload,
    String masterPassword,
  ) async {
    final parsed = _parse(payload);
    final key = await _kdf.deriveKey(masterPassword, parsed.kdf);
    final secretKey = SecretKeyData(Uint8List.fromList(key));
    _wipe(key);
    Uint8List? compressed;
    Uint8List? plain;
    try {
      final data = payload.sublist(headerLength);
      final box = SecretBox(
        data.sublist(0, data.length - tagLength),
        nonce: parsed.nonce,
        mac: Mac(data.sublist(data.length - tagLength)),
      );
      try {
        compressed = Uint8List.fromList(
          await _aes.decrypt(
            box,
            secretKey: secretKey,
            aad: payload.sublist(0, headerLength),
          ),
        );
      } on SecretBoxAuthenticationError {
        throw const BackupWrongPasswordException();
      }
      plain = gunzipLimited(compressed, maxDecompressedBytes);
      try {
        return VaultContents.decode(plain);
      } on FormatException {
        throw const BackupFormatException(
          'El contenido de la copia no es válido',
        );
      }
    } finally {
      _wipe(compressed);
      _wipe(plain);
      secretKey.destroy();
    }
  }

  static Uint8List _header(KdfParams kdf, Uint8List nonce) {
    final header = Uint8List(headerLength);
    header.setRange(0, 4, magic);
    header[4] = version;
    ByteData.sublistView(header).setUint32(5, kdf.memoryKiB);
    header[9] = kdf.iterations;
    header[10] = kdf.parallelism;
    header.setRange(11, 27, kdf.salt);
    header.setRange(27, 39, nonce);
    return header;
  }

  static _Parsed _parse(Uint8List payload) {
    if (payload.length < headerLength + tagLength ||
        payload.length > maxPayloadBytes) {
      throw const BackupFormatException('Tamaño de copia no válido');
    }
    for (var i = 0; i < magic.length; i++) {
      if (payload[i] != magic[i]) {
        throw const BackupFormatException('No es una copia de Cassaforte');
      }
    }
    if (payload[4] != version) {
      throw const BackupFormatException('Versión de copia no compatible');
    }
    final kdf = KdfParams(
      memoryKiB: ByteData.sublistView(payload).getUint32(5),
      iterations: payload[9],
      parallelism: payload[10],
      salt: payload.sublist(11, 27),
    );
    if (!kdf.isValid) {
      throw const BackupFormatException('Parámetros de cifrado no válidos');
    }
    return _Parsed(kdf, payload.sublist(27, 39));
  }

  static void _wipe(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);
}

/// Descomprime GZIP sin superar [limit] bytes.
Uint8List gunzipLimited(Uint8List data, int limit) {
  final sink = _LimitedSink(limit);
  try {
    gzip.decoder.startChunkedConversion(sink)
      ..add(data)
      ..close();
  } on BackupFormatException {
    sink.wipe();
    rethrow;
  } on FormatException {
    sink.wipe();
    throw const BackupFormatException('Datos comprimidos no válidos');
  } on FileSystemException {
    sink.wipe();
    throw const BackupFormatException('Datos comprimidos no válidos');
  }
  return sink.takeBytes();
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);

  final int limit;
  final List<Uint8List> _chunks = [];
  int _length = 0;

  @override
  void add(List<int> chunk) {
    _length += chunk.length;
    final copy = Uint8List.fromList(chunk);
    _chunks.add(copy);
    if (_length > limit) {
      throw const BackupFormatException(
        'Los datos descomprimidos superan el límite',
      );
    }
  }

  @override
  void close() {}

  Uint8List takeBytes() {
    final out = Uint8List(_length);
    var offset = 0;
    for (final c in _chunks) {
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    wipe();
    return out;
  }

  void wipe() {
    for (final c in _chunks) {
      c.fillRange(0, c.length, 0);
    }
    _chunks.clear();
  }
}

class _Parsed {
  const _Parsed(this.kdf, this.nonce);
  final KdfParams kdf;
  final Uint8List nonce;
}
