# Cassaforte

Gestor de contraseñas para Android, personal y **totalmente local**: sin cuentas, servidores, sincronización, publicidad ni analítica. Hecho con Flutter/Dart.

> ⚠️ **No hay recuperación posible.** Si olvidas la contraseña maestra, o si se pierden los datos del móvil (desinstalar la app, borrar sus datos, restablecer o perder el teléfono), la bóveda no se puede recuperar. Cassaforte no hace copias automáticas en la nube: **exporta copias cifradas** desde *Ajustes* y guárdalas fuera del teléfono.

## Funciones

- Bóveda protegida por contraseña maestra (mínimo 10 caracteres, se pide dos veces y hay que aceptar el aviso de no recuperación).
- Cuentas con nombre de la página, dirección web, usuario o correo, contraseña y notas opcionales.
- Añadir, consultar, editar, eliminar (con confirmación) y buscar (por nombre, dirección, usuario y notas).
- Contraseñas ocultas por defecto, con botón para mostrarlas.
- Generador de contraseñas con `Random.secure()` (CSPRNG del sistema): longitud de 8 a 64; minúsculas, mayúsculas, números y símbolos; opción para evitar caracteres ambiguos. Garantiza al menos un carácter de cada tipo elegido.
- Copiar al portapapeles con borrado automático a los 20 s, **solo si** el portapapeles sigue conteniendo lo que copió Cassaforte.
- Bloqueo al pasar a segundo plano y tras 2 minutos sin actividad.
- **Desbloqueo con huella o con el patrón/PIN del teléfono** (Android 11+), opcional. La contraseña maestra se sigue pidiendo para las copias y si Android invalida la llave.
- **Copias de seguridad cifradas**: exportar la bóveda a un archivo `.cassaforte` (donde elijas: Descargas, Drive, USB…) e importarla (fusionar o reemplazar) o restaurarla al empezar en un teléfono nuevo.
- Interfaz en español, Material 3, tema claro/oscuro, adaptada a pantallas grandes.

## Diseño de seguridad

| Aspecto | Implementación |
|---|---|
| Cifrado | AES-256-GCM (cifrado autenticado), paquete [`cryptography`](https://pub.dev/packages/cryptography) 2.9.0 |
| Derivación de clave | Argon2id (v1.3), **64 MiB de memoria, 3 pasadas, 4 carriles**, sal aleatoria de 16 bytes, clave de 32 bytes (segunda configuración recomendada por RFC 9106). Se ejecuta en un *isolate* aparte. |
| Nonce | 12 bytes aleatorios nuevos en **cada** guardado |
| Qué se cifra | Todo el contenido: nombres, direcciones, usuarios, contraseñas, notas y fechas |
| Cabecera | Formato, versión, parámetros de Argon2id, sal y nonce (en claro, necesarios para descifrar). Los parámetros se autentican como AAD: cualquier cambio hace fallar el descifrado. Se rechazan parámetros fuera de límites razonables. |
| Contraseña maestra y clave | La contraseña maestra nunca se guarda. La clave nunca se guarda sin cifrar (solo cifrada por el Keystore si se activa la huella); no aparece en preferencias ni registros. La clave solo existe en memoria mientras la bóveda está abierta y se sobrescribe con ceros al bloquear. |
| Contraseña incorrecta / archivo alterado | Falla la autenticación GCM y no se escribe nada. Un archivo dañado nunca se sobrescribe; la creación de una bóveda nueva se niega si ya existe una. |
| Guardado atómico | Se escribe `vault.cassaforte.tmp`, se vuelca a disco (`flush`) y se renombra sobre el archivo final. Si algo falla, queda la versión anterior completa. |
| Bloqueo y operaciones asíncronas | Cada bloqueo incrementa un contador de sesión. Un desbloqueo o creación en curso que termine después del bloqueo se descarta y la sesión sigue bloqueada. Un guardado en curso termina de escribirse (archivo completo y cifrado) pero no reabre la sesión. Los guardados se encadenan para que no se pisen. Al bloquear se cierran todas las pantallas y diálogos. |
| Huella / patrón | La clave de la bóveda se cifra (AES-256-GCM) con una llave del Android Keystore, generada en StrongBox si existe, no exportable, que exige `BIOMETRIC_STRONG` o el bloqueo de pantalla en **cada** uso (`setUserAuthenticationParameters(0, …)`) y se invalida al añadir huellas o quitar el bloqueo (`setInvalidatedByBiometricEnrollment`). Se usa el `BiometricPrompt` del sistema con `CryptoObject`. Solo se guarda en disco la clave ya cifrada por esa llave. |
| Copias | El archivo exportado es el mismo archivo cifrado de la bóveda (misma cabecera, Argon2id + AES-256-GCM). Exportar exige escribir la contraseña maestra. Importar la valida y descifra antes de tocar nada; las cuentas importadas se vuelven a cifrar con la clave actual (la contraseña maestra no cambia). Restaurar nunca sobrescribe una bóveda existente. Se usa el selector de archivos del sistema, sin permisos de almacenamiento. |
| Pantallas del sistema | Mientras está abierto el diálogo de huella o el selector de archivos no se bloquea por pasar a segundo plano; al cerrarse, si la app no vuelve a primer plano en 2 s, se bloquea. Un desbloqueo con huella iniciado antes de un bloqueo se descarta. |
| Pantalla | `FLAG_SECURE`: sin capturas ni grabación, y contenido oculto en «Recientes». |
| Copias de seguridad | `allowBackup="false"` y reglas que excluyen todo de la copia en la nube y de la transferencia entre dispositivos. |
| Red | La versión release no tiene permiso `INTERNET` (se elimina explícitamente en el manifiesto release y el workflow lo comprueba en el APK). |
| Teclado | Campos sin sugerencias, autocorrección ni aprendizaje personalizado (modo incógnito del teclado, si el teclado lo respeta). |
| Portapapeles | El contenido se marca como sensible (Android 13+ no lo muestra en la vista previa). Para saber si sigue siendo nuestra copia se compara la marca de tiempo de la copia, sin leer el texto. |

Formato del archivo (`files/vault.cassaforte`, en el directorio privado de la app):

```json
{
  "format": "cassaforte-vault", "version": 1,
  "kdf": {"algorithm": "argon2id", "version": 19, "memoryKiB": 65536,
          "iterations": 3, "parallelism": 4, "salt": "<base64>"},
  "cipher": {"algorithm": "aes-256-gcm", "nonce": "<base64>"},
  "ciphertext": "<base64: texto cifrado || etiqueta>"
}
```

### Limitaciones reales (sin promesas absolutas)

- **Memoria:** mientras la bóveda está abierta, los datos descifrados están en la memoria del proceso. Dart no permite borrar de forma fiable las cadenas (`String`) ni controlar el recolector de basura, así que pueden quedar copias de contraseñas en memoria hasta que se reutilice. Malware con privilegios, un móvil rooteado o un volcado de memoria pueden leerlas.
- **Portapapeles:** mientras una contraseña está copiada, el teclado, servicios de accesibilidad u otras apps con acceso pueden leerla. En Android 10+ una app en segundo plano no puede consultar el portapapeles: si a los 20 s Cassaforte no está en primer plano, el borrado se hace al volver a abrirla. Si el proceso termina antes, no se borra (Android 13+ lo borra solo al cabo de un tiempo). Algunos teclados guardan historial de portapapeles propio.
- **Contraseña maestra débil:** quien obtenga el archivo cifrado puede intentar adivinarla sin límite de intentos; Argon2id solo lo encarece. Usa una frase larga.
- **Metadatos:** el tamaño del archivo revela aproximadamente cuánto contenido hay.
- **Dispositivo:** la seguridad depende del sistema Android (bloqueo de pantalla, cifrado del almacenamiento, ausencia de root/malware). No hay protección contra un atacante con acceso al móvil desbloqueado mientras la bóveda está abierta.
- **Durabilidad:** el renombrado es atómico, pero Dart no permite sincronizar el directorio; un corte de energía justo en ese momento podría, en casos raros, dejar la versión anterior.
- **Copias manuales:** no hay copia automática. Si no exportas copias y pierdes el móvil o desinstalas la app, pierdes la bóveda.
- **Copias exportadas:** su seguridad depende por completo de la contraseña maestra. Quien obtenga el archivo puede intentar adivinarla sin límite de intentos.
- **Huella:** quien conozca el patrón/PIN del teléfono (o use tu dedo) puede abrir Cassaforte. En un teléfono con root o malware que controle el sistema, el Keystore puede usarse mientras el teléfono está desbloqueado. Si cambian las huellas o el bloqueo de pantalla, Android destruye la llave y hay que usar la contraseña maestra (la app lo detecta y ofrece reactivarla). Requiere Android 11 o superior.
- Mientras está abierto el diálogo de huella o el selector de archivos, el bloqueo por pasar a segundo plano se aplaza (el bloqueo por inactividad sigue funcionando).
- Argon2id se ejecuta en Dart puro: en móviles lentos el desbloqueo puede tardar varios segundos.

## Arquitectura

```
lib/
  main.dart                       arranque
  src/crypto/kdf.dart             Argon2id y parámetros
  src/crypto/vault_cipher.dart    formato de archivo y AES-256-GCM
  src/storage/vault_store.dart    escritura atómica en disco
  src/model/vault_entry.dart      modelo de cuenta y serialización
  src/session/vault_session.dart  estado, bloqueo, inactividad y concurrencia
  src/security/                   generador y portapapeles
  src/ui/                         pantallas y widgets
android/app/src/main/kotlin/.../MainActivity.kt   FLAG_SECURE y portapapeles nativo
branding/                       imágenes originales del icono y la pantalla de inicio
tool/generate_branding.py       genera los iconos y la pantalla de inicio de Android
```

Para cambiar el icono o la pantalla de inicio, sustituye las imágenes de `branding/` y ejecuta `python3 tool/generate_branding.py` (requiere Pillow). Se generan el icono adaptativo (con versión monocroma para iconos temáticos), el icono clásico y la pantalla de inicio para Android 12+ y anteriores.

## Pruebas

```bash
flutter pub get
flutter analyze
flutter test
```

Las pruebas (61) cubren:

- **Cifrado:** vector oficial de Argon2id (RFC 9106 §5.3), vector de AES-256-GCM, ida y vuelta, nonce distinto en cada cifrado, ausencia de texto en claro, clave incorrecta, alteración de cada byte del texto cifrado, del nonce y de los parámetros de la cabecera, formatos no válidos.
- **Persistencia:** crear, guardar, editar, eliminar y reabrir desde disco; no sobrescribir una bóveda existente; escritura atómica cuando falla la escritura y con temporales huérfanos; un guardado fallido no altera el estado.
- **Contraseña incorrecta y archivo alterado/dañado:** se rechazan sin escribir nada.
- **Bloqueo de sesión:** bloqueo durante el desbloqueo, la creación y el guardado; guardados simultáneos; bloqueo por inactividad.
- **Generador** y **portapapeles** (borrado, no borrar lo copiado después, reintento al volver a primer plano).
- **Copias:** exportar exige la maestra, abrir con contraseña incorrecta o archivo alterado falla, restaurar en un teléfono nuevo, no sobrescribir, fusionar (gana la versión más reciente) y reemplazar.
- **Huella** (con un Keystore simulado): activar, desbloquear, cancelar, llave invalidada, clave que no corresponde a la bóveda, bloqueo durante el desbloqueo y desactivar.
- **Interfaz:** flujo completo (crear, añadir, buscar, contraseña oculta, bloqueo al pasar a segundo plano, contraseña incorrecta, confirmación al eliminar), generador, y restaurar/exportar copias.

## Compilación e instalación

### APK desde GitHub Actions

El workflow `.github/workflows/android.yml` se ejecuta manualmente (*Actions → Android APK → Run workflow*), al subir cambios a `main` (y a ramas `claude/**`) y en pull requests a `main`. Usa Flutter **3.47.6 (stable)** y Java 17, ejecuta `flutter pub get`, comprueba el formato, `flutter analyze` y `flutter test`, compila `flutter build apk --release`, verifica que el APK no pida permisos de red, muestra el certificado de firma y sube el APK como artefacto (30 días).

Para instalarlo: descarga el artefacto (un `.zip`), extrae el `.apk` en el móvil y ábrelo permitiendo «instalar apps de origen desconocido».

### Firma del APK (importante para no perder datos)

- **Sin configurar nada**, el APK se firma con la **clave de depuración que genera cada ejecución** de GitHub Actions. Cada compilación tiene una firma distinta: Android **no permite actualizar** una app con otra firma, y habría que desinstalarla, **lo que borra la bóveda**. Úsalo solo para probar, sin datos reales.
- **Para conservar tus datos entre versiones**, crea tu propia clave una sola vez y guárdala como secretos del repositorio (nunca en el código):

```bash
keytool -genkeypair -v -keystore cassaforte-release.jks -alias cassaforte \
  -keyalg RSA -keysize 4096 -validity 10000
base64 -w 0 cassaforte-release.jks > keystore.b64
```

En GitHub: *Settings → Secrets and variables → Actions → New repository secret*:

| Secreto | Valor |
|---|---|
| `CASSAFORTE_KEYSTORE_BASE64` | contenido de `keystore.b64` |
| `CASSAFORTE_KEYSTORE_PASSWORD` | contraseña del almacén |
| `CASSAFORTE_KEY_ALIAS` | `cassaforte` |
| `CASSAFORTE_KEY_PASSWORD` | contraseña de la clave (si es la misma, puede omitirse) |

Guarda el `.jks` y sus contraseñas en un lugar seguro y fuera del repositorio: si los pierdes, no podrás publicar actualizaciones instalables sobre la versión existente. El resumen del workflow indica qué firma se usó y la huella SHA-256 del certificado; comprueba que sea siempre la misma. Si ya instalaste una versión con firma de depuración, tendrás que desinstalarla (y perder su bóveda) para pasar a la firma propia, así que configura la clave antes de guardar datos reales.

### Compilar en local

```bash
flutter build apk --release
# con clave propia:
CASSAFORTE_KEYSTORE_PATH=/ruta/cassaforte-release.jks \
CASSAFORTE_KEYSTORE_PASSWORD=... CASSAFORTE_KEY_ALIAS=cassaforte \
CASSAFORTE_KEY_PASSWORD=... flutter build apk --release
```

## Estado de verificación

**Hecho:**
- `flutter analyze` sin problemas y `flutter test` con todas las pruebas superadas, en local y en GitHub Actions (Flutter 3.47.6).
- El workflow compila el APK release (código Kotlin y Gradle incluidos), comprueba que solo declara el permiso interno `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` de AndroidX y ninguno de red, y lo sube como artefacto.

**Pendiente:**
- Probar en un dispositivo Android real la huella y el patrón (activar, desbloquear, cancelar, añadir una huella nueva para comprobar la invalidación) y exportar/importar/restaurar copias con el selector de archivos. Las pruebas automáticas simulan el Keystore y el selector: el código nativo solo se ha compilado.
- Probar también: `FLAG_SECURE`, bloqueo al pasar a segundo plano, borrado del portapapeles (incluido el caso en segundo plano), exclusión de copias de seguridad, tiempo de desbloqueo con Argon2id y que la app funcione sin red.
- Hacer una revisión de seguridad independiente: el diseño usa primitivas estándar, pero no lo ha auditado un tercero.

**Recomendación:** no guardes contraseñas reales hasta que el APK compile en Actions, hayas probado los puntos anteriores en tu móvil y configurado tu propia clave de firma. Aun así, conserva otra copia de las contraseñas críticas mientras ganas confianza en la app.
