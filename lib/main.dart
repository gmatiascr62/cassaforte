import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/legal/terms.dart';
import 'src/security/biometric_unlock.dart';
import 'src/security/clipboard_guard.dart';
import 'src/session/vault_session.dart';
import 'src/storage/vault_store.dart';
import 'src/ui/cassaforte_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Directorio privado de la aplicación (excluido de las copias de seguridad
  // mediante las reglas del manifiesto de Android).
  final dir = await getApplicationSupportDirectory();
  final store = FileVaultStore('${dir.path}/${FileVaultStore.fileName}');
  final session = VaultSession(store: store);
  // Clave de la bóveda cifrada por el Android Keystore (solo si se activa
  // el desbloqueo con huella).
  final biometric = BiometricUnlock(
    store: FileVaultStore('${dir.path}/biometric.key'),
  );
  runApp(
    CassaforteApp(
      session: session,
      clipboard: ClipboardGuard(),
      biometric: biometric,
      terms: TermsAcceptance(FileVaultStore('${dir.path}/terms.json')),
    ),
  );
  unawaited(session.initialize());
  unawaited(_deleteSharedBackups());
}

/// Al compartir una copia, Android necesita un archivo temporal (el PDF
/// cifrado) en la caché. Se borra en el siguiente inicio.
Future<void> _deleteSharedBackups() async {
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share');
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      if (f is File && f.uri.pathSegments.last.startsWith('cassaforte-')) {
        await f.delete();
      }
    }
  } catch (_) {
    // No es crítico: el archivo está cifrado.
  }
}
