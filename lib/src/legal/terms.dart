import 'dart:convert';
import 'dart:typed_data';

import '../storage/vault_store.dart';

/// Versión de los términos. Si cambia el texto de forma relevante, se sube
/// el número y la aplicación vuelve a pedir la aceptación.
const int termsVersion = 1;
const String termsDate = '6 de octubre de 2026';

class TermsSection {
  const TermsSection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

/// Términos de uso de Cassaforte.
const List<TermsSection> termsOfUse = [
  TermsSection('1. Qué es Cassaforte', [
    'Cassaforte es una aplicación gratuita para guardar contraseñas y otros '
        'datos de acceso de forma cifrada, únicamente en el teléfono del '
        'usuario. No usa cuentas, servidores, sincronización, publicidad ni '
        'analítica, y no tiene permiso de acceso a Internet.',
  ]),
  TermsSection('2. Aceptación', [
    'Al crear una bóveda o restaurar una copia de seguridad, el usuario '
        'declara haber leído y aceptado estos términos. Si no los acepta, '
        'no debe usar la aplicación.',
  ]),
  TermsSection('3. Uso «tal cual» y sin garantías', [
    'La aplicación se ofrece gratuitamente, «tal cual» y «según '
        'disponibilidad», sin garantías de ningún tipo, expresas o '
        'implícitas, incluidas las de funcionamiento ininterrumpido, ausencia '
        'de errores, idoneidad para un fin determinado o seguridad absoluta.',
    'Ningún sistema informático es completamente seguro. Cassaforte usa '
        'cifrado estándar (AES-256-GCM y Argon2id), pero no puede garantizar '
        'que los datos no sean obtenidos por terceros en todas las '
        'circunstancias.',
  ]),
  TermsSection('4. Responsabilidades del usuario', [
    'El usuario es el único responsable de:',
    '• La seguridad de su teléfono: bloqueo de pantalla, actualizaciones del '
        'sistema, no instalar aplicaciones maliciosas y no usar la aplicación '
        'en un teléfono con acceso root o modificado.',
    '• Elegir una contraseña maestra segura, recordarla y no compartirla. '
        'La contraseña maestra no se guarda en ningún lugar y no puede '
        'recuperarse.',
    '• Hacer y conservar copias de seguridad. Si se pierde, se restablece o '
        'se cambia el teléfono, o se desinstala la aplicación sin una copia, '
        'los datos se pierden definitivamente.',
    '• Las personas a quienes permita usar su teléfono, su huella o su '
        'bloqueo de pantalla.',
    '• El uso que haga de los datos que guarda y de los que copia al '
        'portapapeles.',
  ]),
  TermsSection('5. Limitaciones conocidas', [
    'Mientras la bóveda está abierta, los datos descifrados están en la '
        'memoria del teléfono. Un teléfono con software malicioso, con acceso '
        'root o en manos de otra persona mientras está desbloqueado puede '
        'exponer esos datos. Lo copiado al portapapeles puede ser leído por '
        'otras aplicaciones o por el teclado. Estas y otras limitaciones se '
        'detallan en «Seguridad y limitaciones», dentro de la aplicación.',
  ]),
  TermsSection('6. Limitación de responsabilidad', [
    'En la máxima medida permitida por la ley aplicable, el desarrollador '
        'de Cassaforte no será responsable por:',
    '• La pérdida, alteración o imposibilidad de acceder a los datos '
        'guardados, incluido el olvido de la contraseña maestra.',
    '• El acceso no autorizado a los datos como consecuencia de la '
        'vulneración, el robo, la pérdida o el uso indebido del teléfono del '
        'usuario, de su sistema operativo, de otras aplicaciones o de sus '
        'copias de seguridad.',
    '• Los daños directos, indirectos, incidentales, especiales o '
        'consecuentes, incluidos los perjuicios económicos, derivados del '
        'uso o de la imposibilidad de usar la aplicación.',
    'Nada de lo dispuesto en estos términos excluye ni limita la '
        'responsabilidad que, según la ley aplicable, no pueda excluirse o '
        'limitarse, ni los derechos que la ley reconozca al usuario de forma '
        'irrenunciable.',
  ]),
  TermsSection('7. Privacidad', [
    'Cassaforte no recoge, no almacena fuera del teléfono y no envía ningún '
        'dato personal ni de uso. El desarrollador no tiene acceso a la '
        'bóveda, a la contraseña maestra ni a las copias de seguridad del '
        'usuario.',
  ]),
  TermsSection('8. Cambios y fin del servicio', [
    'La aplicación puede modificarse, dejar de actualizarse o dejar de '
        'distribuirse en cualquier momento. Estos términos pueden '
        'actualizarse; cuando cambien, la aplicación pedirá aceptarlos de '
        'nuevo para seguir usándola.',
  ]),
];

/// Recuerda si se aceptó la versión vigente de los términos. Se guarda en
/// un archivo sin cifrar (no contiene datos personales): versión y fecha.
class TermsAcceptance {
  TermsAcceptance(this._store);

  final VaultStore _store;

  Future<bool> isAccepted() async {
    try {
      if (!await _store.exists()) return false;
      final doc = jsonDecode(utf8.decode(await _store.read()));
      return doc is Map<String, Object?> && doc['version'] == termsVersion;
    } catch (_) {
      return false;
    }
  }

  Future<void> accept() => _store.writeAtomic(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': termsVersion,
          'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
    ),
  );
}
