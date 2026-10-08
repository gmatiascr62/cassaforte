import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

/// Guarda y abre archivos de copia de seguridad con el selector de archivos
/// del sistema (Storage Access Framework). No requiere permisos de
/// almacenamiento: el usuario elige dónde guardar o qué abrir.
abstract interface class BackupFiles {
  /// Guarda con el selector de archivos. Devuelve `false` si se cancela.
  Future<bool> save(
    String suggestedName,
    Uint8List bytes, {
    String mimeType = 'application/octet-stream',
  });

  /// Abre el diálogo de impresión de Android (permite imprimir o «Guardar
  /// como PDF»).
  Future<void> print(String name, Uint8List pdf);

  /// Abre el menú «Compartir» de Android con el PDF.
  Future<void> share(String fileName, Uint8List pdf);

  /// Devuelve `null` si el usuario cancela.
  Future<Uint8List?> open();
}

class BackupFileException implements Exception {
  const BackupFileException(this.message);
  final String message;
  @override
  String toString() => 'BackupFileException: $message';
}

class MethodChannelBackupFiles implements BackupFiles {
  const MethodChannelBackupFiles();

  static const MethodChannel _channel = MethodChannel('cassaforte/files');

  @override
  Future<bool> save(
    String suggestedName,
    Uint8List bytes, {
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>('save', {
        'name': suggestedName,
        'bytes': bytes,
        'mime': mimeType,
      });
      return saved ?? false;
    } on PlatformException catch (e) {
      throw BackupFileException(e.message ?? e.code);
    }
  }

  @override
  Future<Uint8List?> open() async {
    try {
      return await _channel.invokeMethod<Uint8List>('open');
    } on PlatformException catch (e) {
      throw BackupFileException(e.message ?? e.code);
    }
  }

  @override
  Future<void> print(String name, Uint8List pdf) async {
    try {
      await Printing.layoutPdf(name: name, onLayout: (_) async => pdf);
    } on PlatformException catch (e) {
      throw BackupFileException(e.message ?? e.code);
    }
  }

  @override
  Future<void> share(String fileName, Uint8List pdf) async {
    try {
      await Printing.sharePdf(bytes: pdf, filename: fileName);
    } on PlatformException catch (e) {
      throw BackupFileException(e.message ?? e.code);
    }
  }
}
