import 'package:flutter/material.dart';

import '../../crypto/kdf.dart';
import '../../session/vault_session.dart';
import '../widgets/common.dart';

/// Explica cómo se protege la bóveda y qué limitaciones tiene.
class SecurityInfoScreen extends StatelessWidget {
  const SecurityInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const memoryMiB = KdfParams.defaultMemoryKiB ~/ 1024;
    final autoLock = VaultSession.defaultAutoLock.inMinutes;
    final theme = Theme.of(context);
    Widget section(String title, List<String> items) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad y limitaciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CenteredBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RecoveryWarning(),
                  const SizedBox(height: 16),
                  section('Cómo se protege', [
                    'Todo el contenido (nombres, direcciones, usuarios, '
                        'contraseñas y notas) se cifra con AES-256-GCM.',
                    'La clave se deriva de tu contraseña maestra con '
                        'Argon2id ($memoryMiB MiB, '
                        '${KdfParams.defaultIterations} pasadas, '
                        '${KdfParams.defaultParallelism} carriles) y una sal '
                        'aleatoria.',
                    'La contraseña maestra nunca se guarda, y la clave '
                        'nunca se guarda sin cifrar.',
                    'Los datos solo están en este teléfono: sin cuentas, '
                        'servidores, sincronización ni permiso de Internet.',
                    'Se bloquea al salir de la aplicación y tras '
                        '$autoLock minutos sin actividad.',
                    'Se impiden capturas de pantalla y los datos se '
                        'excluyen de las copias de seguridad de Android.',
                    'Con la huella activada, la clave de la bóveda se guarda '
                        'cifrada por una llave del chip seguro del teléfono '
                        'que no se puede extraer y que exige huella o '
                        'bloqueo de pantalla en cada uso.',
                    'La copia de seguridad en PDF solo contiene códigos QR '
                        'cifrados (AES-256-GCM con una clave Argon2id de tu '
                        'contraseña maestra y una sal propia). No muestra '
                        'ningún dato de tus cuentas.',
                    'La cámara solo se usa para escanear los códigos de '
                        'una copia y se pide en ese momento.',
                  ]),
                  section('Limitaciones', [
                    'No hay recuperación: sin la contraseña maestra la '
                        'bóveda no se puede abrir.',
                    'Desinstalar la aplicación o borrar sus datos elimina '
                        'la bóveda. Exportá la copia en PDF para no perderla.',
                    'Mientras está desbloqueada, los datos descifrados '
                        'están en la memoria del teléfono. Un móvil con '
                        'malware o con root puede leerlos.',
                    'Al copiar, otras aplicaciones o el teclado podrían '
                        'leer el portapapeles. Se intenta borrar a los 20 '
                        'segundos, pero si la aplicación está en segundo '
                        'plano Android puede impedirlo hasta que vuelvas.',
                    'Una contraseña maestra débil puede adivinarse si '
                        'alguien obtiene el archivo cifrado.',
                    'Una copia exportada (el PDF o la hoja impresa) es tan '
                        'segura como tu contraseña maestra: quien la consiga '
                        'puede intentar adivinarla sin límite. Nunca la '
                        'escribas en la misma hoja.',
                    'La copia no se actualiza sola: volvé a exportarla '
                        'cuando cambies tus cuentas. Pide la contraseña '
                        'maestra que tenías al hacerla.',
                    'Con la huella activada, quien conozca el patrón o PIN '
                        'del teléfono también puede abrir Cassaforte.',
                    'Si cambian las huellas o el bloqueo de pantalla, '
                        'Android anula la llave y hay que usar la contraseña '
                        'maestra.',
                    'Lo que estés escribiendo en un formulario se conserva '
                        'en memoria mientras la bóveda está bloqueada, para '
                        'que no lo pierdas al volver.',
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
