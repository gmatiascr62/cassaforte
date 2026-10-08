import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'base45.dart';
import 'qr_backup_cipher.dart';

/// Un fragmento de la copia, tal como va dentro de un código QR.
///
/// Formato binario (antes de codificarlo en Base45):
///
/// ```text
///  0..1   "CQ"           identificador
///  2      1              versión
///  3..10  id de copia    8 primeros bytes de SHA-256 de la copia completa
///  11..12 posición       (desde 0), big-endian
///  13..14 total          de fragmentos, big-endian
///  15     variante       cambia el dibujo del QR sin cambiar los datos
///  16..   datos          mezclados (XOR) con una secuencia derivada de
///                        id, posición y variante, para que cada variante
///                        produzca un QR completamente distinto
///  4 bytes finales       8 primeros bytes de SHA-256 de todo lo anterior,
///                        truncados a 4 (detecta lecturas dañadas)
/// ```
class QrChunk {
  const QrChunk({
    required this.copyId,
    required this.index,
    required this.total,
    required this.data,
  });

  static const List<int> magic = [0x43, 0x51]; // "CQ"
  static const int version = 1;
  static const int headerLength = 16;
  static const int checkLength = 4;

  /// Datos por fragmento: con la cabecera caben en un QR versión 20 con
  /// corrección de errores M (970 caracteres alfanuméricos), un tamaño que
  /// se escanea bien impreso en A4 (6 por hoja).
  static const int maxDataPerChunk = 620;

  /// Máximo de fragmentos aceptados (protección contra datos maliciosos).
  static const int maxChunks = 2000;

  final Uint8List copyId;
  final int index;
  final int total;
  final Uint8List data;

  String get copyIdHex => hexId(copyId);

  /// Divide una copia cifrada en fragmentos de tamaño parecido y devuelve
  /// el texto Base45 de cada QR, en orden.
  ///
  /// Si se indica [isReadable], cada QR se comprueba y, si no se puede
  /// leer, se genera otra variante (otro dibujo con los mismos datos). Así
  /// se evitan los códigos que confunden al detector de ZXing.
  static List<String> split(
    Uint8List payload, {
    bool Function(String text)? isReadable,
  }) {
    if (payload.isEmpty) throw ArgumentError('Copia vacía');
    final total = (payload.length + maxDataPerChunk - 1) ~/ maxDataPerChunk;
    if (total > maxChunks) {
      throw const BackupFormatException('La copia es demasiado grande');
    }
    final size = (payload.length + total - 1) ~/ total;
    final id = copyIdOf(payload);
    final texts = <String>[];
    for (var i = 0; i < total; i++) {
      final data = payload.sublist(
        i * size,
        (i + 1) * size > payload.length ? payload.length : (i + 1) * size,
      );
      String? chosen;
      for (var variant = 0; variant < 256; variant++) {
        final text = Base45.encode(_encode(id, i, total, variant, data));
        if (isReadable == null || isReadable(text)) {
          chosen = text;
          break;
        }
      }
      if (chosen == null) {
        throw StateError('No se pudo generar un código QR legible');
      }
      texts.add(chosen);
    }
    return texts;
  }

  /// Interpreta el texto de un QR. Lanza [FormatException] si no es un
  /// fragmento válido de Cassaforte o si está dañado.
  static QrChunk parse(String text) {
    final bytes = Base45.decode(text.trim());
    if (bytes.length < headerLength + checkLength + 1) {
      throw const FormatException('Fragmento demasiado corto');
    }
    if (bytes[0] != magic[0] || bytes[1] != magic[1]) {
      throw const FormatException('No es un código de Cassaforte');
    }
    if (bytes[2] != version) {
      throw const FormatException('Versión de código no compatible');
    }
    final body = bytes.sublist(0, bytes.length - checkLength);
    final check = bytes.sublist(bytes.length - checkLength);
    if (!_equal(_check(body), check)) {
      throw const FormatException('Código dañado');
    }
    final view = ByteData.sublistView(bytes);
    final index = view.getUint16(11);
    final total = view.getUint16(13);
    if (total == 0 || total > maxChunks || index >= total) {
      throw const FormatException('Numeración no válida');
    }
    final copyId = bytes.sublist(3, 11);
    return QrChunk(
      copyId: copyId,
      index: index,
      total: total,
      data: _whiten(
        bytes.sublist(headerLength, bytes.length - checkLength),
        copyId,
        index,
        bytes[15],
      ),
    );
  }

  /// Codifica un fragmento (solo para pruebas de manipulación).
  static String encodeForTest(QrChunk chunk, {int variant = 0}) =>
      Base45.encode(
        _encode(chunk.copyId, chunk.index, chunk.total, variant, chunk.data),
      );

  static Uint8List copyIdOf(Uint8List payload) => Uint8List.fromList(
    const DartSha256().hashSync(payload).bytes.sublist(0, 8),
  );

  static String hexId(Uint8List id) =>
      id.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  static Uint8List _encode(
    Uint8List id,
    int index,
    int total,
    int variant,
    Uint8List data,
  ) {
    final body = Uint8List(headerLength + data.length);
    body.setRange(0, 2, magic);
    body[2] = version;
    body.setRange(3, 11, id);
    ByteData.sublistView(body)
      ..setUint16(11, index)
      ..setUint16(13, total);
    body[15] = variant;
    body.setRange(headerLength, body.length, _whiten(data, id, index, variant));
    return Uint8List.fromList([...body, ..._check(body)]);
  }

  /// XOR con SHA-256(id ‖ posición ‖ variante ‖ contador). No es cifrado
  /// (los datos ya están cifrados): solo cambia el dibujo del QR.
  static Uint8List _whiten(
    Uint8List data,
    Uint8List id,
    int index,
    int variant,
  ) {
    final out = Uint8List.fromList(data);
    for (var block = 0; block * 32 < out.length; block++) {
      final seed = Uint8List(13)
        ..setRange(0, 8, id)
        ..[8] = index >> 8
        ..[9] = index & 0xFF
        ..[10] = variant
        ..[11] = block >> 8
        ..[12] = block & 0xFF;
      final ks = const DartSha256().hashSync(seed).bytes;
      for (var i = 0; i < 32 && block * 32 + i < out.length; i++) {
        out[block * 32 + i] ^= ks[i];
      }
    }
    return out;
  }

  static List<int> _check(List<int> body) =>
      const DartSha256().hashSync(body).bytes.sublist(0, checkLength);

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Resultado de añadir un código leído.
enum ChunkStatus {
  /// Código nuevo de esta copia.
  added,

  /// Ya se había leído.
  duplicate,

  /// Pertenece a otra copia distinta de la que se está leyendo.
  otherCopy,

  /// No es un código de Cassaforte o está dañado.
  invalid,

  /// Misma posición que uno ya leído pero con otro contenido: alterado.
  conflict,
}

/// Junta los fragmentos leídos (en cualquier orden) hasta reconstruir la
/// copia cifrada completa.
class BackupAssembler {
  Uint8List? _copyId;
  int? _total;
  final Map<int, Uint8List> _parts = {};

  int get received => _parts.length;
  int? get total => _total;
  String? get copyIdHex => _copyId == null ? null : QrChunk.hexId(_copyId!);
  bool get isComplete => _total != null && _parts.length == _total;

  /// Posiciones (desde 1) que todavía faltan.
  List<int> get missing => [
    if (_total != null)
      for (var i = 0; i < _total!; i++)
        if (!_parts.containsKey(i)) i + 1,
  ];

  void reset() {
    _copyId = null;
    _total = null;
    _parts.clear();
  }

  ChunkStatus add(String text) {
    final QrChunk chunk;
    try {
      chunk = QrChunk.parse(text);
    } on FormatException {
      return ChunkStatus.invalid;
    }
    final id = _copyId;
    if (id == null) {
      _copyId = chunk.copyId;
      _total = chunk.total;
    } else if (!QrChunk._equal(id, chunk.copyId)) {
      return ChunkStatus.otherCopy;
    } else if (chunk.total != _total) {
      return ChunkStatus.conflict;
    }
    final existing = _parts[chunk.index];
    if (existing != null) {
      return QrChunk._equal(existing, chunk.data)
          ? ChunkStatus.duplicate
          : ChunkStatus.conflict;
    }
    _parts[chunk.index] = chunk.data;
    return ChunkStatus.added;
  }

  /// Une los fragmentos y comprueba que el resultado corresponde al
  /// identificador de la copia. Lanza [BackupFormatException].
  Uint8List assemble() {
    if (!isComplete) {
      throw BackupFormatException(
        'Faltan códigos: ${missing.take(10).join(', ')}'
        '${missing.length > 10 ? '…' : ''}',
      );
    }
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < _total!; i++) {
      out.add(_parts[i]!);
    }
    final payload = out.takeBytes();
    if (payload.length > QrBackupCipher.maxPayloadBytes ||
        !QrChunk._equal(QrChunk.copyIdOf(payload), _copyId!)) {
      throw const BackupFormatException(
        'Los códigos están dañados o mezclados con otra copia',
      );
    }
    return payload;
  }
}
