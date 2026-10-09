import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../backup/qr_image_reader.dart';

class QrScannerException implements Exception {
  const QrScannerException(this.message);
  final String message;
  @override
  String toString() => 'QrScannerException: $message';
}

/// Lector de códigos QR con la cámara.
abstract interface class QrScanner {
  /// Abre la cámara y llama a [onCode] con el texto de cada QR que lee.
  /// Lanza [QrScannerException] si no hay cámara o falta el permiso.
  Future<void> start(void Function(String text) onCode);

  /// Vista previa de la cámara (solo después de [start]).
  Widget buildPreview(BuildContext context);

  Future<void> stop();
}

/// Crea un lector nuevo cada vez que se abre la pantalla de escaneo.
typedef QrScannerFactory = QrScanner Function();

/// Implementación con el paquete oficial `camera` (CameraX). Los
/// fotogramas se decodifican en Dart (ZXing), en otro isolate, sin conexión
/// ni servicios externos.
class CameraQrScanner implements QrScanner {
  CameraController? _controller;
  bool _decoding = false;
  bool _stopped = false;

  @override
  Future<void> start(void Function(String text) onCode) async {
    _stopped = false;
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException {
      throw const QrScannerException('No se pudo acceder a la cámara.');
    }
    if (cameras.isEmpty) {
      throw const QrScannerException('Este teléfono no tiene cámara.');
    }
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      camera,
      // 1080p: más píxeles por módulo, lectura más fiable de QR densos.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (_stopped) return;
      await controller.startImageStream((image) {
        if (_decoding || _stopped) return;
        _decoding = true;
        decodeInBackground(_lumaOf(image))
            .then((text) {
              if (text != null && !_stopped) onCode(text);
            })
            .catchError((Object e) {
              // No debería pasar; si pasa, que se vea al depurar (el
              // error no contiene datos del QR).
              debugPrint('Error al leer un fotograma: ${e.runtimeType}');
            })
            .whenComplete(() => _decoding = false);
      });
    } on CameraException catch (e) {
      await stop();
      throw QrScannerException(
        e.code.contains('AccessDenied') || e.code.contains('AccessRestricted')
            ? 'Cassaforte no tiene permiso para usar la cámara. Podés '
                  'activarlo en Ajustes del teléfono › Aplicaciones › '
                  'Cassaforte › Permisos, o elegir el archivo PDF.'
            : 'No se pudo abrir la cámara.',
      );
    }
  }

  /// Lee un QR del fotograma en otro isolate.
  ///
  /// Tiene que ser estático: `Isolate.run` copia al otro isolate todo el
  /// contexto de la función que se le pasa, y un cierre creado dentro de
  /// [start] arrastraría el `CameraController`, que no se puede enviar. Así
  /// fallaban todos los fotogramas y la cámara no reconocía ningún código.
  @visibleForTesting
  static Future<String?> decodeInBackground(GrayImage frame) =>
      Isolate.run(() => QrImageReader.readOne(frame));

  /// Plano Y (luminancia) del fotograma YUV, sin el relleno de cada fila.
  static GrayImage _lumaOf(CameraImage image) {
    final plane = image.planes.first;
    final w = image.width, h = image.height, stride = plane.bytesPerRow;
    if (stride == w) {
      return GrayImage(w, h, Uint8List.fromList(plane.bytes));
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      out.setRange(y * w, y * w + w, plane.bytes, y * stride);
    }
    return GrayImage(w, h, out);
  }

  @override
  Widget buildPreview(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(child: CameraPreview(c));
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }
}
