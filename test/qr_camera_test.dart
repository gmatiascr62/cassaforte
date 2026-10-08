// ignore_for_file: implementation_imports
import 'dart:math';
import 'dart:typed_data';

import 'package:cassaforte/src/backup/qr_chunks.dart';
import 'package:cassaforte/src/backup/qr_codes.dart';
import 'package:cassaforte/src/backup/qr_image_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zxing2/qrcode.dart';
import 'package:zxing2/src/common/perspective_transform.dart';

/// Códigos como los de una copia de unas 100 cuentas (unos 7 KB cifrados),
/// pero siempre iguales: el cifrado usa sal y nonce aleatorios y las
/// fotos simuladas cambiarían en cada ejecución.
List<String> fixedCodes({int seed = 5, int bytes = 7000}) {
  final random = Random(seed);
  final payload = Uint8List.fromList(
    List.generate(bytes, (_) => random.nextInt(256)),
  );
  return QrChunk.split(payload, isReadable: isQrReadable);
}

/// Simula un fotograma de la cámara: el QR (con su zona de silencio, sobre
/// papel blanco) se proyecta en el cuadrilátero [quad] (x0,y0 … x3,y3 en el
/// orden arriba-izq., arriba-der., abajo-der., abajo-izq.), con fondo gris,
/// iluminación desigual, desenfoque leve y ruido.
GrayImage cameraFrame(
  String text,
  List<double> quad, {
  int width = 1280,
  int height = 720,
  int seed = 1,
}) {
  final qr = renderQr(buildAlphanumericQr(text), scale: 4);
  // Margen de papel alrededor del código.
  final paper = qr.width * 1.15;
  final pad = (paper - qr.width) / 2;
  final toPaper = PerspectiveTransform.quadrilateralToQuadrilateral(
    quad[0],
    quad[1],
    quad[2],
    quad[3],
    quad[4],
    quad[5],
    quad[6],
    quad[7],
    0,
    0,
    paper,
    0,
    paper,
    paper,
    0,
    paper,
  );
  final random = Random(seed);
  final raw = Float64List(width * height);
  final point = [0.0, 0.0];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      point[0] = x + 0.5;
      point[1] = y + 0.5;
      toPaper.transformPoints(point);
      final u = point[0], v = point[1];
      double value;
      if (u < 0 || v < 0 || u >= paper || v >= paper) {
        value = 120; // Mesa.
      } else {
        final qx = (u - pad).floor(), qy = (v - pad).floor();
        final inQr = qx >= 0 && qy >= 0 && qx < qr.width && qy < qr.height;
        value = inQr ? qr.pixels[qy * qr.width + qx].toDouble() : 255;
        value = 25 + value * 0.85; // Papel no tan blanco, tinta no tan negra.
      }
      // Luz que cae de izquierda a derecha.
      raw[y * width + x] = value * (1 - 0.35 * x / width);
    }
  }
  // Desenfoque leve (3×3) y ruido del sensor.
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0, n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= width || yy >= height) continue;
          final w = dx == 0 && dy == 0 ? 4.0 : 1.0;
          sum += raw[yy * width + xx] * w;
          n += w.toInt();
        }
      }
      final noise = (random.nextDouble() - 0.5) * 24;
      out[y * width + x] = (sum / n + noise).round().clamp(0, 255);
    }
  }
  return GrayImage(width, height, out);
}

/// Cuadriláteros como los de una foto real: de frente, girada, inclinada
/// hacia atrás (trapecio), de costado y combinaciones.
List<List<double>> poses(double s, double cx, double cy) {
  List<double> around(List<double> unit, {double angle = 0}) {
    final c = cos(angle), sn = sin(angle);
    return [
      for (var i = 0; i < 8; i += 2) ...[
        cx + (unit[i] * c - unit[i + 1] * sn) * s,
        cy + (unit[i] * sn + unit[i + 1] * c) * s,
      ],
    ];
  }

  const square = [-0.5, -0.5, 0.5, -0.5, 0.5, 0.5, -0.5, 0.5];
  const keystone = [-0.42, -0.45, 0.42, -0.45, 0.5, 0.5, -0.5, 0.5];
  const sideways = [-0.5, -0.5, 0.4, -0.43, 0.4, 0.43, -0.5, 0.5];
  const skewed = [-0.46, -0.44, 0.47, -0.5, 0.5, 0.5, -0.44, 0.47];
  return [
    around(square),
    around(square, angle: 0.3),
    around(keystone),
    around(keystone, angle: -0.2),
    around(sideways),
    around(sideways, angle: 0.6),
    around(skewed, angle: 0.2),
    around(keystone, angle: 2.4),
  ];
}

void main() {
  test(
    'la cámara lee códigos en fotos inclinadas, giradas y en perspectiva',
    () {
      final codes = fixedCodes();
      var read = 0, total = 0;
      final failures = <String>[];
      for (var i = 0; i < codes.length; i++) {
        final frames = poses(500, 640, 360);
        for (var p = 0; p < frames.length; p++) {
          total++;
          final frame = cameraFrame(codes[i], frames[p], seed: i * 31 + p);
          if (QrImageReader.readOne(frame) == codes[i]) {
            read++;
          } else {
            failures.add('código ${i + 1}, posición $p');
          }
        }
      }
      // ignore: avoid_print
      print('Leídos $read de $total fotogramas. Fallos: $failures');
      // Un fallo aislado se resuelve con el siguiente fotograma; lo que no
      // puede pasar es que una posición o un código fallen siempre.
      expect(read / total, greaterThanOrEqualTo(0.95));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('nunca devuelve un texto distinto del código', () {
    // El detector prueba varias hipótesis; la corrección de errores del QR
    // debe rechazar las equivocadas en vez de devolver datos erróneos.
    final codes = fixedCodes(seed: 9, bytes: 3000);
    for (var i = 0; i < codes.length; i++) {
      for (final quad in poses(500, 640, 360)) {
        final text = QrImageReader.readOne(cameraFrame(codes[i], quad));
        expect(text == null || text == codes[i], isTrue);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('zxing2 sin las correcciones falla en fotos en perspectiva', () {
    // Documenta por qué existe QrDetector: si zxing2 corrige el problema
    // en una versión futura, esta prueba avisa de que se puede simplificar.
    final codes = fixedCodes();
    var plain = 0, total = 0;
    for (final code in codes) {
      final quads = poses(500, 640, 360);
      for (final p in [2, 3, 4, 5]) {
        total++;
        final frame = cameraFrame(code, quads[p]);
        try {
          final r = QRCodeReader().decode(
            BinaryBitmap(HybridBinarizer(_Source(frame))),
            hints: DecodeHints()..put(DecodeHintType.tryHarder),
          );
          if (r.text == code) plain++;
        } on ReaderException {
          // No leído.
        }
      }
    }
    expect(plain, lessThan(total));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

class _Source extends LuminanceSource {
  _Source(this.image) : super(image.width, image.height);
  final GrayImage image;

  @override
  Int8List getRow(int y, Int8List? row) => Int8List.fromList(
    image.pixels.sublist(y * image.width, (y + 1) * image.width),
  );

  @override
  Int8List getMatrix() => Int8List.fromList(image.pixels);
}
