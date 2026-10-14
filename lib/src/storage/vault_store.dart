import 'dart:io';
import 'dart:typed_data';

/// Almacenamiento de los bytes (ya cifrados) de la bóveda.
abstract interface class VaultStore {
  Future<bool> exists();
  Future<Uint8List> read();

  /// Sustituye el contenido de forma atómica: o queda el archivo anterior
  /// completo, o el nuevo completo.
  Future<void> writeAtomic(Uint8List bytes);

  /// Borra el archivo si existe.
  Future<void> delete();
}

/// Guarda la bóveda en un archivo del directorio privado de la aplicación.
///
/// La escritura atómica se hace escribiendo un archivo temporal en el mismo
/// directorio, forzando su volcado a disco y renombrándolo sobre el archivo
/// final (`rename` es atómico en el mismo sistema de archivos).
class FileVaultStore implements VaultStore {
  FileVaultStore(this.path);

  static const String fileName = 'vault.cassaforte';

  final String path;

  File get _file => File(path);
  File get _temp => File('$path.tmp');

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<Uint8List> read() => _file.readAsBytes();

  @override
  Future<void> delete() async {
    if (await _file.exists()) await _file.delete();
  }

  @override
  Future<void> writeAtomic(Uint8List bytes) async {
    final temp = _temp;
    try {
      final raf = await temp.open(mode: FileMode.write);
      try {
        await raf.writeFrom(bytes);
        await raf.flush();
      } finally {
        await raf.close();
      }
      await temp.rename(path);
    } catch (_) {
      // Si algo falla, el archivo original no se ha tocado.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }
}
