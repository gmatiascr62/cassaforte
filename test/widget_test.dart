import 'dart:convert';
import 'dart:typed_data';

import 'package:cassaforte/src/crypto/kdf.dart';
import 'package:cassaforte/src/crypto/vault_cipher.dart';
import 'package:cassaforte/src/legal/terms.dart';
import 'package:cassaforte/src/model/vault_entry.dart';
import 'package:cassaforte/src/security/biometric_unlock.dart';
import 'package:cassaforte/src/security/clipboard_guard.dart';
import 'package:cassaforte/src/session/vault_session.dart';
import 'package:cassaforte/src/ui/cassaforte_app.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Derivación rápida SOLO para las pruebas de interfaz (las pruebas de
/// cifrado usan Argon2id real).
class FakeKdf implements KeyDerivation {
  @override
  Future<Uint8List> deriveKey(String password, KdfParams params) async {
    final hash = await Sha256().hash([
      ...params.salt,
      ...utf8.encode(password),
    ]);
    return Uint8List.fromList(hash.bytes);
  }
}

Future<TermsAcceptance> acceptedTerms() async {
  final terms = TermsAcceptance(MemoryVaultStore());
  await terms.accept();
  return terms;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('flujo completo: crear, añadir, ver, bloquear, eliminar', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    final clipboard = ClipboardGuard(clipboard: FakeClipboard());
    final terms = TermsAcceptance(MemoryVaultStore());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: clipboard,
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: FakeBackupFiles(),
        terms: terms,
      ),
    );
    await session.initialize();
    await tester.pumpAndSettle();

    // Configuración con aviso de recuperación.
    expect(find.text('Bienvenido a Cassaforte'), findsOneWidget);
    expect(find.textContaining('no habrá forma de recuperar'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'contraseña maestra 1');
    await tester.enterText(fields.at(1), 'contraseña maestra 2');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);

    await tester.enterText(fields.at(1), 'contraseña maestra 1');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(
      find.text('Debes confirmar que has leído el aviso.'),
      findsOneWidget,
    );
    expect(store.bytes, isNull);

    // Aviso aceptado, pero faltan los Términos de uso.
    await tapVisible(tester, find.byType(Checkbox).at(0));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(find.text('Debes aceptar los Términos de uso.'), findsOneWidget);
    expect(store.bytes, isNull);
    expect(await terms.isAccepted(), isFalse);

    // Se pueden leer desde la misma pantalla.
    await tapVisible(tester, find.text('Leer los Términos de uso'));
    await tester.pumpAndSettle();
    expect(find.text('6. Limitación de responsabilidad'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byType(Checkbox).at(1));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Crear bóveda'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(await terms.isAccepted(), isTrue);
    expect(find.textContaining('Aún no hay cuentas'), findsOneWidget);

    // Añadir una cuenta.
    await tapVisible(tester, find.text('Añadir'));
    await tester.pumpAndSettle();
    final form = find.byType(TextFormField);
    await tester.enterText(form.at(0), 'Correo');
    // Formulario: nombre, usuario y contraseña (al final).
    expect(form, findsNWidgets(3));
    await tester.enterText(form.at(1), 'yo@example.com');
    await tester.enterText(form.at(2), 'S3creta!');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Correo'), findsOneWidget);
    expect(session.entries, hasLength(1));

    // Búsqueda.
    await tester.enterText(find.byType(SearchBar), 'banco');
    await tester.pump();
    expect(find.text('Correo'), findsNothing);
    await tester.enterText(find.byType(SearchBar), 'CORR');
    await tester.pump();
    expect(find.text('Correo'), findsOneWidget);

    // Detalle: contraseña oculta por defecto.
    await tapVisible(tester, find.text('Correo'));
    await tester.pumpAndSettle();
    expect(find.text('S3creta!'), findsNothing);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(find.text('S3creta!'), findsOneWidget);

    // Pasar a segundo plano bloquea y cierra el detalle.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.locked);
    expect(find.text('La bóveda está bloqueada.'), findsOneWidget);
    expect(find.text('S3creta!'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Contraseña incorrecta.
    await tester.enterText(find.byType(TextFormField), 'no es esta');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Desbloquear'));
    await tester.pumpAndSettle();
    expect(
      find.text('Contraseña incorrecta o archivo alterado.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), 'contraseña maestra 1');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Desbloquear'));
    await tester.pumpAndSettle();
    // Se vuelve a la misma pantalla, con la contraseña oculta otra vez.
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    expect(find.text('S3creta!'), findsNothing);

    // Eliminar pide confirmación.
    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar cuenta?'), findsOneWidget);
    await tapVisible(tester, find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(session.entries, hasLength(1));

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(session.entries, isEmpty);
    expect(find.textContaining('Aún no hay cuentas'), findsOneWidget);

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('el generador entrega una contraseña al formulario', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: FakeBackupFiles(),
        terms: await acceptedTerms(),
      ),
    );
    await session.initialize();
    await session.create('contraseña maestra 1');
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Añadir'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Generar contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('Generador de contraseñas'), findsOneWidget);
    await tapVisible(tester, find.text('Usar esta contraseña'));
    await tester.pumpAndSettle();

    final passwordField = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).at(2),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordField.controller.text, hasLength(20));

    session.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('restaurar una copia al empezar y exportarla desde Ajustes', (
    tester,
  ) async {
    // Copia hecha en "otro teléfono".
    final source = VaultSession(
      store: MemoryVaultStore(),
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    await source.initialize();
    await source.create('contraseña maestra 1');
    await source.saveEntry(VaultEntry.create(title: 'Banco', password: 'x1'));
    final backup = await source.exportBackup('contraseña maestra 1');
    source.dispose();

    final store = MemoryVaultStore();
    final files = FakeBackupFiles()..toOpen = backup;
    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: files,
        terms: await acceptedTerms(),
      ),
    );
    await session.initialize();
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byType(Checkbox).at(1));
    await tapVisible(tester, find.text('Restaurar copia de seguridad'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      'contraseña maestra 1',
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(find.text('Banco'), findsOneWidget);

    // Exportar desde Ajustes.
    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar copia'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      'contraseña maestra 1',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(files.saved, store.bytes);
    expect(session.status, VaultStatus.unlocked);

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  Future<VaultSession> openVaultWith(
    WidgetTester tester,
    FakeBiometricPlatform platform,
  ) async {
    final session = VaultSession(
      store: MemoryVaultStore(),
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: platform,
        ),
        backupFiles: FakeBackupFiles(),
        terms: await acceptedTerms(),
      ),
    );
    await session.initialize();
    await session.create('contraseña maestra 1');
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('activar la huella desde Ajustes y desbloquear con ella', (
    tester,
  ) async {
    final platform = FakeBiometricPlatform();
    final session = await openVaultWith(tester, platform);

    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Comprobando'), findsNothing);
    final toggle = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(platform.prompts, 1);

    // Al bloquear, la pantalla de desbloqueo muestra la huella sola.
    session.lock();
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(platform.prompts, 2);

    // Si se cancela, queda el botón para intentarlo de nuevo.
    platform.cancelNext = true;
    session.lock();
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.locked);
    await tester.tap(find.text('Usar huella o patrón'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);

    // Al terminar, se bloquea sin volver a abrir.
    platform.cancelNext = true;
    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('si el sistema falla al comprobar la huella, no se queda '
      'en «Comprobando»', (tester) async {
    final platform = FakeBiometricPlatform()..failStatus = true;
    final session = await openVaultWith(tester, platform);

    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Comprobando'), findsNothing);
    expect(
      find.text('No se pudo comprobar la huella en este teléfono.'),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('lo que se estaba escribiendo se conserva tras bloquear', (
    tester,
  ) async {
    final platform = FakeBiometricPlatform()
      ..status = BiometricAvailability.unsupported;
    final session = await openVaultWith(tester, platform);

    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    final form = find.byType(TextFormField);
    await tester.enterText(form.at(0), 'Mi banco');
    await tester.enterText(form.at(2), 'a-medias');

    // Salir a otra aplicación bloquea la bóveda.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.locked);
    expect(find.text('Mi banco'), findsNothing); // oculto bajo el bloqueo
    expect(find.text('Nueva cuenta'), findsNothing);

    // «Atrás» con la bóveda bloqueada no descarta el formulario.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'contraseña maestra 1');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Desbloquear'));
    await tester.pumpAndSettle();

    // Seguimos en el formulario con lo escrito.
    expect(find.text('Nueva cuenta'), findsOneWidget);
    expect(find.text('Mi banco'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'yo@banco.example',
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    final saved = session.entries.single;
    expect(saved.title, 'Mi banco');
    expect(saved.password, 'a-medias');
    expect(saved.username, 'yo@banco.example');

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('campos adicionales entre el usuario y la contraseña', (
    tester,
  ) async {
    final platform = FakeBiometricPlatform()
      ..status = BiometricAvailability.unsupported;
    final session = await openVaultWith(tester, platform);

    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Banco');
    await tester.enterText(find.byType(TextFormField).at(1), 'juan');

    // «Añadir campo» está a la derecha, debajo de la contraseña y encima de
    // «Generar contraseña».
    final addY = tester.getCenter(find.text('Añadir campo')).dy;
    final genY = tester.getCenter(find.text('Generar contraseña')).dy;
    expect(addY, lessThan(genY));

    Future<void> addField(String name, {bool hidden = false}) async {
      await tapVisible(tester, find.text('Añadir campo'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo campo'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        name,
      );
      if (hidden) await tester.tap(find.byType(Checkbox));
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
      await tester.pumpAndSettle();
    }

    // Sin nombre no se añade.
    await tapVisible(tester, find.text('Añadir campo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
    await tester.pump();
    expect(find.text('Escribí un nombre.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await addField('Número de cliente');
    await addField('PIN', hidden: true);

    // Los campos nuevos aparecen vacíos, con su nombre, entre el usuario y
    // la contraseña.
    var fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5));
    String labelOf(int i) => tester
        .widget<TextField>(
          find.descendant(of: fields.at(i), matching: find.byType(TextField)),
        )
        .decoration!
        .labelText!;
    expect(
      [for (var i = 0; i < 5; i++) labelOf(i)],
      ['Nombre *', 'Usuario', 'Número de cliente', 'PIN', 'Contraseña *'],
    );
    await tester.enterText(fields.at(2), '12345');
    await tester.enterText(fields.at(3), '9876');
    await tester.enterText(fields.at(4), 'clave-final');

    // Un campo añadido y quitado (vacío) no se guarda.
    await addField('Sobra');
    expect(find.byType(TextFormField), findsNWidgets(6));
    await tapVisible(tester, find.byTooltip('Quitar Sobra'));
    await tester.pumpAndSettle();
    fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5));

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    final saved = session.entries.single;
    expect(saved.username, 'juan');
    expect(saved.password, 'clave-final');
    expect(saved.fields, const [
      CustomField(label: 'Número de cliente', value: '12345'),
      CustomField(label: 'PIN', value: '9876', hidden: true),
    ]);

    // En el detalle: el PIN oculto y la contraseña al final.
    await tester.tap(find.text('Banco'));
    await tester.pumpAndSettle();
    expect(find.text('12345'), findsOneWidget);
    expect(find.text('9876'), findsNothing);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where(
          (t) => const [
            'Nombre',
            'Usuario',
            'Número de cliente',
            'PIN',
            'Contraseña',
          ].contains(t),
        )
        .toList();
    expect(labels, [
      'Nombre',
      'Usuario',
      'Número de cliente',
      'PIN',
      'Contraseña',
    ]);
    await tester.tap(find.byTooltip('Mostrar PIN'));
    await tester.pump();
    expect(find.text('9876'), findsOneWidget);

    // Sigue igual tras bloquear y volver a abrir desde el archivo.
    session.lock();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'contraseña maestra 1');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Desbloquear'));
    await tester.pumpAndSettle();
    expect(session.entries.single.fields, hasLength(2));
    expect(find.text('9876'), findsNothing); // se vuelve a ocultar

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('editar una cuenta antigua conserva su dirección y sus notas', (
    tester,
  ) async {
    final platform = FakeBiometricPlatform()
      ..status = BiometricAvailability.unsupported;
    final session = await openVaultWith(tester, platform);
    final old = VaultEntry.create(
      title: 'Correo',
      url: 'https://correo.example',
      username: 'yo',
      password: 'x',
      notes: 'nota vieja',
    );
    await session.saveEntry(old);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Correo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('https://correo.example'), findsOneWidget);
    expect(find.text('nota vieja'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    final saved = session.entryById(old.id)!;
    expect(saved.url, isEmpty);
    expect(saved.notes, isEmpty);
    expect(saved.fields, const [
      CustomField(label: 'Dirección web', value: 'https://correo.example'),
      CustomField(label: 'Notas', value: 'nota vieja'),
    ]);

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('una bóveda existente pide aceptar los términos al abrirla', (
    tester,
  ) async {
    final store = MemoryVaultStore();
    final terms = TermsAcceptance(MemoryVaultStore());
    final previous = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    await previous.initialize();
    await previous.create('contraseña maestra 1');
    previous.dispose();

    final session = VaultSession(
      store: store,
      cipher: VaultCipher(keyDerivation: FakeKdf()),
      newKdfParams: fastKdfParams,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      CassaforteApp(
        session: session,
        clipboard: ClipboardGuard(clipboard: FakeClipboard()),
        biometric: BiometricUnlock(
          store: MemoryVaultStore(),
          platform: FakeBiometricPlatform()
            ..status = BiometricAvailability.unsupported,
        ),
        backupFiles: FakeBackupFiles(),
        terms: terms,
      ),
    );
    await session.initialize();
    await tester.pumpAndSettle();

    Future<void> unlock() async {
      await tester.enterText(
        find.byType(TextFormField),
        'contraseña maestra 1',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Desbloquear'),
      );
      await tester.pumpAndSettle();
    }

    // Sin aceptar, no se puede usar: vuelve a bloquearse.
    await unlock();
    expect(find.text('Términos de uso'), findsOneWidget);
    await tester.tap(find.text('No acepto'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.locked);
    expect(await terms.isAccepted(), isFalse);

    // Al aceptar, queda registrado y no se vuelve a pedir.
    await unlock();
    await tester.tap(find.text('Acepto'));
    await tester.pumpAndSettle();
    expect(session.status, VaultStatus.unlocked);
    expect(await terms.isAccepted(), isTrue);

    session.lock();
    await tester.pumpAndSettle();
    await unlock();
    expect(find.text('No acepto'), findsNothing);

    // Y se pueden leer desde Ajustes.
    await tester.tap(find.byTooltip('Ajustes y copias'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Términos de uso'));
    await tester.pumpAndSettle();
    expect(find.text('3. Uso «tal cual» y sin garantías'), findsOneWidget);

    session.lock();
    await tester.pump(const Duration(seconds: 5));
  });
}
