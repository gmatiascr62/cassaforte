import 'package:flutter/services.dart';

/// Guarda y abre archivos de copia de seguridad con el selector de archivos
/// del sistema (Storage Access Framework). No requiere permisos de
/// almacenamiento: el usuario elige dónde guardar o qué abrir.
abstract interface class BackupFiles {
  /// Devuelve `false` si el usuario cancela.
  Future<bool> save(String suggestedName, Uint8List bytes);

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
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    try {
      final saved = await _channel.invokeMethod<bool>('save', {
        'name': suggestedName,
        'bytes': bytes,
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
}
