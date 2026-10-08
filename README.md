# Cassaforte

Gestor de contraseñas para Android, personal y **totalmente local**: sin cuentas, servidores, sincronización, publicidad ni analítica. Hecho con Flutter/Dart.

> ⚠️ **No hay recuperación posible.** Si olvidas la contraseña maestra, o si se pierden los datos del móvil (desinstalar la app, borrar sus datos, restablecer o perder el teléfono), la bóveda no se puede recuperar. Cassaforte no hace copias automáticas en la nube: **exporta la copia de seguridad en PDF** desde *Ajustes*, imprímela o guárdala fuera del teléfono.

## Funciones

- Bóveda protegida por contraseña maestra (mínimo 10 caracteres, se pide dos veces y hay que aceptar el aviso de no recuperación).
- Cuentas con **nombre**, **usuario** y **contraseña** (siempre al final). El botón «Añadir campo» (debajo de la contraseña, junto a «Generar contraseña») pide el nombre del campo en una alerta y lo agrega vacío entre el usuario y la contraseña (p. ej., «Número de cliente» o un PIN, que puede marcarse como oculto). Las cuentas antiguas con dirección web o notas las conservan como campos extra al editarlas.
- Añadir, consultar, editar, eliminar (con confirmación) y buscar (por nombre, dirección, usuario y notas).
- Contraseñas ocultas por defecto, con botón para mostrarlas.
- Generador de contraseñas con `Random.secure()` (CSPRNG del sistema): longitud de 8 a 64; minúsculas, mayúsculas, números y símbolos; opción para evitar caracteres ambiguos. Garantiza al menos un carácter de cada tipo elegido.
- Copiar al portapapeles con borrado automático a los 20 s, **solo si** el portapapeles sigue conteniendo lo que copió Cassaforte.
- Bloqueo al pasar a segundo plano y tras 2 minutos sin actividad.
- **Desbloqueo con huella o con el patrón/PIN del teléfono** (Android 11+), opcional. La contraseña maestra se sigue pidiendo para las copias y si Android invalida la llave.
- **Copias de seguridad en PDF con códigos QR cifrados** (ver abajo): exportar desde *Ajustes* (guardar, imprimir o compartir) y recuperar en un teléfono nuevo con «Recuperar mis contraseñas», escaneando los QR con la cámara o eligiendo el PDF. Dentro de la bóveda también se puede importar una copia (fusionar o reemplazar). Los archivos `.cassaforte` de versiones anteriores se siguen pudiendo restaurar e importar.
- **Términos de uso** (`lib/src/legal/terms.dart`): hay que aceptarlos al crear la bóveda o restaurar una copia; las bóvedas existentes los piden una vez al abrirlas (si no se aceptan, la app se vuelve a bloquear). Se pueden leer en Ajustes. Se guarda solo la versión aceptada y la fecha, sin datos personales. Cambiar `termsVersion` vuelve a pedirlos. *No son asesoramiento legal: conviene que un abogado los revise antes de publicar la app.*
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
| Bloqueo y operaciones asíncronas | Cada bloqueo incrementa un contador de sesión. Un desbloqueo o creación en curso que termine después del bloqueo se descarta y la sesión sigue bloqueada. Un guardado en curso termina de escribirse (archivo completo y cifrado) pero no reabre la sesión. Los guardados se encadenan para que no se pisen. Al bloquear, la pantalla de desbloqueo tapa la app: lo que había abierto (p. ej., un formulario a medio completar) queda oculto, sin foco ni semántica, y las contraseñas vuelven a ocultarse; al desbloquear se sigue donde se estaba. |
| Huella / patrón | La clave de la bóveda se cifra (AES-256-GCM) con una llave del Android Keystore, generada en StrongBox si existe, no exportable, que exige `BIOMETRIC_STRONG` o el bloqueo de pantalla en **cada** uso (`setUserAuthenticationParameters(0, …)`) y se invalida al añadir huellas o quitar el bloqueo (`setInvalidatedByBiometricEnrollment`). Se usa el `BiometricPrompt` del sistema con `CryptoObject`. Solo se guarda en disco la clave ya cifrada por esa llave. |
| Copias (PDF con QR) | Ver «Copia de seguridad en PDF». Exportar exige escribir la contraseña maestra. Restaurar descifra y valida todo antes de escribir, en una única escritura atómica, y nunca sobrescribe una bóveda existente. Importar no cambia la contraseña maestra actual. |
| Pantallas del sistema | Mientras está abierto el diálogo de huella o el selector de archivos no se bloquea por pasar a segundo plano; al cerrarse, si la app no vuelve a primer plano en 2 s, se bloquea. Un desbloqueo con huella iniciado antes de un bloqueo se descarta. |
| Pantalla | `FLAG_SECURE`: sin capturas ni grabación, y contenido oculto en «Recientes». |
| Copias de seguridad | `allowBackup="false"` y reglas que excluyen todo de la copia en la nube y de la transferencia entre dispositivos. |
| Red y permisos | La versión release no tiene permiso `INTERNET`. Sus permisos son `USE_BIOMETRIC` (huella) y `CAMERA` (solo para escanear los QR de una copia, pedido en ese momento). Los permisos de micrófono y almacenamiento que declara el paquete de cámara se eliminan del manifiesto; el workflow falla si aparecen (se elimina explícitamente en el manifiesto release y el workflow lo comprueba en el APK). |
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
- **Copias exportadas:** su seguridad depende por completo de la contraseña maestra. Quien obtenga el PDF o una foto de la hoja impresa puede intentar adivinarla sin límite de intentos. Nunca escribas la contraseña maestra en la hoja.
- **La copia es una foto de un momento:** no se actualiza sola; hay que volver a exportarla tras cambios. Si se cambia la contraseña maestra, las copias anteriores siguen pidiendo la contraseña con la que se hicieron.
- **Compartir el PDF** deja una copia (cifrada) en la caché de la app hasta el siguiente inicio, y la app a la que lo compartas (correo, nube…) guarda su propia copia.
- El paquete `printing` (imprimir, compartir y leer PDF) incluye código para descargar imágenes de Internet que Cassaforte no usa; sin permiso `INTERNET` no podría conectarse aunque se usara.
- **Huella:** quien conozca el patrón/PIN del teléfono (o use tu dedo) puede abrir Cassaforte. En un teléfono con root o malware que controle el sistema, el Keystore puede usarse mientras el teléfono está desbloqueado. Si cambian las huellas o el bloqueo de pantalla, Android destruye la llave y hay que usar la contraseña maestra (la app lo detecta y ofrece reactivarla). Requiere Android 11 o superior.
- **Formulario a medio completar:** lo que se estaba escribiendo se conserva en memoria mientras la bóveda está bloqueada (oculto bajo la pantalla de bloqueo) para no perderlo. Si Android cierra la app en segundo plano, se pierde.
- Mientras está abierto el diálogo de huella o el selector de archivos, el bloqueo por pasar a segundo plano se aplaza (el bloqueo por inactividad sigue funcionando).
- Argon2id se ejecuta en Dart puro: en móviles lentos el desbloqueo puede tardar varios segundos.

## Arquitectura

```
lib/
  main.dart                       arranque
  src/backup/                     copia en PDF con QR: cifrado, Base45,
                                  fragmentos, PDF, lectura de QR en Dart
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

Las pruebas (101) cubren:

- **Cifrado:** vector oficial de Argon2id (RFC 9106 §5.3), vector de AES-256-GCM, ida y vuelta, nonce distinto en cada cifrado, ausencia de texto en claro, clave incorrecta, alteración de cada byte del texto cifrado, del nonce y de los parámetros de la cabecera, formatos no válidos.
- **Persistencia:** crear, guardar, editar, eliminar y reabrir desde disco; no sobrescribir una bóveda existente; escritura atómica cuando falla la escritura y con temporales huérfanos; un guardado fallido no altera el estado.
- **Contraseña incorrecta y archivo alterado/dañado:** se rechazan sin escribir nada.
- **Bloqueo de sesión:** bloqueo durante el desbloqueo, la creación y el guardado; guardados simultáneos; bloqueo por inactividad.
- **Generador** y **portapapeles** (borrado, no borrar lo copiado después, reintento al volver a primer plano).
- **Copia en PDF con QR:** exportar y restaurar 1, 20, 50 y 100 cuentas leyendo los QR de las hojas (con relectura a otra resolución) y conservando exactamente nombre, URL, usuario, contraseña, notas, campos y fechas; 10 copias de 100 cuentas seguidas; QR desordenados y repetidos; códigos faltantes; códigos de otra copia; códigos ajenos o dañados; fragmento falsificado con suma de control válida; contraseña incorrecta; datos alterados; formatos y parámetros no válidos; bomba de compresión; ausencia de texto en claro en los QR y en el PDF; hojas desplazadas (PDF escaneado); restauración sin red (`HttpOverrides` que falla ante cualquier conexión); vectores de Base45 (RFC 9285). Interfaz: exportar → guardar/imprimir/compartir → recuperar en otro teléfono desde el PDF (con contraseña incorrecta primero), con la cámara (en desorden, repetidos, de otra copia y ajenos), sin permiso de cámara, archivos inválidos y faltantes, e importar dentro de la bóveda. Sesión: restauración atómica, sin bóveda parcial si falla la escritura y sin sobrescribir.
- **Copias `.cassaforte` anteriores:** exportar exige la maestra, abrir con contraseña incorrecta o archivo alterado falla, restaurar en un teléfono nuevo, no sobrescribir, fusionar (gana la versión más reciente) y reemplazar.
- **Huella** (con un Keystore simulado): activar, desbloquear, cancelar, llave invalidada, clave que no corresponde a la bóveda, bloqueo durante el desbloqueo y desactivar.
- **Interfaz:** flujo completo (crear, añadir, buscar, contraseña oculta, bloqueo al pasar a segundo plano, contraseña incorrecta, confirmación al eliminar), conservar un formulario a medio completar tras bloquear, campos adicionales (orden, ocultos, quitar, conversión de cuentas antiguas), generador, restaurar/exportar copias y aceptación de los Términos de uso.

## Copia de seguridad en PDF

*Ajustes → Exportar copia de seguridad* crea un PDF A4 que solo contiene códigos QR, su numeración («3 / 12») y un identificador de copia. No contiene ningún nombre, usuario ni contraseña legible. Se puede **guardar** (selector de archivos), **imprimir** (diálogo de impresión de Android, que también permite «Guardar como PDF») o **compartir**.

Para recuperar en otro teléfono: *Recuperar mis contraseñas* → **Escanear códigos QR** (en cualquier orden; muestra «3 de 12 códigos escaneados», ignora repetidos y avisa si un código es de otra copia o está dañado) o **Seleccionar archivo PDF** (lee todas las hojas). Después pide la contraseña maestra **que tenías al exportar**.

Formato (versión 1):

1. Las cuentas se serializan con el mismo JSON versionado de la bóveda (todos los campos y fechas) y se **comprimen con GZIP antes de cifrar**.
2. Se cifran con **AES-256-GCM**. La clave se deriva de la contraseña maestra con **Argon2id** (64 MiB, 3 pasadas, 4 carriles) y una **sal aleatoria propia de la copia**. El nonce también es nuevo. La cabecera binaria (`CSFB`, versión, parámetros, sal, nonce) se autentica como AAD.
3. El resultado se divide en fragmentos de tamaño parecido. Cada uno lleva `CQ`, versión, el **identificador de la copia** (8 bytes de SHA-256 de la copia completa), posición, total, una variante y una suma de control (4 bytes de SHA-256).
4. Cada fragmento va en un QR en **modo alfanumérico con Base45** (RFC 9285), que transporta datos binarios casi sin desperdicio. Usa **corrección de errores M** y como máximo **versión 20**, que impresa en 6 por hoja A4 tiene módulos de unos 0,75 mm. Cien cuentas típicas ocupan **unos 12 QR en 2 hojas**.
5. **Cada QR se verifica antes de ponerlo en el PDF:** se dibuja a 3, 4, 5 y 6 píxeles por módulo y se lee con el detector de ZXing. Si falla, se genera otra variante (los datos del fragmento se mezclan con XOR con una secuencia derivada de la variante, lo que produce otro dibujo). Esto es necesario: en las pruebas, ZXing (tanto el port en Dart como la biblioteca original en Java) no encontraba alrededor del 2 % de los QR con datos aleatorios, aunque estuvieran dibujados perfectos. ZXing-C++ sí los leía, así que el problema era del detector y no del QR.
6. Al leer, los fragmentos se juntan en cualquier orden. Se rechazan los de otra copia, los dañados y los que contradicen a uno ya leído. Al final se comprueba que el SHA-256 de lo reconstruido coincide con el identificador **antes** de pedir la contraseña, y después GCM verifica todo.
7. Límites contra archivos maliciosos: PDF ≤ 30 MB y ≤ 100 hojas; copia cifrada ≤ 1 MiB; datos descomprimidos ≤ 16 MiB; ≤ 2000 fragmentos; parámetros de Argon2id acotados.

La lectura de QR (desde el PDF y desde la cámara) se hace en Dart con `zxing2`, en otro isolate y sin conexión. Las hojas del PDF se rasterizan con el renderizador de Android (`PdfRenderer`, vía `printing`) a 200 ppp; si faltan códigos se vuelven a leer a 300 y 150 ppp. En cada hoja se busca primero en la posición conocida de cada QR (también como «código puro») y, si no, en toda la hoja (para PDF escaneados de papel).

### Prueba manual de la copia (pendiente en un teléfono real)

1. Crear unas 20–100 cuentas de prueba (no reales) → *Ajustes → Exportar copia de seguridad* → Guardar PDF.
2. Abrir el PDF en otro dispositivo y comprobar que no se lee ningún dato de las cuentas.
3. Imprimirlo en A4 al 100 % (sin «ajustar a página» si es posible).
4. Desinstalar Cassaforte (o usar otro teléfono), instalarla, *Recuperar mis contraseñas*:
   - **Escanear códigos QR** desde la hoja impresa y también desde la pantalla de una computadora, en desorden y repitiendo alguno.
   - **Seleccionar archivo PDF** con el PDF guardado.
5. Escribir mal la contraseña una vez y después la correcta, y comprobar que las cuentas son idénticas.
6. Escanear un QR de otra copia y comprobar que se rechaza.

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
- Probar en un dispositivo Android real la copia en PDF con QR (ver «Prueba manual de la copia»): lectura con la cámara desde papel y pantalla, lectura del PDF con el renderizador real de Android, imprimir y compartir. Las pruebas automáticas dibujan las hojas como lo haría un visor de PDF y simulan la cámara; el renderizador de Android y la cámara real solo se han compilado.
- Probar en un dispositivo Android real la huella y el patrón (activar, desbloquear, cancelar, añadir una huella nueva para comprobar la invalidación) y exportar/importar/restaurar copias con el selector de archivos. Las pruebas automáticas simulan el Keystore y el selector: el código nativo solo se ha compilado.
- Probar también: `FLAG_SECURE`, bloqueo al pasar a segundo plano, borrado del portapapeles (incluido el caso en segundo plano), exclusión de copias de seguridad, tiempo de desbloqueo con Argon2id y que la app funcione sin red.
- Hacer una revisión de seguridad independiente: el diseño usa primitivas estándar, pero no lo ha auditado un tercero.

**Recomendación:** no guardes contraseñas reales hasta que el APK compile en Actions, hayas probado los puntos anteriores en tu móvil y configurado tu propia clave de firma. Aun así, conserva otra copia de las contraseñas críticas mientras ganas confianza en la app.
