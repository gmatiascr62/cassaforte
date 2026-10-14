import 'dart:typed_data';

/// Codificación Base45 (RFC 9285).
///
/// Convierte datos binarios en texto con el juego de caracteres del modo
/// alfanumérico de los códigos QR, que guarda 5,5 bits por carácter. Así un
/// QR transporta datos binarios casi sin desperdicio y sin los problemas de
/// juego de caracteres del modo «byte».
class Base45 {
  static const String alphabet =
      r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

  static final Map<int, int> _index = {
    for (var i = 0; i < alphabet.length; i++) alphabet.codeUnitAt(i): i,
  };

  static String encode(Uint8List data) {
    final out = StringBuffer();
    for (var i = 0; i < data.length; i += 2) {
      if (i + 1 < data.length) {
        final n = data[i] * 256 + data[i + 1];
        out
          ..writeCharCode(alphabet.codeUnitAt(n % 45))
          ..writeCharCode(alphabet.codeUnitAt((n ~/ 45) % 45))
          ..writeCharCode(alphabet.codeUnitAt(n ~/ 2025));
      } else {
        final n = data[i];
        out
          ..writeCharCode(alphabet.codeUnitAt(n % 45))
          ..writeCharCode(alphabet.codeUnitAt(n ~/ 45));
      }
    }
    return out.toString();
  }

  /// Lanza [FormatException] si el texto no es Base45 válido.
  static Uint8List decode(String text) {
    if (text.length % 3 == 1) {
      throw const FormatException('Longitud Base45 no válida');
    }
    final out = Uint8List(
      text.length ~/ 3 * 2 + (text.length % 3 == 2 ? 1 : 0),
    );
    var o = 0;
    int value(int i) {
      final v = _index[text.codeUnitAt(i)];
      if (v == null) throw const FormatException('Carácter Base45 no válido');
      return v;
    }

    for (var i = 0; i < text.length; i += 3) {
      if (i + 2 < text.length) {
        final n = value(i) + value(i + 1) * 45 + value(i + 2) * 2025;
        if (n > 0xFFFF) throw const FormatException('Bloque Base45 no válido');
        out[o++] = n >> 8;
        out[o++] = n & 0xFF;
      } else {
        final n = value(i) + value(i + 1) * 45;
        if (n > 0xFF) throw const FormatException('Bloque Base45 no válido');
        out[o++] = n;
      }
    }
    return out;
  }
}
