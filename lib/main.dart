import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
    ),
  );
  unawaited(session.initialize());
}
