import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

import 'qr_detector.dart';
import 'qr_page_layout.dart';

/// Imagen en escala de grises (1 byte por píxel).
class GrayImage {
  GrayImage(this.width, this.height, this.pixels)
    : assert(pixels.length >= width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  /// Convierte píxeles RGBA (como los de la rasterización de un PDF).
  factory GrayImage.fromRgba(int width, int height, Uint8List rgba) {
    final out = Uint8List(width * height);
    for (var i = 0, p = 0; i < out.length; i++, p += 4) {
      // Luminancia aproximada; el fondo transparente cuenta como blanco.
      final a = rgba[p + 3];
      final lum = (rgba[p] * 77 + rgba[p + 1] * 150 + rgba[p + 2] * 29) >> 8;
      out[i] = 255 - (((255 - lum) * a) >> 8);
    }
    return GrayImage(width, height, out);
  }
}

class _GraySource extends LuminanceSource {
  _GraySource(this._img, this._left, this._top, int width, int height)
    : super(width, height);

  final GrayImage _img;
  final int _left;
  final int _top;

  @override
  Int8List getRow(int y, Int8List? row) {
    row ??= Int8List(width);
    final start = (_top + y) * _img.width + _left;
    for (var x = 0; x < width; x++) {
      row[x] = _img.pixels[start + x];
    }
    return row;
  }

  @override
  Int8List getMatrix() {
    final out = Int8List(width * height);
    for (var y = 0; y < height; y++) {
      final start = (_top + y) * _img.width + _left;
      for (var x = 0; x < width; x++) {
        out[y * width + x] = _img.pixels[start + x];
      }
    }
    return out;
  }

  @override
  bool get isCropSupported => true;

  @override
  LuminanceSource crop(int left, int top, int width, int height) =>
      _GraySource(_img, _left + left, _top + top, width, height);
}

class _Found {
  _Found(this.text, this.minX, this.minY, this.maxX, this.maxY);
  final String text;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
}

/// Lee los códigos QR de una imagen (una hoja del PDF, una foto o un
/// fotograma de la cámara). Totalmente local, en Dart.
class QrImageReader {
  static const int _minRegion = 60;

  /// Busca primero en las celdas conocidas del PDF de Cassaforte y, si no
  /// encuentra nada, en toda la imagen, repitiendo en las zonas que quedan
  /// alrededor de cada código encontrado (como el lector múltiple de ZXing).
  static List<String> readAll(GrayImage image, {bool usePageLayout = true}) {
    final found = <String>{};
    if (usePageLayout) {
      final cells = QrPageLayout.readRegions();
      final exact = QrPageLayout.qrRegions();
      for (var i = 0; i < cells.length; i++) {
        final r = cells[i];
        var f = _decodeRegion(
          image,
          (r.left * image.width).floor(),
          (r.top * image.height).floor(),
          (r.width * image.width).floor(),
          (r.height * image.height).floor(),
        );
        // Si el detector falla, se lee el código «puro» en su posición
        // exacta (sin buscar los cuadrados de las esquinas).
        final e = exact[i];
        f ??= _decodeRegion(
          image,
          (e.left * image.width).round(),
          (e.top * image.height).round(),
          (e.width * image.width).round(),
          (e.height * image.height).round(),
          pure: true,
        );
        if (f != null) found.add(f.text);
      }
      // Todas las celdas leídas: listo. Si falta alguna (hoja desplazada,
      // escaneada, o la última hoja, que puede no estar completa), se busca
      // también en toda la hoja.
      if (found.length == cells.length) return found.toList();
    }
    _multi(image, 0, 0, image.width, image.height, 0, found);
    if (found.isEmpty) {
      // Último intento: ventanas superpuestas (fotos con varios códigos).
      for (final div in const [2, 3]) {
        final w = image.width * 2 ~/ (div + 1);
        final h = image.height * 2 ~/ (div + 1);
        for (var iy = 0; iy < div; iy++) {
          for (var ix = 0; ix < div; ix++) {
            final x = (image.width - w) * ix ~/ (div - 1);
            final y = (image.height - h) * iy ~/ (div - 1);
            final f = _decodeRegion(image, x, y, w, h);
            if (f != null) found.add(f.text);
          }
        }
        if (found.isNotEmpty) break;
      }
    }
    return found.toList();
  }

  /// Lee un único código (p. ej., en un fotograma de la cámara). Con
  /// [fast], solo prueba la imagen completa.
  static String? readOne(GrayImage image, {bool fast = false}) {
    if (fast) {
      return _decodeRegion(image, 0, 0, image.width, image.height)?.text;
    }
    // Si no se lee, se prueba el otro binarizador de ZXing (umbral único
    // para toda la imagen), que funciona mejor con algunas fotos borrosas.
    return _readFrame(image) ?? _readFrame(image, global: true);
  }

  static String? _readFrame(GrayImage image, {bool global = false}) {
    // Primero el centro, donde suele apuntar el usuario.
    final cw = image.width * 3 ~/ 4;
    final ch = image.height * 3 ~/ 4;
    return _decodeRegion(
          image,
          (image.width - cw) ~/ 2,
          (image.height - ch) ~/ 2,
          cw,
          ch,
          global: global,
        )?.text ??
        _decodeRegion(
          image,
          0,
          0,
          image.width,
          image.height,
          global: global,
        )?.text;
  }

  static void _multi(
    GrayImage image,
    int x,
    int y,
    int w,
    int h,
    int depth,
    Set<String> found,
  ) {
    if (depth > 4 || w < _minRegion || h < _minRegion) return;
    final f = _decodeRegion(image, x, y, w, h);
    if (f == null) return;
    if (!found.add(f.text) && depth > 0) return;
    // Zonas a la izquierda, arriba, a la derecha y abajo del código.
    _multi(image, x, y, f.minX - x, h, depth + 1, found);
    _multi(image, x, y, w, f.minY - y, depth + 1, found);
    _multi(image, f.maxX, y, x + w - f.maxX, h, depth + 1, found);
    _multi(image, x, f.maxY, w, y + h - f.maxY, depth + 1, found);
  }

  static _Found? _decodeRegion(
    GrayImage image,
    int x,
    int y,
    int w,
    int h, {
    bool pure = false,
    bool global = false,
  }) {
    x = x.clamp(0, image.width);
    y = y.clamp(0, image.height);
    w = w.clamp(0, image.width - x);
    h = h.clamp(0, image.height - y);
    if (w < _minRegion || h < _minRegion) return null;
    final hints = DecodeHints()
      ..put(DecodeHintType.tryHarder)
      ..put(DecodeHintType.possibleFormats, [BarcodeFormat.qrCode]);
    if (pure) hints.put(DecodeHintType.pureBarcode);
    try {
      final source = _GraySource(image, x, y, w, h);
      final bitmap = BinaryBitmap(
        global ? GlobalHistogramBinarizer(source) : HybridBinarizer(source),
      );
      final ({String text, List<ResultPoint> points}) result;
      if (pure) {
        final r = QRCodeReader().decode(bitmap, hints: hints);
        result = (text: r.text, points: r.resultPoints);
      } else {
        result = QrDetector.decode(bitmap.getBlackMatrix(), hints);
      }
      final points = result.points;
      var minX = w, minY = h, maxX = 0, maxY = 0;
      for (final p in points) {
        minX = p.x < minX ? p.x.floor() : minX;
        minY = p.y < minY ? p.y.floor() : minY;
        maxX = p.x > maxX ? p.x.ceil() : maxX;
        maxY = p.y > maxY ? p.y.ceil() : maxY;
      }
      if (points.isEmpty) {
        minX = 0;
        minY = 0;
        maxX = w;
        maxY = h;
      }
      return _Found(result.text, x + minX, y + minY, x + maxX, y + maxY);
    } on ReaderException {
      return null;
    } on ArgumentError {
      // Incluye RangeError (recortes fuera de la imagen).
      return null;
    }
  }
}
