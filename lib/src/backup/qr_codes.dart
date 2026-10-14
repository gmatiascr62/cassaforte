import 'dart:typed_data';

import 'package:qr/qr.dart';

import 'qr_image_reader.dart';

/// Genera la matriz de un QR en modo alfanumérico (para texto Base45) con
/// la versión más pequeña posible y corrección de errores M (15 %).
QrImage buildAlphanumericQr(String text) {
  for (var version = 1; version <= 40; version++) {
    try {
      return QrImage(
        QrCode(version, QrErrorCorrectLevel.M)..addAlphaNumeric(text),
      );
    } on InputTooLongException {
      continue;
    }
  }
  throw ArgumentError('Texto demasiado largo para un QR');
}

/// Dibuja la matriz con [scale] píxeles por módulo (puede no ser entero,
/// como en una foto o un PDF rasterizado) y 4 módulos de zona de silencio.
GrayImage renderQr(QrImage qr, {double scale = 4}) {
  final n = qr.moduleCount;
  final size = ((n + 8) * scale).ceil();
  final px = Uint8List(size * size)..fillRange(0, size * size, 255);
  int edge(int module) => ((module + 4) * scale).round();
  for (var r = 0; r < n; r++) {
    final y0 = edge(r), y1 = edge(r + 1);
    for (var c = 0; c < n; c++) {
      if (!qr.isDark(r, c)) continue;
      final x0 = edge(c), x1 = edge(c + 1);
      for (var y = y0; y < y1; y++) {
        px.fillRange(y * size + x0, y * size + x1, 0);
      }
    }
  }
  return GrayImage(size, size, px);
}

/// Escalas (píxeles por módulo) a las que se comprueba cada QR antes de
/// ponerlo en el PDF. Son enteras a propósito: con escalas fraccionarias el
/// redondeo del dibujo de prueba hace fallar siempre algunas versiones de
/// QR, y lo que se busca aquí son los fallos que dependen de los datos
/// (dibujos que confunden al detector). Los fallos por tamaño se cubren al
/// leer: el PDF se relee a otra resolución y la cámara se mueve.
const List<double> verificationScales = [3, 4, 5, 6];

/// Comprueba que el detector de ZXing (el mismo algoritmo que usan muchos
/// lectores) encuentra y lee el QR de [text] a varias escalas.
bool isQrReadable(String text) {
  final qr = buildAlphanumericQr(text);
  for (final scale in verificationScales) {
    if (QrImageReader.readOne(renderQr(qr, scale: scale), fast: true) != text) {
      return false;
    }
  }
  return true;
}
